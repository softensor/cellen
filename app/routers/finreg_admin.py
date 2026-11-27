"""Native admin surface over FinReg's fiscal documents.

The school's finance staff never open FinReg. These routes serve Cellen's own
screens from the local ledger (``FinregDocument``) and reach FinReg server to
server only for what must be authoritative and fresh: a document's current
state, its official PDF, and fiscal mutations.
"""
from __future__ import annotations

import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from fastapi.responses import Response
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_school_id, require_finance_access
from app.models.finance import Payment
from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregDocument,
    FinregSchoolConnection,
)
from app.models.user import User
from app.models.person import Child, Guardian
from app.services import finreg_ledger
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import (
    CORRECTION_COMMAND,
    dispatch_instruction,
    enqueue_billing_instruction,
)
from app.services.finreg_errors import explain_stored, http_error

router = APIRouter(prefix="/finreg/admin", tags=["Finreg Native Admin"])

PENDING_AGT = {"pending", "queued", "submitted", "processing", "sent", "not_sent"}
REJECTED_AGT = {"rejected", "invalid", "error", "failed"}


async def _connection(db: AsyncSession, school_id) -> FinregSchoolConnection | None:
    return (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()


async def adapter_for(db: AsyncSession, school_id):
    """The adapter this school's documents live behind, or a 409."""
    connection = await _connection(db, school_id)
    if not settings.FINREG_INTEGRATION_ENABLED or connection is None or connection.mode == "disabled" or connection.kill_switch:
        raise HTTPException(status_code=409, detail={
            "code": "finreg_not_operational",
            "message": "A faturação fiscal não está activa para esta escola.",
        })
    return FakeFinregAdapter() if connection.mode == "fake" else HttpFinregAdapter()


def agt_state(row: FinregDocument) -> str:
    """One school-facing state per document, in the order a person reads it."""
    if row.document_status == "cancelled":
        return "cancelled"
    if row.document_status == "draft":
        return "processing"
    agt = str(row.agt_status or "").lower()
    if agt in REJECTED_AGT:
        return "rejected"
    if agt in PENDING_AGT or (not agt and row.needs_refresh):
        return "submitted"
    return "issued"


def _float(value) -> float | None:
    return None if value is None else float(value)


def serialize(row: FinregDocument, names: dict[uuid.UUID, str] | None = None) -> dict:
    names = names or {}
    return {
        "id": str(row.id),
        "finreg_document_id": str(row.finreg_document_id),
        "instruction_id": str(row.instruction_id) if row.instruction_id else None,
        "kind": row.kind,
        "document_type": row.document_type,
        "full_document_number": row.full_document_number,
        "document_status": row.document_status,
        "agt_status": row.agt_status,
        "agt_message": row.agt_message,
        "state": agt_state(row),
        "currency_code": row.currency_code,
        "net_total": _float(row.net_total),
        "tax_total": _float(row.tax_total),
        "gross_total": _float(row.gross_total),
        "document_date": row.document_date.isoformat() if row.document_date else None,
        "due_date": row.due_date.isoformat() if row.due_date else None,
        "billing_period": row.billing_period,
        "customer_name": row.customer_name or names.get(row.guardian_id),
        "customer_tax_id": row.customer_tax_id,
        "guardian_id": str(row.guardian_id) if row.guardian_id else None,
        "guardian_name": names.get(row.guardian_id),
        "pupil_id": str(row.pupil_id) if row.pupil_id else None,
        "pupil_name": names.get(row.pupil_id),
        "corrects_document_id": str(row.corrects_document_id) if row.corrects_document_id else None,
        "corrected_by_document_id": (
            str(row.corrected_by_document_id) if row.corrected_by_document_id else None
        ),
        "refreshed_at": row.refreshed_at.isoformat() if row.refreshed_at else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


async def names_for(db: AsyncSession, school_id, rows: list[FinregDocument]) -> dict[uuid.UUID, str]:
    guardian_ids = {row.guardian_id for row in rows if row.guardian_id}
    pupil_ids = {row.pupil_id for row in rows if row.pupil_id}
    names: dict[uuid.UUID, str] = {}
    if guardian_ids:
        for guardian in (await db.execute(select(Guardian).where(
            Guardian.school_id == school_id, Guardian.id.in_(guardian_ids)
        ))).scalars():
            names[guardian.id] = f"{guardian.first_name} {guardian.last_name}".strip()
    if pupil_ids:
        for child in (await db.execute(select(Child).where(
            Child.school_id == school_id, Child.id.in_(pupil_ids)
        ))).scalars():
            names[child.id] = f"{child.first_name} {child.last_name}".strip()
    return names


async def owned_document(db: AsyncSession, school_id, document_id: uuid.UUID) -> FinregDocument:
    row = await db.get(FinregDocument, document_id)
    if row is None or row.school_id != school_id:
        raise HTTPException(status_code=404, detail="Documento não encontrado")
    return row


@router.get("/documents")
async def list_documents(
    kind: str | None = Query(None, description="Comma-separated: invoice,invoice_receipt,credit_note,debit_note"),
    state: str | None = Query(None, pattern="^(processing|submitted|issued|rejected|cancelled)$"),
    q: str | None = Query(None, max_length=120),
    guardian_id: uuid.UUID | None = None,
    pupil_id: uuid.UUID | None = None,
    period: str | None = Query(None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$"),
    date_from: date | None = None,
    date_to: date | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    # Cheap and local: ledgers anything the outbox confirmed before the
    # ledger existed, so the first visit is already complete.
    if await finreg_ledger.backfill(db, school_id):
        await db.commit()

    conditions = [FinregDocument.school_id == school_id]
    if kind:
        kinds = [item.strip() for item in kind.split(",") if item.strip()]
        conditions.append(FinregDocument.kind.in_(kinds))
    if guardian_id:
        conditions.append(FinregDocument.guardian_id == guardian_id)
    if pupil_id:
        conditions.append(FinregDocument.pupil_id == pupil_id)
    if period:
        conditions.append(FinregDocument.billing_period == period)
    if date_from:
        conditions.append(FinregDocument.document_date >= date_from)
    if date_to:
        conditions.append(FinregDocument.document_date <= date_to)
    if q:
        pattern = f"%{q.strip()}%"
        guardian_match = select(Guardian.id).where(
            Guardian.school_id == school_id,
            or_(
                (Guardian.first_name + " " + Guardian.last_name).ilike(pattern),
                Guardian.nif.ilike(pattern),
            ),
        )
        pupil_match = select(Child.id).where(
            Child.school_id == school_id,
            (Child.first_name + " " + Child.last_name).ilike(pattern),
        )
        conditions.append(or_(
            FinregDocument.full_document_number.ilike(pattern),
            FinregDocument.customer_name.ilike(pattern),
            FinregDocument.customer_tax_id.ilike(pattern),
            FinregDocument.guardian_id.in_(guardian_match),
            FinregDocument.pupil_id.in_(pupil_match),
        ))

    ordered = select(FinregDocument).where(*conditions).order_by(
        FinregDocument.document_date.desc().nulls_first(),
        FinregDocument.created_at.desc(),
    )
    if state:
        # The school-facing state combines three FinReg fields; filtering a
        # school's ledger in memory is cheap and keeps one definition of it.
        rows = [row for row in (await db.execute(ordered)).scalars() if agt_state(row) == state]
        total = len(rows)
        page = rows[offset:offset + limit]
    else:
        total = (await db.execute(
            select(func.count()).select_from(FinregDocument).where(*conditions)
        )).scalar_one()
        page = (await db.execute(ordered.offset(offset).limit(limit))).scalars().all()
    names = await names_for(db, school_id, page)

    attention = (await db.execute(select(FinregDocument).where(
        FinregDocument.school_id == school_id,
        FinregDocument.document_status != "cancelled",
        or_(
            FinregDocument.needs_refresh.is_(True),
            func.lower(func.coalesce(FinregDocument.agt_status, "")).in_(REJECTED_AGT),
        ),
    ))).scalars().all()
    summary = {"processing": 0, "submitted": 0, "rejected": 0}
    for row in attention:
        current = agt_state(row)
        if current in summary:
            summary[current] += 1
    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "summary": summary,
        "items": [serialize(row, names) for row in page],
    }


@router.get("/documents/{document_id}")
async def document_detail(
    document_id: uuid.UUID,
    refresh: bool = False,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    row = await owned_document(db, school_id, document_id)
    stale = False
    if refresh:
        try:
            await finreg_ledger.refresh_document(
                db, row, adapter=await adapter_for(db, school_id), actor_reference=str(user.id)
            )
        except (FinregError, HTTPException):
            stale = True
        await db.commit()
    names = await names_for(db, school_id, [row])
    body = serialize(row, names)
    snapshot = row.snapshot or {}
    body["lines"] = [
        {
            "description": line.get("description"),
            "quantity": line.get("quantity"),
            "unit_price": line.get("unit_price"),
            "discount_pct": line.get("discount_pct"),
            "tax_rate": line.get("tax_rate"),
            "line_total": line.get("line_total") or line.get("gross_total") or line.get("total"),
        }
        for line in snapshot.get("lines") or []
    ]
    body["software_cert_number"] = snapshot.get("software_cert_number")
    body["agt_digital_code"] = snapshot.get("agt_digital_code")
    body["stale"] = stale
    related_ids = [
        value for value in (row.corrects_document_id, row.corrected_by_document_id) if value
    ]
    related = []
    if related_ids:
        related = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.finreg_document_id.in_(related_ids),
        ))).scalars().all()
    body["related"] = [serialize(item, names) for item in related]
    return body


@router.post("/documents/{document_id}/refresh")
async def refresh_document(
    document_id: uuid.UUID,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    row = await owned_document(db, school_id, document_id)
    adapter = await adapter_for(db, school_id)
    try:
        await finreg_ledger.refresh_document(db, row, adapter=adapter, actor_reference=str(user.id))
    except FinregError as exc:
        await db.commit()
        raise http_error(exc) from exc
    await db.commit()
    return serialize(row, await names_for(db, school_id, [row]))


@router.get("/documents/{document_id}/pdf")
async def document_pdf(
    document_id: uuid.UUID,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    row = await owned_document(db, school_id, document_id)
    if row.document_status == "draft":
        raise HTTPException(status_code=409, detail={
            "code": "document_not_finalized",
            "message": "O documento ainda está a ser emitido. Tente dentro de instantes.",
        })
    adapter = await adapter_for(db, school_id)
    if isinstance(adapter, FakeFinregAdapter):
        raise HTTPException(status_code=409, detail={
            "code": "fake_mode",
            "message": "O modo de teste não gera PDFs fiscais.",
        })
    try:
        content = await adapter.download(
            f"documents/{row.reference}/pdf", actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise http_error(exc) from exc
    filename = (row.full_document_number or str(row.finreg_document_id)).replace("/", "-").replace(" ", "_")
    return Response(content=content, media_type="application/pdf", headers={
        "Content-Disposition": f'inline; filename="{filename}.pdf"'
    })


# ── Corrections (credit notes) ──────────────────────────────────────────────

CORRECTABLE_KINDS = {"invoice", "invoice_receipt", "debit_note"}
OPEN_STATUSES = {"pending", "processing", "unknown"}


class CorrectionRequest(BaseModel):
    request_id: uuid.UUID
    reason: str = Field(min_length=3, max_length=250)


def _instruction_state(instruction: FinregBillingInstruction) -> str:
    if instruction.status == "confirmed":
        return "confirmed"
    if instruction.status == "rejected":
        return "rejected"
    return "processing"


@router.post("/documents/{document_id}/corrections", status_code=201)
async def correct_document(
    document_id: uuid.UUID,
    body: CorrectionRequest,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    """Cancel a fiscal document; FinReg issues the credit note.

    ``request_id`` is minted by the screen once per dialog, so pressing the
    button again after a timeout resends the same correction, never a second.
    """
    row = await owned_document(db, school_id, document_id)
    connection = await _connection(db, school_id)
    if (
        not settings.FINREG_INTEGRATION_ENABLED
        or connection is None
        or connection.kill_switch
        or connection.mode not in {"fake", "pilot", "live"}
    ):
        raise HTTPException(status_code=409, detail={
            "code": "finreg_writes_disabled",
            "message": "As operações fiscais não estão activas para esta escola.",
        })
    key = f"cellen-correction-{body.request_id}"
    existing = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.idempotency_key == key,
    ))).scalar_one_or_none()
    if existing is None:
        if row.kind not in CORRECTABLE_KINDS:
            raise HTTPException(status_code=409, detail={
                "code": "document_not_correctable",
                "message": "Este tipo de documento não pode ser anulado.",
            })
        if row.document_status == "cancelled":
            raise HTTPException(status_code=409, detail={
                "code": "document_already_cancelled",
                "message": "Este documento já foi anulado.",
            })
        if row.document_status != "finalized":
            raise HTTPException(status_code=409, detail={
                "code": "document_not_finalized",
                "message": "O documento ainda está a ser emitido.",
            })
        in_flight = (await db.execute(select(FinregBillingInstruction).where(
            FinregBillingInstruction.school_id == school_id,
            FinregBillingInstruction.command_type == CORRECTION_COMMAND,
            FinregBillingInstruction.status.in_(OPEN_STATUSES),
            FinregBillingInstruction.payload["document_id"].astext == str(row.finreg_document_id),
        ))).scalars().first()
        if in_flight is not None:
            raise HTTPException(status_code=409, detail={
                "code": "correction_in_progress",
                "message": "Já existe uma anulação deste documento em curso.",
            })
    instruction, _ = await enqueue_billing_instruction(
        db,
        school_id=school_id,
        idempotency_key=key,
        command_type=CORRECTION_COMMAND,
        payload={
            "document_id": str(row.finreg_document_id),
            "document_reference": row.reference,
            "external_id": str(body.request_id),
            "reason": body.reason.strip(),
            "actor_reference": str(user.id),
        },
    )
    await db.commit()
    if instruction.status in {"pending", "unknown"} and instruction.next_attempt_at is None:
        try:
            await dispatch_instruction(db, instruction)
        except FinregError as exc:
            if not (exc.retryable or exc.unknown_outcome):
                raise http_error(exc) from exc
    credit = None
    if instruction.status == "confirmed" and instruction.finreg_document_id:
        credit = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.finreg_document_id == instruction.finreg_document_id,
        ))).scalar_one_or_none()
    await db.refresh(row)
    names = await names_for(db, school_id, [row] + ([credit] if credit else []))
    return {
        "instruction_id": str(instruction.id),
        "status": _instruction_state(instruction),
        "document": serialize(row, names),
        "credit_note": serialize(credit, names) if credit else None,
    }


