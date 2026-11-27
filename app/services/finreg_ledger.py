"""Cellen's local read model of FinReg fiscal documents.

The school never opens FinReg. Its own finance screens list, search and open
fiscal documents from ``FinregDocument`` rows, and every value on a row was
returned by FinReg: a confirmed outbox instruction, a document event, or a
direct ``GET documents/{reference}`` refresh. Nothing here computes a number,
a total or a status.

Three writers feed the ledger, all idempotent:

* ``record_instruction`` -- right after the outbox confirms an instruction;
* ``apply_event`` -- for each FinReg event the poller consumes;
* ``refresh_document`` -- re-reads a row FinReg may have changed since (a
  draft finalized, an AGT submission answered, a document cancelled).
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregDocument,
    FinregSchoolConnection,
)
from app.core.config import settings
from app.services.finreg import FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import (
    BILLING_PLAN_UPSERT_COMMAND,
    BILLING_RUN_COMMAND,
    CORRECTION_COMMAND,
    LATE_FEE_COMMAND,
)

logger = logging.getLogger(__name__)

# FinReg document types → the school-facing family a screen groups them by.
KIND_BY_TYPE = {
    "invoice": "invoice",
    "ft": "invoice",
    "invoice_receipt": "invoice_receipt",
    "fr": "invoice_receipt",
    "credit_note": "credit_note",
    "nc": "credit_note",
    "debit_note": "debit_note",
    "nd": "debit_note",
    "receipt": "receipt",
    "rc": "receipt",
}

# AGT states after which FinReg will not change the submission by itself.
AGT_SETTLED = {"accepted", "valid", "validated", "rejected", "invalid", "not_required", "exempt"}
REFRESH_BACKOFF_CAP = timedelta(hours=6)
REFRESH_FIRST_DELAY = timedelta(seconds=30)
REFRESH_GIVE_UP_AFTER = 40


def _uuid(value) -> uuid.UUID | None:
    if value is None or value == "":
        return None
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError):
        return None


def _money(value) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError):
        return None


def _date(value) -> date | None:
    if not value:
        return None
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def kind_for(document_type: str | None) -> str:
    return KIND_BY_TYPE.get(str(document_type or "invoice").lower(), "invoice")


def looks_like_document(payload: Any) -> bool:
    """A FinReg ``DocumentOut``: an id plus a document type or status."""
    return (
        isinstance(payload, dict)
        and _uuid(payload.get("id")) is not None
        and ("document_type" in payload or "document_status" in payload)
    )


def _status(payload: dict, fallback: str = "draft") -> str:
    return str(payload.get("document_status") or payload.get("status") or fallback).lower()


def _settled(row: FinregDocument) -> bool:
    """FinReg has nothing further to tell us about this document by itself."""
    if row.document_status == "cancelled":
        return True
    if row.document_status == "draft":
        return False
    return str(row.agt_status or "").lower() in AGT_SETTLED


def _schedule(row: FinregDocument) -> None:
    row.needs_refresh = not _settled(row)


def _context(instruction: FinregBillingInstruction | None) -> dict:
    if instruction is None:
        return {}
    payload = instruction.payload or {}
    for container in ("plan", "draft"):
        context = (payload.get(container) or {}).get("context")
        if context:
            return dict(context)
    return dict(payload.get("context") or {})


def _apply_instruction_context(row: FinregDocument, instruction: FinregBillingInstruction | None) -> None:
    if instruction is None:
        return
    payload = instruction.payload or {}
    context = _context(instruction)
    row.instruction_id = instruction.id
    row.guardian_id = row.guardian_id or _uuid((payload.get("guardian") or {}).get("external_id"))
    row.pupil_id = row.pupil_id or _uuid(context.get("pupil_id"))
    period = context.get("billing_period") or payload.get("billing_period")
    if period and not row.billing_period:
        row.billing_period = str(period)[:7]


def _apply_document(row: FinregDocument, document: dict) -> None:
    """Copy FinReg's own values onto the row. Absent keys keep what we had."""
    if document.get("document_type"):
        row.document_type = str(document["document_type"])
        row.kind = kind_for(document["document_type"])
    if document.get("full_document_number"):
        row.full_document_number = str(document["full_document_number"])
    if document.get("document_status") or document.get("status"):
        row.document_status = _status(document, row.document_status or "draft")
    if "agt_status" in document:
        row.agt_status = document.get("agt_status")
    if document.get("agt_response_message"):
        row.agt_message = str(document["agt_response_message"])[:2000]
    if document.get("currency_code"):
        row.currency_code = str(document["currency_code"])[:3]
    for attribute in ("net_total", "tax_total", "gross_total"):
        if document.get(attribute) is not None:
            setattr(row, attribute, _money(document[attribute]))
    row.document_date = _date(document.get("document_date")) or row.document_date
    row.due_date = _date(document.get("due_date")) or row.due_date
    if document.get("customer_name"):
        row.customer_name = str(document["customer_name"])[:255]
    if document.get("customer_tax_id"):
        row.customer_tax_id = str(document["customer_tax_id"])[:40]
    row.snapshot = document


