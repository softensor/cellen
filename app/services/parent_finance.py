# -*- coding: utf-8 -*-
"""Parent-facing projection of the school's billing documents.

The parent portal asks one question: what does this family owe, for which
child and month, and what can be paid now? FinReg owns the balances while a
school is FinReg-active, but the monthly documents are created by Cellen's
outbox, so neither side alone can answer it:

* Cellen's instruction knows the pupil, the month and the composed amount;
* FinReg's receivable knows the authoritative balance, due date and status.

This module joins the two without inventing numbers: when FinReg answers, its
balance wins; when the engine is unreachable (or the school is internal), the
document falls back to the amount Cellen composed and the payments Cellen
recorded locally. A document whose instruction is not confirmed yet is shown
as *processing* -- visible to the family, never payable.

Family visibility is deliberately broader than the payer: any guardian linked
to the pupil sees the pupil's documents and can pay them, because in a real
family either parent may walk into the school or open the portal.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from typing import Iterable, Optional
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finance import Payment, PaymentReference
from app.models.finreg_integration import FinregBillingInstruction
from app.models.person import ChildGuardian
from app.services.finreg import FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import integration_mode
from app.utils.agt import now_luanda, today_luanda

RECEIVABLE_PAGE_SIZE = 2000
RECEIVABLE_MAX_PAGES = 5
PAID_EPSILON = Decimal("0.005")
# Only a pilot/live connection has finalized documents FinReg can answer for.
# Fake mode runs on the test double; shadow mode leaves the month in drafts.
FEED_MODES = {"pilot", "live"}


def _money(value) -> float:
    return round(float(value or 0), 2)


def _decimal(value) -> Decimal:
    try:
        return Decimal(str(value if value is not None else 0))
    except (InvalidOperation, ValueError):
        return Decimal("0")


def instruction_context(instruction: FinregBillingInstruction) -> dict:
    """The school context of an instruction, whatever command staged it.

    Monthly runs carry it under ``plan.context``; one-off drafts (enrolment,
    modality, late fee) carry it under ``draft.context``. Reading only one of
    the two is what left every monthly row without a child or a month.
    """
    payload = instruction.payload or {}
    for container in ("plan", "draft"):
        context = (payload.get(container) or {}).get("context")
        if context:
            return dict(context)
    return {}


def instruction_pupil_id(instruction: FinregBillingInstruction) -> Optional[str]:
    pupil_id = instruction_context(instruction).get("pupil_id")
    return str(pupil_id) if pupil_id else None


def plan_gross_total(plan: dict) -> float:
    """Gross amount of a recurring plan, from the lines Cellen composed.

    FinReg's run response carries the document id but no amounts, so this is
    the local truth for a monthly document until the receivable feed answers.
    """
    template = (plan or {}).get("template") or {}
    total = Decimal("0")
    for line in template.get("lines") or []:
        quantity = _decimal(line.get("quantity"))
        unit_price = _decimal(line.get("unit_price"))
        discount = _decimal(line.get("discount_pct"))
        tax_rate = _decimal(line.get("tax_rate"))
        net = quantity * unit_price * (Decimal("1") - discount / Decimal("100"))
        total += net * (Decimal("1") + tax_rate / Decimal("100"))
    return float(total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _snapshot_gross_total(snapshot: dict) -> float:
    for key in ("gross_total", "total", "amount"):
        if snapshot.get(key) is not None:
            return _money(snapshot.get(key))
    return 0.0


def document_gross_total(instruction: FinregBillingInstruction) -> float:
    payload = instruction.payload or {}
    gross = plan_gross_total(payload.get("plan") or {})
    if gross > 0:
        return gross
    gross = _snapshot_gross_total(instruction.result_snapshot or {})
    if gross > 0:
        return gross
    draft = payload.get("draft") or {}
    return plan_gross_total(
        {
            "template": {
                "lines": (draft.get("document") or {}).get("lines") or [],
            }
        }
    )


def reference_month(
    instruction: FinregBillingInstruction, context: dict
) -> Optional[str]:
    value = context.get("billing_period") or (instruction.payload or {}).get(
        "billing_month"
    )
    if not value:
        return None
    text = str(value)
    if len(text) == 7:
        return f"{text}-01"
    if len(text) >= 10:
        return text[:10]
    return None


def due_date_for(
    instruction: FinregBillingInstruction, context: dict
) -> Optional[str]:
    plan = (instruction.payload or {}).get("plan") or {}
    template = plan.get("template") or {}
    raw_run_date = (instruction.payload or {}).get("run_date")
    due_days = template.get("due_days")
    if raw_run_date and due_days is not None:
        try:
            run_date = date.fromisoformat(str(raw_run_date)[:10])
            return (run_date + timedelta(days=int(due_days))).isoformat()
        except (TypeError, ValueError):
            pass
    snapshot = instruction.result_snapshot or {}
    return snapshot.get("due_date") or snapshot.get("document_date")


async def linked_child_ids(
    db: AsyncSession, *, school_id: UUID, guardian_id: UUID
) -> set[str]:
    rows = (
        await db.execute(
            select(ChildGuardian.child_id).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.school_id == school_id,
            )
        )
    ).all()
    return {str(row[0]) for row in rows}


async def guardian_can_view_instruction(
    db: AsyncSession,
    *,
    school_id: UUID,
    guardian_id: UUID,
    instruction: FinregBillingInstruction,
) -> bool:
    payload = instruction.payload or {}
    payer = str((payload.get("guardian") or {}).get("external_id") or "")
    if payer == str(guardian_id):
        return True
    pupil_id = instruction_pupil_id(instruction)
    if not pupil_id:
        return False
    return pupil_id in await linked_child_ids(
        db, school_id=school_id, guardian_id=guardian_id
    )


async def _visible_instructions(
    db: AsyncSession, *, school_id: UUID, guardian_id: UUID
) -> list[FinregBillingInstruction]:
    linked = await linked_child_ids(
        db, school_id=school_id, guardian_id=guardian_id
    )
    conditions = [
        FinregBillingInstruction.payload["guardian"]["external_id"].astext
        == str(guardian_id)
    ]
    if linked:
        conditions.append(
            FinregBillingInstruction.payload["plan"]["context"]["pupil_id"].astext.in_(
                linked
            )
        )
        conditions.append(
            FinregBillingInstruction.payload["draft"]["context"]["pupil_id"].astext.in_(
                linked
            )
        )
    rows = (
        await db.execute(
            select(FinregBillingInstruction)
            .where(
                FinregBillingInstruction.school_id == school_id,
                FinregBillingInstruction.status.in_(
                    ("confirmed", "pending", "processing", "unknown")
                ),
                FinregBillingInstruction.finreg_document_id.is_not(None),
                or_(*conditions),
            )
            .order_by(FinregBillingInstruction.created_at.desc())
        )
    ).scalars().all()
    return list(rows)


async def visible_instruction_ids(
    db: AsyncSession, *, school_id: UUID, guardian_id: UUID
) -> list[UUID]:
    """Instruction ids in the family's scope, for receipts and proofs."""
    rows = await _visible_instructions(
        db, school_id=school_id, guardian_id=guardian_id
    )
    return [item.id for item in rows]


