# -*- coding: utf-8 -*-
"""Payments recorded at the school on a family's behalf.

Parents pay in cash, by transfer or at the counter, so the finance desk must
be able to settle the same debt the parent portal shows. The money lands in
whichever engine owns the school:

* FinReg-active: the payment is sent through the integration and FinReg
  issues the legal receipt; Cellen keeps a mirror Payment row so the parent's
  portal, cash session and receipt list see it.
* Internal: the payment goes through ``PaymentIntakeService``, which allocates
  it to the invoice and emits the RC exactly like a counter payment.

Both paths are idempotent on ``idempotency_key``: a lost response followed by
a retry resumes the same payment instead of charging the family twice.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finance import CashSession, Payment, PaymentAllocation
from app.models.finreg_integration import FinregBillingInstruction
from app.services.billing_run import BillingError, FINREG_MODES
from app.services.debt_control import list_debts
from app.services.finance import PaymentIntakeService
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import integration_mode
from app.utils.agt import today_luanda

ALLOWED_METHODS = {"cash", "transfer", "card", "check", "mobile", "other"}
METHOD_ALIASES = {
    "multicaixa_ref": "mobile",
    "multicaixa_express": "mobile",
    "bank_transfer": "transfer",
    "mobile_money": "mobile",
}


class InPersonPaymentError(Exception):
    def __init__(self, code: str, detail: str, status_code: int = 409):
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.status_code = status_code


def _method(value: str) -> str:
    normalized = METHOD_ALIASES.get(value, value)
    if normalized not in ALLOWED_METHODS:
        raise InPersonPaymentError(
            "invalid_payment_method",
            "Método de pagamento inválido.",
            422,
        )
    return normalized


async def _open_cash_session(db: AsyncSession, school_id: UUID) -> Optional[CashSession]:
    return (
        await db.execute(
            select(CashSession).where(
                CashSession.school_id == school_id,
                CashSession.status == "open",
            )
        )
    ).scalar_one_or_none()


async def _instruction_for_document(
    db: AsyncSession, *, school_id: UUID, document_id: UUID
) -> Optional[FinregBillingInstruction]:
    return (
        await db.execute(
            select(FinregBillingInstruction)
            .where(
                FinregBillingInstruction.school_id == school_id,
                FinregBillingInstruction.finreg_document_id == document_id,
            )
            .order_by(FinregBillingInstruction.created_at.desc())
        )
    ).scalars().first()


async def _instruction_by_id(
    db: AsyncSession, *, school_id: UUID, instruction_id
) -> Optional[FinregBillingInstruction]:
    if instruction_id is None:
        return None
    return (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == school_id,
                FinregBillingInstruction.id == instruction_id,
            )
        )
    ).scalar_one_or_none()


async def _adapter_for(db: AsyncSession, school_id: UUID):
    mode = await integration_mode(db, school_id)
    return FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter()


async def _settle_finreg(
    adapter,
    *,
    payment: Payment,
    document_id: UUID,
    amount: Decimal,
    payment_method: str,
    payment_date: date,
    actor_reference: str,
) -> None:
    key = f"cellen-inperson-{payment.id}"
    payload = {
        "payment": {
            "document_id": str(document_id),
            "payment_method": payment_method,
            "amount": str(amount),
            "payment_date": payment_date.isoformat(),
            "reference": str(payment.id),
        }
    }
    await adapter.request(
        "POST",
        f"payments/{payment.id}",
        payload,
        idempotency_key=key,
        correlation_id=str(payment.id),
        actor_reference=actor_reference,
    )
    await adapter.request(
        "POST",
        f"payments/{payment.id}/receipt",
        {},
        idempotency_key=f"{key}:receipt",
        correlation_id=str(payment.id),
        actor_reference=actor_reference,
    )


async def _complete_finreg_payment(
    db: AsyncSession,
    adapter,
    *,
    payment: Payment,
    document_id: UUID,
    actor_reference: str,
) -> Payment:
    try:
        await _settle_finreg(
            adapter,
            payment=payment,
            document_id=document_id,
            amount=payment.amount,
            payment_method=payment.payment_method,
            payment_date=payment.payment_date,
            actor_reference=actor_reference,
        )
    except FinregError as exc:
        if exc.retryable:
            # The row stays pending_finreg; retrying with the same
            # idempotency key resumes this exact payment.
            raise InPersonPaymentError(
                exc.code,
                f"O FinReg não confirmou o pagamento: {exc.detail}",
                503,
            ) from exc
        payment.status = "rejected"
        payment.notes = " · ".join(
            part for part in (payment.notes, f"[FinReg] {exc.detail}") if part
        )
        await db.commit()
        raise InPersonPaymentError(exc.code, exc.detail, 422) from exc

    payment.status = "normal"
    payment.finreg_payment_external_reference = payment.id
    await db.commit()
    await db.refresh(payment)
    return payment


async def record_in_person_payment(
    db: AsyncSession,
    *,
    school_id: UUID,
    document_id: UUID,
    amount: Decimal,
    payment_method: str,
    payment_date: Optional[date] = None,
    notes: Optional[str] = None,
    reference: Optional[str] = None,
    received_by: Optional[UUID] = None,
    idempotency_key: Optional[str] = None,
    actor_reference: str = "cellen-finance",
    adapter=None,
) -> Payment:
    method = _method(payment_method)
    if amount is None or amount <= 0:
        raise InPersonPaymentError(
            "invalid_amount", "O valor do pagamento deve ser maior do que zero.", 422
        )
    when = payment_date or today_luanda()

    existing = None
    if idempotency_key:
        existing = (
            await db.execute(
                select(Payment).where(
                    Payment.school_id == school_id,
                    Payment.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one_or_none()
        if existing is not None and existing.status == "normal":
            return existing
        if existing is not None and existing.status == "pending_finreg":
            # The previous attempt reached FinReg but its answer was lost.
            # The document may already be settled there, so do not look it up
            # among the open debts again -- resume the same payment instead.
            instruction = await _instruction_by_id(
                db,
                school_id=school_id,
                instruction_id=existing.finreg_document_external_reference,
            )
            if instruction is None or instruction.finreg_document_id is None:
                raise InPersonPaymentError(
                    "payment_pending",
                    "O pagamento anterior ainda está a ser confirmado pelo "
                    "FinReg. Tente novamente dentro de momentos.",
                    409,
                )
            return await _complete_finreg_payment(
                db,
                adapter or await _adapter_for(db, school_id),
                payment=existing,
                document_id=instruction.finreg_document_id,
                actor_reference=actor_reference,
            )
        if existing is not None and existing.status == "rejected":
            raise InPersonPaymentError(
                "payment_rejected",
                "O pagamento anterior foi rejeitado. Inicie um novo registo.",
                409,
            )
        if existing is not None:
            raise InPersonPaymentError(
                "payment_conflict",
                "Este registo de pagamento já existe com outro estado.",
                409,
            )

    try:
        debts = await list_debts(db, school_id=school_id, adapter=adapter)
    except BillingError as exc:
        raise InPersonPaymentError(exc.code, exc.detail, exc.status_code) from exc

    row = next(
        (
            item
            for item in debts.get("rows", [])
            if str(item.get("document_id")) == str(document_id)
        ),
        None,
    )
    if row is None:
        raise InPersonPaymentError(
            "debt_not_found",
            "Dívida não encontrada ou já liquidada.",
            404,
        )

    outstanding = Decimal(str(row.get("outstanding") or 0))
    if amount > outstanding + Decimal("0.01"):
        raise InPersonPaymentError(
            "amount_above_balance",
            "O valor excede o saldo em dívida deste documento.",
            422,
        )

    guardian_id = row.get("guardian_id")
    try:
        guardian_uuid = UUID(str(guardian_id))
    except (TypeError, ValueError) as exc:
        raise InPersonPaymentError(
            "guardian_missing",
            "Não foi possível identificar o encarregado desta dívida.",
            409,
        ) from exc

    cash_session_id = None
    if method in ("cash", "check"):
        session = await _open_cash_session(db, school_id)
        if session is None:
            raise InPersonPaymentError(
                "cash_session_closed",
                "Não existe sessão de caixa aberta. Abra uma sessão antes de "
                "registar pagamentos em dinheiro ou cheque.",
                400,
            )
        cash_session_id = session.id

    note_parts = [part for part in (notes, reference and f"Ref: {reference}") if part]
    combined_notes = " · ".join(note_parts) or None

    source = row.get("source") or (
        "finreg"
        if (await integration_mode(db, school_id)) in FINREG_MODES
        else "internal"
    )

    if source == "internal":
        intake = PaymentIntakeService(db, school_id)
        try:
            payment = await intake.intake(
                billing_guardian_id=guardian_uuid,
                amount=amount,
                payment_method=method,
                payment_date=when,
                target_invoice_ids=[document_id],
                received_by=received_by,
                cash_session_id=cash_session_id,
                idempotency_key=idempotency_key,
                notes=combined_notes,
            )
        except ValueError as exc:
            raise InPersonPaymentError(
                "payment_rejected", str(exc), 422
            ) from exc
        await db.commit()
        await db.refresh(payment)
        return payment

    # FinReg-active: persist the mirror row first so a lost response cannot
    # create a second payment; the FinReg call is idempotent on its id.
    payment = existing
    if payment is None:
        payment = Payment(
            school_id=school_id,
            billing_guardian_id=guardian_uuid,
            received_by=received_by,
            payment_date=when,
            amount=amount,
            payment_method=method,
            notes=combined_notes,
            status="pending_finreg",
            idempotency_key=idempotency_key,
            cash_session_id=cash_session_id,
        )
        instruction = await _instruction_for_document(
            db, school_id=school_id, document_id=document_id
        )
        if instruction is not None:
            payment.finreg_document_external_reference = instruction.id
        db.add(payment)
        try:
            await db.commit()
        except IntegrityError:
            # A concurrent retry with the same key won the race.
            await db.rollback()
            payment = (
                await db.execute(
                    select(Payment).where(
                        Payment.school_id == school_id,
                        Payment.idempotency_key == idempotency_key,
                    )
                )
            ).scalar_one()
            if payment.status == "normal":
                return payment
    return await _complete_finreg_payment(
        db,
        adapter or await _adapter_for(db, school_id),
        payment=payment,
        document_id=document_id,
        actor_reference=actor_reference,
    )


async def payment_allocations(
    db: AsyncSession, *, payment_id: UUID
) -> list[dict]:
    rows = (
        await db.execute(
            select(PaymentAllocation).where(
                PaymentAllocation.payment_id == payment_id
            )
        )
    ).scalars().all()
    return [
        {
            "invoice_id": str(allocation.invoice_id),
            "amount_applied": float(allocation.amount_applied),
        }
        for allocation in rows
    ]