# ── Receipts ────────────────────────────────────────────────────────────────

def _receipt(payment: Payment, names: dict, documents: dict) -> dict:
    document = documents.get(payment.finreg_document_external_reference)
    return {
        "id": str(payment.id),
        "payment_date": payment.payment_date.isoformat() if payment.payment_date else None,
        "amount": float(payment.amount),
        "payment_method": payment.payment_method,
        "status": payment.status,
        "guardian_id": str(payment.billing_guardian_id),
        "guardian_name": names.get(payment.billing_guardian_id),
        "document_number": document.full_document_number if document else None,
        "document_id": str(document.id) if document else None,
        "created_at": payment.created_at.isoformat() if payment.created_at else None,
    }


@router.get("/receipts")
async def list_receipts(
    guardian_id: uuid.UUID | None = None,
    q: str | None = Query(None, max_length=120),
    date_from: date | None = None,
    date_to: date | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    conditions = [
        Payment.school_id == school_id,
        Payment.finreg_payment_external_reference.is_not(None),
    ]
    if guardian_id:
        conditions.append(Payment.billing_guardian_id == guardian_id)
    if date_from:
        conditions.append(Payment.payment_date >= date_from)
    if date_to:
        conditions.append(Payment.payment_date <= date_to)
    if q:
        pattern = f"%{q.strip()}%"
        conditions.append(Payment.billing_guardian_id.in_(select(Guardian.id).where(
            Guardian.school_id == school_id,
            or_(
                (Guardian.first_name + " " + Guardian.last_name).ilike(pattern),
                Guardian.nif.ilike(pattern),
            ),
        )))
    total = (await db.execute(
        select(func.count()).select_from(Payment).where(*conditions)
    )).scalar_one()
    payments = (await db.execute(select(Payment).where(*conditions).order_by(
        Payment.payment_date.desc(), Payment.created_at.desc()
    ).offset(offset).limit(limit))).scalars().all()
    guardian_ids = {payment.billing_guardian_id for payment in payments}
    names: dict = {}
    if guardian_ids:
        for guardian in (await db.execute(select(Guardian).where(
            Guardian.school_id == school_id, Guardian.id.in_(guardian_ids)
        ))).scalars():
            names[guardian.id] = f"{guardian.first_name} {guardian.last_name}".strip()
    instruction_ids = {
        payment.finreg_document_external_reference
        for payment in payments if payment.finreg_document_external_reference
    }
    documents: dict = {}
    if instruction_ids:
        for document in (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.instruction_id.in_(instruction_ids),
        ))).scalars():
            documents[document.instruction_id] = document
    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "items": [_receipt(payment, names, documents) for payment in payments],
    }