async def family_billing_guardian_id(
    db: AsyncSession, *, school_id: UUID, guardian_id: UUID
) -> Optional[UUID]:
    """The single payer behind the family's confirmed documents, if unambiguous.

    A second parent has no FinReg customer of their own (only the billing
    guardian is upserted), so their statement is the family payer's statement.
    With more than one payer there is no single customer to proxy and the
    caller keeps its own answer.
    """
    rows = await _visible_instructions(
        db, school_id=school_id, guardian_id=guardian_id
    )
    payers = {
        str((item.payload or {}).get("guardian", {}).get("external_id"))
        for item in rows
        if item.status == "confirmed"
    }
    payers.discard("")
    if len(payers) != 1:
        return None
    try:
        return UUID(payers.pop())
    except ValueError:
        return None


async def _open_receivables(
    adapter, *, school_id: UUID, customer_external_ids: Iterable[str]
) -> Optional[dict[str, dict]]:
    """Index FinReg's open receivables by document id.

    ``None`` means the feed could not be read; callers must then fall back to
    locally composed amounts instead of assuming a missing document is paid.
    """
    index: dict[str, dict] = {}
    for external_id in sorted({value for value in customer_external_ids if value}):
        offset = 0
        for _ in range(RECEIVABLE_MAX_PAGES):
            operation = (
                "receivables?customer_external_id="
                f"{external_id}&overdue_only=false"
                f"&limit={RECEIVABLE_PAGE_SIZE}&offset={offset}"
            )
            try:
                payload = await adapter.request(
                    "GET",
                    operation,
                    None,
                    actor_reference=f"cellen-parent:{school_id}",
                )
            except FinregError:
                return None
            rows = (payload or {}).get("rows") or []
            for row in rows:
                document_id = row.get("document_id")
                if document_id:
                    index[str(document_id)] = row
            if len(rows) < RECEIVABLE_PAGE_SIZE:
                break
            offset += RECEIVABLE_PAGE_SIZE
    return index