async def _row_for(db: AsyncSession, school_id, finreg_document_id: uuid.UUID) -> FinregDocument | None:
    return (await db.execute(select(FinregDocument).where(
        FinregDocument.school_id == school_id,
        FinregDocument.finreg_document_id == finreg_document_id,
    ))).scalar_one_or_none()


async def upsert_document(
    db: AsyncSession,
    *,
    school_id,
    finreg_document_id: uuid.UUID,
    reference: str,
    document: dict | None = None,
    instruction: FinregBillingInstruction | None = None,
    fallback_status: str | None = None,
) -> FinregDocument:
    row = await _row_for(db, school_id, finreg_document_id)
    if row is None:
        row = FinregDocument(
            school_id=school_id,
            finreg_document_id=finreg_document_id,
            reference=reference,
            kind="invoice",
            document_status=fallback_status or "draft",
            currency_code="AOA",
            needs_refresh=True,
            refresh_attempts=0,
        )
        db.add(row)
    elif fallback_status and not document:
        row.document_status = fallback_status
    _apply_instruction_context(row, instruction)
    if document:
        _apply_document(row, document)
        row.refreshed_at = datetime.now(timezone.utc)
        row.refresh_attempts = 0
        row.last_error_code = None
    _schedule(row)
    await db.flush()
    return row


def instruction_reference(instruction: FinregBillingInstruction) -> str:
    """The id FinReg's integrations API knows this instruction's document by."""
    payload = instruction.payload or {}
    if instruction.command_type == BILLING_RUN_COMMAND:
        return str(instruction.finreg_document_id)
    if instruction.command_type == LATE_FEE_COMMAND:
        external = (payload.get("debit_note") or {}).get("external_id")
        return str(external or instruction.finreg_document_id)
    draft = payload.get("draft") or {}
    return str(draft.get("external_id") or instruction.id)


async def record_instruction(db: AsyncSession, instruction: FinregBillingInstruction) -> FinregDocument | None:
    """Ledger the document a confirmed instruction produced, if it has one."""
    if (
        instruction.status != "confirmed"
        or instruction.finreg_document_id is None
        or instruction.command_type == BILLING_PLAN_UPSERT_COMMAND
    ):
        return None
    snapshot = instruction.result_snapshot or {}
    if instruction.command_type == CORRECTION_COMMAND:
        original_id = _uuid((instruction.payload or {}).get("document_id"))
        original = await _row_for(db, instruction.school_id, original_id) if original_id else None
        if original is None:
            return None
        row = await record_correction(
            db,
            school_id=instruction.school_id,
            original=original,
            correction_reference=str((instruction.payload or {}).get("external_id") or instruction.id),
            response={**snapshot, "credit_note_id": str(instruction.finreg_document_id)},
        )
        if row is not None:
            row.instruction_id = instruction.id
        return row
    document = snapshot if looks_like_document(snapshot) else None
    if document and _uuid(document.get("id")) != instruction.finreg_document_id:
        document = None
    fallback = None
    if document is None:
        # A run item carries the number and status but no totals or lines;
        # the refresh fills the rest from FinReg itself.
        partial = {
            key: snapshot.get(key)
            for key in ("full_document_number", "document_status")
            if snapshot.get(key)
        }
        fallback = _status(partial, "draft") if partial.get("document_status") else None
        row = await upsert_document(
            db,
            school_id=instruction.school_id,
            finreg_document_id=instruction.finreg_document_id,
            reference=instruction_reference(instruction),
            instruction=instruction,
            fallback_status=fallback,
        )
        if partial.get("full_document_number"):
            row.full_document_number = str(partial["full_document_number"])
        if instruction.command_type == LATE_FEE_COMMAND and row.kind == "invoice":
            row.kind = "debit_note"
        return row
    return await upsert_document(
        db,
        school_id=instruction.school_id,
        finreg_document_id=instruction.finreg_document_id,
        reference=instruction_reference(instruction),
        document=document,
        instruction=instruction,
    )