async def _owned_receipt(db: AsyncSession, school_id, payment_id: uuid.UUID) -> Payment:
    payment = (await db.execute(select(Payment).where(
        Payment.id == payment_id,
        Payment.school_id == school_id,
        Payment.finreg_payment_external_reference.is_not(None),
    ))).scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Recibo não encontrado")
    return payment


@router.get("/receipts/{payment_id}")
async def receipt_detail(
    payment_id: uuid.UUID,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    payment = await _owned_receipt(db, school_id, payment_id)
    guardian = await db.get(Guardian, payment.billing_guardian_id)
    names = {guardian.id: f"{guardian.first_name} {guardian.last_name}".strip()} if guardian else {}
    body = _receipt(payment, names, {})
    body["finreg"] = None
    body["stale"] = False
    try:
        adapter = await adapter_for(db, school_id)
        if not isinstance(adapter, FakeFinregAdapter):
            receipt = await adapter.request(
                "GET", f"receipts/{payment.finreg_payment_external_reference}", None,
                actor_reference=str(user.id),
            )
            if isinstance(receipt, dict):
                body["finreg"] = {
                    "full_document_number": receipt.get("full_document_number"),
                    "document_status": receipt.get("document_status"),
                    "agt_status": receipt.get("agt_status"),
                    "gross_total": receipt.get("gross_total"),
                    "document_date": receipt.get("document_date"),
                }
    except (FinregError, HTTPException):
        body["stale"] = True
    return body


@router.get("/receipts/{payment_id}/pdf")
async def receipt_pdf(
    payment_id: uuid.UUID,
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    payment = await _owned_receipt(db, school_id, payment_id)
    adapter = await adapter_for(db, school_id)
    if isinstance(adapter, FakeFinregAdapter):
        raise HTTPException(status_code=409, detail={
            "code": "fake_mode",
            "message": "O modo de teste não gera PDFs fiscais.",
        })
    try:
        content = await adapter.download(
            f"receipts/{payment.finreg_payment_external_reference}/pdf",
            actor_reference=str(user.id),
        )
    except FinregError as exc:
        raise http_error(exc) from exc
    return Response(content=content, media_type="application/pdf", headers={
        "Content-Disposition": f'inline; filename="recibo-{payment.id}.pdf"'
    })


# ── Fiscal activity (audit log) ─────────────────────────────────────────────

COMMAND_LABELS = {
    "billing_run": "Faturação mensal",
    "billing_plan_upsert": "Plano de faturação",
    "issue_invoice": "Fatura avulsa",
    "enrollment_fee": "Taxa de matrícula",
    "modality_inscription_fee": "Inscrição em modalidade",
    "late_fee": "Multa por atraso",
    "correction": "Anulação (nota de crédito)",
}


@router.get("/activity")
async def fiscal_activity(
    status: str | None = Query(None, pattern="^(confirmed|processing|rejected)$"),
    command: str | None = Query(None, max_length=50),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    """Every fiscal instruction Cellen sent FinReg: who, when, what, outcome."""
    conditions = [FinregBillingInstruction.school_id == school_id]
    if status == "confirmed":
        conditions.append(FinregBillingInstruction.status == "confirmed")
    elif status == "rejected":
        conditions.append(FinregBillingInstruction.status == "rejected")
    elif status == "processing":
        conditions.append(FinregBillingInstruction.status.in_(OPEN_STATUSES))
    if command:
        conditions.append(FinregBillingInstruction.command_type == command)
    total = (await db.execute(
        select(func.count()).select_from(FinregBillingInstruction).where(*conditions)
    )).scalar_one()
    rows = (await db.execute(select(FinregBillingInstruction).where(*conditions).order_by(
        FinregBillingInstruction.created_at.desc()
    ).offset(offset).limit(limit))).scalars().all()

    actor_ids = set()
    for row in rows:
        actor = _uuid_or_none((row.payload or {}).get("actor_reference"))
        if actor:
            actor_ids.add(actor)
    actors = {}
    if actor_ids:
        for account in (await db.execute(select(User).where(User.id.in_(actor_ids)))).scalars():
            actors[account.id] = account.username
    document_ids = {row.finreg_document_id for row in rows if row.finreg_document_id}
    documents = {}
    if document_ids:
        for document in (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.finreg_document_id.in_(document_ids),
        ))).scalars():
            documents[document.finreg_document_id] = document

    items = []
    for row in rows:
        actor = _uuid_or_none((row.payload or {}).get("actor_reference"))
        document = documents.get(row.finreg_document_id)
        items.append({
            "id": str(row.id),
            "command": row.command_type,
            "label": COMMAND_LABELS.get(row.command_type, row.command_type),
            "status": _instruction_state(row),
            "raw_status": row.status,
            "attempts": row.attempts,
            "error_code": row.error_code,
            "error_detail": explain_stored(row.error_code, row.error_detail, status=row.status),
            "support_detail": row.error_detail,
            "actor": actors.get(actor) if actor else "Sistema",
            "document_id": str(document.id) if document else None,
            "document_number": document.full_document_number if document else None,
            "can_retry": row.status in {"pending", "rejected", "unknown"},
            "created_at": row.created_at.isoformat() if row.created_at else None,
            "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        })
    return {"total": total, "limit": limit, "offset": offset, "items": items}


def _uuid_or_none(value) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(value)) if value else None
    except (TypeError, ValueError):
        return None


@router.get("/attention")
async def attention(
    user=Depends(require_finance_access),
    school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    """What in certified invoicing needs a person right now."""
    rows = (await db.execute(select(FinregDocument).where(
        FinregDocument.school_id == school_id,
        FinregDocument.document_status != "cancelled",
        or_(
            FinregDocument.needs_refresh.is_(True),
            func.lower(func.coalesce(FinregDocument.agt_status, "")).in_(REJECTED_AGT),
        ),
    ))).scalars().all()
    rejected = sum(1 for row in rows if agt_state(row) == "rejected")
    pending = sum(1 for row in rows if agt_state(row) in {"processing", "submitted"})
    failed = (await db.execute(select(func.count()).select_from(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.status == "rejected",
        FinregBillingInstruction.command_type != "billing_plan_upsert",
    ))).scalar_one()
    return {
        "rejected_documents": rejected,
        "pending_documents": pending,
        "failed_operations": failed,
    }