async def outstanding_for_instruction(
    db: AsyncSession,
    *,
    school_id: UUID,
    instruction: FinregBillingInstruction,
    adapter=None,
) -> float:
    """What is still owed on one document, without trusting a run snapshot.

    Monthly run instructions carry no amounts in ``result_snapshot``; reading
    only that is why a parent's proof form defaulted to zero.
    """
    if instruction.finreg_document_id is not None:
        mode = await integration_mode(db, school_id)
        if adapter is None and mode in FEED_MODES:
            adapter = HttpFinregAdapter()
        if adapter is not None:
            payer = str(
                (instruction.payload or {}).get("guardian", {}).get("external_id")
                or ""
            )
            receivables = await _open_receivables(
                adapter, school_id=school_id, customer_external_ids=[payer]
            )
            if receivables is not None:
                row = receivables.get(str(instruction.finreg_document_id))
                if row is not None:
                    return max(_money(row.get("outstanding_amount")), 0.0)
                return 0.0

    gross = document_gross_total(instruction)
    payments = await _payments_by_instruction(
        db, school_id=school_id, instruction_ids=[instruction.id]
    )
    paid = sum(
        _decimal(payment.amount)
        for payment in payments.get(str(instruction.id), [])
        if payment.status == "normal"
    )
    return max(gross - float(paid), 0.0)


async def _payments_by_instruction(
    db: AsyncSession,
    *,
    school_id: UUID,
    instruction_ids: list[UUID],
) -> dict[str, list[Payment]]:
    if not instruction_ids:
        return {}
    rows = (
        await db.execute(
            select(Payment)
            .where(
                Payment.school_id == school_id,
                Payment.finreg_document_external_reference.in_(instruction_ids),
            )
            .order_by(Payment.created_at)
        )
    ).scalars().all()
    grouped: dict[str, list[Payment]] = {}
    for payment in rows:
        grouped.setdefault(
            str(payment.finreg_document_external_reference), []
        ).append(payment)
    return grouped


def _fallback_state(
    *,
    gross: float,
    due: Optional[str],
    payments: list[Payment],
) -> tuple[str, float, float]:
    paid = sum(
        _decimal(payment.amount)
        for payment in payments
        if payment.status == "normal"
    )
    paid_float = float(paid)
    balance = max(gross - paid_float, 0.0)
    if gross > 0 and paid >= _decimal(gross) - PAID_EPSILON:
        return "paid", gross, 0.0
    overdue = False
    if due:
        try:
            overdue = date.fromisoformat(due[:10]) < today_luanda()
        except ValueError:
            overdue = False
    if paid_float > 0:
        return "partially_paid", paid_float, balance
    return ("overdue" if overdue else "pending"), paid_float, balance


async def _active_rail_references(
    db: AsyncSession, *, school_id: UUID, document_ids: Iterable[UUID]
) -> dict[str, dict]:
    """The open payment reference per FinReg document, keyed by document id.

    The card is where a guardian looks for the Multicaixa digits, not a
    banner at the top of the list: without this join the parent screen says
    "Referência de pagamento não disponível" even after a reference exists.
    """
    ids = [document_id for document_id in document_ids if document_id]
    if not ids:
        return {}
    rows = (
        await db.execute(
            select(PaymentReference)
            .where(
                PaymentReference.school_id == school_id,
                PaymentReference.finreg_document_id.in_(ids),
                PaymentReference.status.in_(("creating", "active")),
                or_(
                    PaymentReference.expires_at.is_(None),
                    PaymentReference.expires_at > now_luanda(),
                ),
            )
            .order_by(PaymentReference.created_at.desc())
        )
    ).scalars().all()
    by_document: dict[str, dict] = {}
    for reference in rows:
        key = str(reference.finreg_document_id)
        if key in by_document:
            continue
        by_document[key] = {
            "id": str(reference.id),
            "entity": reference.entity,
            "reference": reference.reference,
            "amount": _money(reference.amount),
            "status": reference.status,
            "provider": reference.provider,
            "checkout_url": reference.checkout_url,
            "expires_at": (
                reference.expires_at.isoformat() if reference.expires_at else None
            ),
        }
    return by_document