async def backfill(db: AsyncSession, school_id, *, limit: int = 500) -> int:
    """Ledger every confirmed document instruction not yet in the ledger.

    Uses only what Cellen already stored, so it costs no FinReg call; the
    refresh pass completes the rows afterwards.
    """
    known = select(FinregDocument.finreg_document_id).where(FinregDocument.school_id == school_id)
    rows = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.status == "confirmed",
        FinregBillingInstruction.finreg_document_id.is_not(None),
        FinregBillingInstruction.command_type != BILLING_PLAN_UPSERT_COMMAND,
        FinregBillingInstruction.finreg_document_id.not_in(known),
    ).order_by(FinregBillingInstruction.created_at).limit(limit))).scalars().all()
    count = 0
    for instruction in rows:
        if await record_instruction(db, instruction) is not None:
            count += 1
    return count


async def record_correction(
    db: AsyncSession,
    *,
    school_id,
    original: FinregDocument,
    correction_reference: str,
    response: dict,
) -> FinregDocument | None:
    """Ledger the credit note FinReg issued and mark the original cancelled."""
    credit_note_id = _uuid(response.get("credit_note_id") or response.get("id"))
    original.document_status = "cancelled"
    original.needs_refresh = True
    if credit_note_id is None:
        await db.flush()
        return None
    original.corrected_by_document_id = credit_note_id
    row = await upsert_document(
        db,
        school_id=school_id,
        finreg_document_id=credit_note_id,
        reference=correction_reference,
        fallback_status="finalized",
    )
    row.kind = "credit_note"
    row.document_type = row.document_type or "credit_note"
    row.corrects_document_id = original.finreg_document_id
    row.guardian_id = row.guardian_id or original.guardian_id
    row.pupil_id = row.pupil_id or original.pupil_id
    row.billing_period = row.billing_period or original.billing_period
    row.customer_name = row.customer_name or original.customer_name
    row.customer_tax_id = row.customer_tax_id or original.customer_tax_id
    if response.get("credit_note_number"):
        row.full_document_number = str(response["credit_note_number"])
    if original.gross_total is not None and row.gross_total is None:
        row.gross_total = original.gross_total
    row.needs_refresh = True
    await db.flush()
    return row


DOCUMENT_EVENTS = {"document.created", "document.finalized", "document.cancelled"}
AGT_EVENTS = {"agt.submission_changed", "document.agt_status_changed"}


async def apply_event(db: AsyncSession, school_id, event: dict) -> FinregDocument | None:
    """Fold one FinReg event into the ledger. Unknown events are ignored."""
    event_type = str(event.get("event_type") or "")
    payload = event.get("payload") or {}
    entity_id = _uuid(event.get("entity_id"))
    if event_type in DOCUMENT_EVENTS and entity_id is not None:
        row = await _row_for(db, school_id, entity_id)
        instruction = None
        external = _uuid(payload.get("external_id"))
        if external is not None:
            candidate = await db.get(FinregBillingInstruction, external)
            if candidate is not None and candidate.school_id == school_id:
                instruction = candidate
        if row is None and instruction is None:
            # A document no Cellen instruction asked for (for example one a
            # FinReg operator issued by hand) is not the school app's to list.
            return None
        reference = row.reference if row else str(payload.get("external_id") or entity_id)
        document = payload if looks_like_document(payload) else None
        fallback = "cancelled" if event_type == "document.cancelled" else None
        return await upsert_document(
            db,
            school_id=school_id,
            finreg_document_id=entity_id,
            reference=reference,
            document=document,
            instruction=instruction,
            fallback_status=fallback,
        )
    if event_type == "document.corrected" and entity_id is not None:
        original_external = str(payload.get("original_external_id") or "")
        original = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.reference == original_external,
        ))).scalar_one_or_none()
        if original is None:
            return None
        external = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school_id,
            FinregDocument.finreg_document_id == entity_id,
        ))).scalar_one_or_none()
        reference = external.reference if external else str(payload.get("external_id") or entity_id)
        return await record_correction(
            db,
            school_id=school_id,
            original=original,
            correction_reference=reference,
            response={**payload, "credit_note_id": str(entity_id)},
        )
    if event_type in AGT_EVENTS:
        target = _uuid(payload.get("document_id")) or entity_id
        if target is None:
            return None
        row = await _row_for(db, school_id, target)
        if row is None:
            return None
        if payload.get("agt_status") or payload.get("status"):
            row.agt_status = str(payload.get("agt_status") or payload.get("status"))
        if payload.get("message") or payload.get("agt_response_message"):
            row.agt_message = str(payload.get("message") or payload.get("agt_response_message"))[:2000]
        row.needs_refresh = True
        await db.flush()
        return row
    return None


async def refresh_document(
    db: AsyncSession,
    row: FinregDocument,
    *,
    adapter=None,
    actor_reference: str = "cellen-ledger",
) -> FinregDocument:
    """Re-read one document from FinReg. Raises ``FinregError`` on failure."""
    adapter = adapter or HttpFinregAdapter()
    try:
        document = await adapter.request(
            "GET", f"documents/{row.reference}", None, actor_reference=actor_reference
        )
    except FinregError as exc:
        row.refresh_attempts += 1
        row.last_error_code = exc.code[:80]
        row.refreshed_at = datetime.now(timezone.utc)
        if row.refresh_attempts >= REFRESH_GIVE_UP_AFTER:
            row.needs_refresh = False
        await db.flush()
        raise
    if looks_like_document(document):
        _apply_document(row, document)
    row.refreshed_at = datetime.now(timezone.utc)
    row.refresh_attempts = 0
    row.last_error_code = None
    _schedule(row)
    await db.flush()
    return row


def _due_for_refresh(row: FinregDocument, now: datetime) -> bool:
    if row.refreshed_at is None:
        return True
    delay = min(REFRESH_BACKOFF_CAP, REFRESH_FIRST_DELAY * (2 ** min(row.refresh_attempts, 12)))
    return row.refreshed_at + delay <= now


async def refresh_pending(db: AsyncSession, *, limit: int = 25) -> tuple[int, int]:
    """Refresh rows FinReg may still change, for every live connection."""
    if not settings.FINREG_INTEGRATION_ENABLED:
        return 0, 0
    connections = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.mode.in_(["pilot", "live", "shadow"]),
        FinregSchoolConnection.kill_switch.is_(False),
    ))).scalars().all()
    refreshed = failed = 0
    now = datetime.now(timezone.utc)
    for connection in connections:
        await backfill(db, connection.school_id)
        rows = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == connection.school_id,
            FinregDocument.needs_refresh.is_(True),
        ).order_by(FinregDocument.refreshed_at.asc().nulls_first()).limit(limit * 4))).scalars().all()
        adapter = HttpFinregAdapter()
        budget = limit
        for row in rows:
            if budget <= 0:
                break
            if not _due_for_refresh(row, now):
                continue
            budget -= 1
            try:
                await refresh_document(db, row, adapter=adapter)
                refreshed += 1
            except FinregError:
                failed += 1
        await db.commit()
    return refreshed, failed