async def list_parent_documents(
    db: AsyncSession,
    *,
    school_id: UUID,
    guardian_id: UUID,
    adapter=None,
) -> list[dict]:
    """Every document the family may see, with real amounts and status."""
    instructions = await _visible_instructions(
        db, school_id=school_id, guardian_id=guardian_id
    )
    if not instructions:
        return []
    references = await _active_rail_references(
        db,
        school_id=school_id,
        document_ids=[
            item.finreg_document_id
            for item in instructions
            if item.finreg_document_id
        ],
    )

    mode = await integration_mode(db, school_id)
    if adapter is None and mode in FEED_MODES:
        adapter = HttpFinregAdapter()

    receivables: Optional[dict[str, dict]] = None
    if adapter is not None:
        payers = {
            str((item.payload or {}).get("guardian", {}).get("external_id") or "")
            for item in instructions
        }
        receivables = await _open_receivables(
            adapter, school_id=school_id, customer_external_ids=payers
        )

    payments = await _payments_by_instruction(
        db,
        school_id=school_id,
        instruction_ids=[item.id for item in instructions],
    )

    output: list[dict] = []
    for item in instructions:
        context = instruction_context(item)
        gross = document_gross_total(item)
        snapshot = item.result_snapshot or {}
        # A shadow run -- or any document still awaiting finalize -- is not a
        # payable fiscal document: FinReg opens no receivable for a draft, so
        # trusting the feed's absence would read it as settled.
        draft = mode == "shadow" or str(
            snapshot.get("status") or ""
        ).lower() == "draft"
        receivable = (
            receivables.get(str(item.finreg_document_id))
            if receivables is not None and item.finreg_document_id
            else None
        )
        instruction_payments = payments.get(str(item.id), [])

        if item.status != "confirmed":
            status = "processing"
            balance = gross
            amount_paid = 0.0
            due = due_date_for(item, context)
            document_type = snapshot.get("document_type", "invoice")
            document_number = (
                snapshot.get("full_document_number")
                or snapshot.get("document_number")
                or "Em processamento"
            )
        elif draft:
            status = "processing"
            balance = gross
            amount_paid = 0.0
            due = due_date_for(item, context)
            document_type = snapshot.get("document_type", "invoice")
            document_number = (
                snapshot.get("full_document_number")
                or snapshot.get("document_number")
                or "Em processamento"
            )
        elif receivable is not None:
            gross = _money(receivable.get("gross_total") or gross)
            amount_paid = _money(receivable.get("paid_total"))
            balance = _money(receivable.get("outstanding_amount"))
            days_overdue = int(receivable.get("days_overdue") or 0)
            if balance <= 0:
                status = "paid"
                amount_paid = gross
            elif days_overdue > 0:
                status = "overdue"
            elif amount_paid > 0:
                status = "partially_paid"
            else:
                status = "pending"
            due = receivable.get("due_date") or due_date_for(item, context)
            document_type = receivable.get("document_type") or snapshot.get(
                "document_type", "invoice"
            )
            document_number = (
                receivable.get("full_document_number")
                or snapshot.get("full_document_number")
                or snapshot.get("document_number")
                or "Finreg"
            )
        elif receivables is not None:
            # The feed answered and this document is not open any more: it
            # was settled or credited. Show it as paid history, at zero.
            status = "paid" if gross > 0 else "pending"
            balance = 0.0 if gross > 0 else gross
            amount_paid = gross if gross > 0 else 0.0
            due = due_date_for(item, context)
            document_type = snapshot.get("document_type", "invoice")
            document_number = (
                snapshot.get("full_document_number")
                or snapshot.get("document_number")
                or "Finreg"
            )
        else:
            status, amount_paid, balance = _fallback_state(
                gross=gross, due=due_date_for(item, context),
                payments=instruction_payments,
            )
            due = due_date_for(item, context)
            document_type = snapshot.get("document_type", "invoice")
            document_number = (
                snapshot.get("full_document_number")
                or snapshot.get("document_number")
                or "Finreg"
            )

        if gross <= 0 and receivable is None:
            # Nothing payable and nothing recorded: do not invent a row.
            continue

        reference = references.get(str(item.finreg_document_id))
        # Only real digits go into the card's Multicaixa block; a reference
        # still being created has none yet, and an empty box reads worse
        # than "not available yet".
        digits = (
            reference
            if reference
            and reference.get("status") == "active"
            and reference.get("entity")
            and reference.get("reference")
            else None
        )
        output.append({
            "id": str(item.id),
            "finreg": True,
            # The debt read model and principia-pay key off the FinReg
            # document, not the outbox instruction.
            "document_id": str(item.finreg_document_id)
            if item.finreg_document_id
            else None,
            "payment_reference": reference,
            "multicaixa_entity": digits["entity"] if digits else None,
            "multicaixa_ref": digits["reference"] if digits else None,
            "child_id": context.get("pupil_id"),
            "child_name": context.get("pupil_name") or "—",
            "document_type": document_type,
            "full_document_number": document_number,
            "reference_month": reference_month(item, context),
            "gross_total": gross,
            "status": status,
            "due_date": due,
            "amount_paid": amount_paid,
            "balance": balance,
            "payment_proofs": [
                {
                    "id": str(payment.id),
                    "status": payment.status,
                    "notes": payment.notes,
                    "amount": float(payment.amount),
                    "receipt_proof_url": payment.receipt_proof_url,
                    "created_at": payment.created_at.isoformat()
                    if payment.created_at
                    else None,
                }
                for payment in instruction_payments
            ],
        })

    output.sort(
        key=lambda row: (row.get("reference_month") or "", row.get("due_date") or ""),
        reverse=True,
    )
    return output
