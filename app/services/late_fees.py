# -*- coding: utf-8 -*-
"""Late fees (multas) computed in Cellen, issued by the fiscal engine.

The director's example — "10% from day 10 to 30 of the current month, 15%
from day 10 of the next month" — is data, not code: each band is one row in
``school_fee_policies.late_fee_bands`` with an anchor month, a day window and
a percentage. This module resolves which band is active for a document on a
given day and turns the difference into a fiscal adjustment.

Escalation is incremental. A document already carrying a 10% multa that
reaches the 15% band receives a 5% note, never a second 15%. The unique
``(school, source_kind, source_id, band_id)`` key makes a retried run a
no-op, and the host debit-note route is idempotent by the assessment id.

FinReg-active schools issue the multa through FinReg's debit-note route so
the document still comes from the fiscal engine. Internal schools emit the
same ND through ``DocumentEmissionService``. Shadow schools compute and
report only: a non-fiscal integration client cannot issue a corrective
document, and pretending otherwise would fabricate a fiscal outcome.
"""
from __future__ import annotations

import calendar
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.billing import LateFeeAssessment, SchoolFeePolicy
from app.models.finance import BillingItem, Invoice
from app.models.finreg_integration import FinregBillingInstruction
from app.services.billing_profiles import get_fee_policy, get_school_year
from app.services.billing_run import BillingError, FINREG_MODES
from app.services.debt_control import list_debts
from app.services.finance import DocumentEmissionService
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import (
    LATE_FEE_COMMAND,
    dispatch_instruction,
    enqueue_billing_instruction,
    integration_mode,
)
from app.utils.agt import today_luanda

ANCHORS = ("due_month", "next_month")
BASES = ("outstanding", "document_total")


def _money(value) -> float:
    return round(float(value or 0), 2)


def _decimal(value) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def _uuid(value) -> Optional[UUID]:
    try:
        return UUID(str(value)) if value else None
    except (TypeError, ValueError):
        return None


def _parse_date(value) -> Optional[date]:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value)) if value else None
    except ValueError:
        return None


# ─── band resolution (pure) ─────────────────────────────────────────────────

def band_window(band: dict, due_date: date) -> tuple[date, date]:
    """The inclusive calendar window a band covers for this due date."""
    year, month = due_date.year, due_date.month
    if band.get("anchor") == "next_month":
        month += 1
        if month > 12:
            year, month = year + 1, 1
    last_day = calendar.monthrange(year, month)[1]
    start_day = min(max(int(band.get("start_day") or 1), 1), last_day)
    end_day = band.get("end_day")
    end_day = last_day if end_day in (None, 0) else min(max(int(end_day), start_day), last_day)
    return date(year, month, start_day), date(year, month, end_day)


def band_active_on(band: dict, due_date: date, on: date) -> bool:
    start, end = band_window(band, due_date)
    return start <= on <= end


def resolve_active_band(bands: Iterable[dict], due_date: date, on: date) -> Optional[dict]:
    """The highest active band on ``on``; None when no band applies yet."""
    active = [band for band in bands if band_active_on(band, due_date, on)]
    if not active:
        return None
    return max(
        active,
        key=lambda band: (
            _decimal(band.get("percent")),
            int(band.get("start_day") or 1),
            str(band.get("id") or ""),
        ),
    )


def validate_bands(bands: Iterable[dict]) -> list[dict]:
    """Reject ambiguous policy before it reaches a fiscal document.

    Duplicate ids would collide with the assessment idempotency key; an
    inverted window or a zero percentage would silently never charge.
    """
    result: list[dict] = []
    seen: set[str] = set()
    for raw in bands:
        band = dict(raw or {})
        band_id = str(band.get("id") or "").strip()
        if not band_id:
            raise BillingError(
                "late_fee_band_id_required",
                "Cada faixa de multa precisa de um identificador.",
                422,
            )
        if band_id in seen:
            raise BillingError(
                "late_fee_band_duplicate",
                f"A faixa de multa '{band_id}' está repetida.",
                422,
            )
        seen.add(band_id)
        if band.get("anchor", "due_month") not in ANCHORS:
            raise BillingError(
                "late_fee_band_anchor",
                f"A faixa '{band_id}' tem uma âncora inválida.",
                422,
            )
        start_day = int(band.get("start_day") or 0)
        if not 1 <= start_day <= 31:
            raise BillingError(
                "late_fee_band_day",
                f"A faixa '{band_id}' tem um dia inicial inválido.",
                422,
            )
        end_day = band.get("end_day")
        if end_day is not None:
            end_day = int(end_day)
            if not 1 <= end_day <= 31 or end_day < start_day:
                raise BillingError(
                    "late_fee_band_day",
                    f"A faixa '{band_id}' termina antes de começar.",
                    422,
                )
        percent = _decimal(band.get("percent"))
        if percent <= 0 or percent > 100:
            raise BillingError(
                "late_fee_band_percent",
                f"A percentagem da faixa '{band_id}' deve estar entre 0 e 100.",
                422,
            )
        min_amount = band.get("min_amount")
        max_amount = band.get("max_amount")
        if min_amount not in (None, "") and _decimal(min_amount) < 0:
            raise BillingError(
                "late_fee_band_min", f"A multa mínima da faixa '{band_id}' é inválida.", 422
            )
        if max_amount not in (None, "") and _decimal(max_amount) < 0:
            raise BillingError(
                "late_fee_band_max", f"A multa máxima da faixa '{band_id}' é inválida.", 422
            )
        if (
            min_amount not in (None, "")
            and max_amount not in (None, "")
            and _decimal(max_amount) < _decimal(min_amount)
        ):
            raise BillingError(
                "late_fee_band_range",
                f"A multa máxima da faixa '{band_id}' é inferior à mínima.",
                422,
            )
        result.append(band)
    return result


def band_fee(band: dict, base: Decimal, incremental_percent: Decimal) -> Decimal:
    """Fee for one top-up, honouring the band's optional floor and ceiling."""
    amount = (base * incremental_percent / Decimal("100")).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    min_amount = band.get("min_amount")
    max_amount = band.get("max_amount")
    if min_amount not in (None, ""):
        amount = max(amount, _decimal(min_amount).quantize(Decimal("0.01")))
    if max_amount not in (None, ""):
        amount = min(amount, _decimal(max_amount).quantize(Decimal("0.01")))
    return amount


# ─── persistence helpers ────────────────────────────────────────────────────

async def _assessments_for(
    db: AsyncSession, *, school_id: UUID, source_kind: str, source_id: UUID
) -> list[LateFeeAssessment]:
    return list(
        (
            await db.execute(
                select(LateFeeAssessment).where(
                    LateFeeAssessment.school_id == school_id,
                    LateFeeAssessment.source_kind == source_kind,
                    LateFeeAssessment.source_id == source_id,
                )
            )
        ).scalars().all()
    )


def _serialize(assessment: LateFeeAssessment) -> dict:
    return {
        "id": str(assessment.id),
        "source_kind": assessment.source_kind,
        "source_id": str(assessment.source_id),
        "document_number": assessment.document_number,
        "student_id": str(assessment.student_id) if assessment.student_id else None,
        "guardian_id": str(assessment.guardian_id) if assessment.guardian_id else None,
        "band_id": assessment.band_id,
        "band_percent": _money(assessment.band_percent),
        "incremental_percent": _money(assessment.incremental_percent),
        "base_amount": _money(assessment.base_amount),
        "fee_amount": _money(assessment.fee_amount),
        "status": assessment.status,
        "assessed_on": assessment.assessed_on.isoformat() if assessment.assessed_on else None,
        "finreg_debit_note_id": (
            str(assessment.finreg_debit_note_id) if assessment.finreg_debit_note_id else None
        ),
        "internal_invoice_id": (
            str(assessment.internal_invoice_id) if assessment.internal_invoice_id else None
        ),
        "error_code": assessment.error_code,
        "error_detail": assessment.error_detail,
    }


def _finreg_payload(
    row: dict, assessment: LateFeeAssessment, item: BillingItem, *, actor_reference: str
) -> dict:
    """The FinReg debit-note body plus the context the outbox needs."""
    label = assessment.document_number or "documento"
    band_pct = _money(assessment.band_percent)
    incremental = _money(assessment.incremental_percent)
    reason = f"Multa por atraso — {label}"[:250]
    description = f"Multa {band_pct:g}%"
    if incremental < band_pct:
        description += f" (+{incremental:g}% à faixa anterior)"
    description = f"{description} — {label}"[:200]
    return {
        "actor_reference": actor_reference,
        "document_id": str(row["document_id"]),
        "document_external_id": str(assessment.id),
        "debit_note": {
            # FinReg identifies the corrective document by this id, so a
            # retried dispatch maps to the note it already issued.
            "external_id": str(assessment.id),
            "reason": reason,
            "description": description,
            "net_amount": str(assessment.fee_amount),
            "tax_rate": str(item.iva_rate),
            "tax_option_code": item.finreg_tax_option_code,
            "tax_exemption_reason": item.iva_exemption_reason,
        },
        "context": {
            "source_document_number": assessment.document_number,
            "student_id": row.get("student_id"),
            "student_name": row.get("student_name"),
            "band_id": assessment.band_id,
            "band_percent": band_pct,
            "incremental_percent": incremental,
        },
    }


async def _emit_internal_nd(
    db: AsyncSession,
    *,
    school_id: UUID,
    school_year_id: UUID,
    assessment: LateFeeAssessment,
    source_id: UUID,
    item: BillingItem,
    issued_by: Optional[UUID],
    on: date,
) -> None:
    """Emit the multa as a local signed ND (internal-mode school only)."""
    invoice = await db.get(Invoice, source_id)
    if invoice is None or invoice.school_id != school_id:
        assessment.status = "failed"
        assessment.error_code = "source_invoice_not_found"
        assessment.error_detail = "A factura de origem já não existe."
        return
    service = DocumentEmissionService(db, school_id)
    band_pct = _money(assessment.band_percent)
    nd = await service.emit_invoice(
        "ND",
        on,
        invoice.billing_guardian_id,
        invoice.customer_nif,
        invoice.customer_name,
        [{
            "billing_item_id": item.id,
            "description": f"Multa por atraso ({band_pct:g}%)",
            "quantity": 1,
            "unit_price": str(assessment.fee_amount),
            "iva_rate": str(item.iva_rate),
            "iva_exemption_reason": item.iva_exemption_reason,
            "iva_exemption_legend": item.iva_exemption_legend,
        }],
        child_id=invoice.child_id,
        due_date=on,
        issued_by=issued_by,
        school_year_id=school_year_id,
        reference_month=invoice.reference_month or invoice.invoice_date,
        description="Multa por atraso",
        notes=f"Multa de {band_pct:g}% sobre {invoice.full_document_number}",
        corrected_invoice_id=invoice.id,
        correction_reason=f"Multa de {band_pct:g}% sobre {invoice.full_document_number}"[:250],
    )
    assessment.internal_invoice_id = nd.id
    assessment.status = "issued"
    assessment.error_code = assessment.error_detail = None


# ─── assessment ─────────────────────────────────────────────────────────────

async def assess_late_fees(
    db: AsyncSession,
    *,
    school_id: UUID,
    as_of: Optional[date] = None,
    dry_run: bool = False,
    dispatch: bool = True,
    issued_by: Optional[UUID] = None,
    adapter=None,
) -> dict:
    """Assess every open overdue document against the school's bands.

    Returns the assessments created (or, in dry-run/shadow mode, the ones that
    would be created) plus a per-document explanation the director can read.
    """
    on = min(as_of or today_luanda(), today_luanda())
    school_year = await get_school_year(db, school_id)
    if school_year is None:
        raise BillingError("school_year_not_found", "Nenhum ano letivo configurado.", 404)
    policy = await get_fee_policy(db, school_id, school_year.id)
    mode = await integration_mode(db, school_id)

    if policy is None or not policy.late_fee_enabled:
        return _empty_result(on, mode, "late_fee_disabled")
    bands = validate_bands(policy.late_fee_bands or [])
    if not bands:
        return _empty_result(on, mode, "late_fee_no_bands")
    if policy.late_fee_base not in BASES:
        raise BillingError(
            "late_fee_base_invalid", "A base de cálculo da multa é inválida.", 422
        )

    item: Optional[BillingItem] = None
    if policy.late_fee_billing_item_id:
        item = await db.get(BillingItem, policy.late_fee_billing_item_id)
    if item is not None and item.school_id != school_id:
        raise BillingError("late_fee_item_missing", "Serviço fiscal inválido.", 422)
    shadow = mode == "shadow"
    preview_only = dry_run or shadow
    if item is None and not preview_only:
        raise BillingError(
            "late_fee_item_missing",
            "Escolha o serviço fiscal da multa antes de gerar multas.",
            422,
        )
    if item is not None and not item.is_active and not preview_only:
        raise BillingError(
            "late_fee_item_inactive", "O serviço fiscal da multa está inactivo.", 422
        )

    debts = await list_debts(
        db, school_id=school_id, as_of=on, overdue_only=True, adapter=adapter
    )
    if mode in FINREG_MODES:
        adapter = adapter or (
            FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter()
        )

    created: list[dict] = []
    skipped: list[dict] = []
    instructions: list[FinregBillingInstruction] = []

    for row in debts["rows"]:
        due_date = _parse_date(row.get("due_date"))
        if due_date is None or int(row.get("days_overdue") or 0) <= 0:
            continue
        band = resolve_active_band(bands, due_date, on)
        if band is None:
            continue
        source_kind = "finreg_document" if row["source"] == "finreg" else "internal_invoice"
        source_id = _uuid(row.get("document_id"))
        if source_id is None:
            continue
        existing = await _assessments_for(
            db, school_id=school_id, source_kind=source_kind, source_id=source_id
        )
        assessed_pct = sum(
            (
                _decimal(assessment.incremental_percent)
                for assessment in existing
                if assessment.status in ("pending", "issued")
            ),
            Decimal("0"),
        )
        band_id = str(band.get("id"))
        target_pct = _decimal(band.get("percent"))
        previous = next((a for a in existing if a.band_id == band_id), None)
        if previous is not None and previous.status in ("issued", "pending"):
            skipped.append(_skip(row, band_id, "already_assessed"))
            continue
        if target_pct <= assessed_pct:
            skipped.append(_skip(row, band_id, "no_increase"))
            continue

        incremental = (target_pct - assessed_pct).quantize(Decimal("0.01"))
        base = _decimal(
            row.get("gross_total")
            if policy.late_fee_base == "document_total"
            else row.get("outstanding")
        )
        fee = band_fee(band, base, incremental)
        if fee <= 0:
            skipped.append(_skip(row, band_id, "zero_fee"))
            continue

        start, end = band_window(band, due_date)
        entry = {
            "source_kind": source_kind,
            "source_id": str(source_id),
            "document_number": row.get("document_number"),
            "student_id": row.get("student_id"),
            "student_name": row.get("student_name"),
            "guardian_id": row.get("guardian_id"),
            "band": {
                "id": band_id,
                "label": band.get("label"),
                "percent": _money(target_pct),
                "window": [start.isoformat(), end.isoformat()],
            },
            "assessed_percent_before": _money(assessed_pct),
            "incremental_percent": _money(incremental),
            "base": policy.late_fee_base,
            "base_amount": _money(base),
            "fee_amount": _money(fee),
            "outstanding_before": _money(row.get("outstanding")),
        }

        if preview_only:
            created.append({
                **entry,
                "reason": "shadow_mode" if shadow else "dry_run",
                "assessment_id": None,
            })
            continue

        assessment = previous
        if assessment is None:
            assessment = LateFeeAssessment(
                school_id=school_id,
                source_kind=source_kind,
                source_id=source_id,
                band_id=band_id,
                status="pending",
                assessed_on=on,
            )
            db.add(assessment)
        assessment.document_number = row.get("document_number")
        assessment.student_id = _uuid(row.get("student_id"))
        assessment.guardian_id = _uuid(row.get("guardian_id"))
        assessment.band_percent = target_pct
        assessment.incremental_percent = incremental
        assessment.base_amount = base
        assessment.fee_amount = fee
        assessment.status = "pending"
        assessment.error_code = assessment.error_detail = None
        await db.flush()

        if row["source"] == "finreg":
            instruction, _created = await enqueue_billing_instruction(
                db,
                school_id=school_id,
                idempotency_key=f"cellen-late-fee-{assessment.id}",
                command_type=LATE_FEE_COMMAND,
                payload=_finreg_payload(
                    row, assessment, item, actor_reference=f"cellen-late-fee:{school_id}"
                ),
            )
            assessment.instruction_id = instruction.id
            instructions.append(instruction)
        else:
            await _emit_internal_nd(
                db,
                school_id=school_id,
                school_year_id=school_year.id,
                assessment=assessment,
                source_id=source_id,
                item=item,
                issued_by=issued_by,
                on=on,
            )
        await db.commit()
        created.append({**entry, "assessment_id": str(assessment.id)})

    if dispatch:
        for instruction in instructions:
            try:
                await dispatch_instruction(db, instruction, adapter=adapter)
            except FinregError:
                # The outbox keeps the pending/unknown instruction; the next
                # assessment sees "pending" and does not duplicate it.
                pass
            assessment = (
                await db.execute(
                    select(LateFeeAssessment).where(
                        LateFeeAssessment.instruction_id == instruction.id
                    )
                )
            ).scalar_one_or_none()
            if assessment is not None:
                if instruction.status == "confirmed":
                    assessment.status = "issued"
                    assessment.finreg_debit_note_id = instruction.finreg_document_id
                    assessment.error_code = assessment.error_detail = None
                elif instruction.status in ("rejected", "unknown"):
                    assessment.status = "failed"
                    assessment.error_code = instruction.error_code
                    assessment.error_detail = instruction.error_detail
                await db.commit()

    return {
        "mode": mode,
        "as_of": on.isoformat(),
        "enabled": True,
        "base": policy.late_fee_base,
        "preview_only": preview_only,
        "bands": _band_summary(bands, on),
        "created": created,
        "skipped": skipped,
        "totals": {
            "count": len(created),
            "fee_total": _money(sum(entry["fee_amount"] for entry in created)),
        },
    }


def _skip(row: dict, band_id: str, reason: str) -> dict:
    return {
        "document_id": row.get("document_id"),
        "document_number": row.get("document_number"),
        "band_id": band_id,
        "reason": reason,
    }


def _empty_result(on: date, mode: str, reason: str) -> dict:
    return {
        "mode": mode,
        "as_of": on.isoformat(),
        "enabled": reason != "late_fee_disabled",
        "reason": reason,
        "preview_only": False,
        "bands": [],
        "created": [],
        "skipped": [],
        "totals": {"count": 0, "fee_total": 0.0},
    }


def _band_summary(bands: Iterable[dict], on: date) -> list[dict]:
    """Bands as the API shows them.

    Windows depend on the document's due date, so this view describes the
    bands themselves (anchor/day/percent) and marks which would be active
    today for a document due today's month start — the screen's live preview
    uses the same helpers through ``POST /billing/late-fees/assess`` with
    ``dry_run``.
    """
    return [
        {
            "id": band.get("id"),
            "label": band.get("label"),
            "anchor": band.get("anchor", "due_month"),
            "start_day": band.get("start_day"),
            "end_day": band.get("end_day"),
            "percent": _money(band.get("percent")),
            "min_amount": band.get("min_amount"),
            "max_amount": band.get("max_amount"),
        }
        for band in bands
    ]


# ─── read model and reconciliation ──────────────────────────────────────────

async def list_assessments(
    db: AsyncSession,
    *,
    school_id: UUID,
    status: Optional[str] = None,
    student_id: Optional[UUID] = None,
    limit: int = 500,
) -> dict:
    query = select(LateFeeAssessment).where(LateFeeAssessment.school_id == school_id)
    if status:
        query = query.where(LateFeeAssessment.status == status)
    if student_id is not None:
        query = query.where(LateFeeAssessment.student_id == student_id)
    rows = list(
        (
            await db.execute(
                query.order_by(
                    LateFeeAssessment.assessed_on.desc(),
                    LateFeeAssessment.created_at.desc(),
                ).limit(min(max(limit, 1), 2000))
            )
        ).scalars().all()
    )
    return {
        "count": len(rows),
        "total": _money(sum(float(row.fee_amount or 0) for row in rows)),
        "rows": [_serialize(row) for row in rows],
    }


async def reconcile_assessments(db: AsyncSession, *, limit: int = 200) -> int:
    """Promote assessments whose outbox instruction resolved since the last run."""
    rows = (
        await db.execute(
            select(LateFeeAssessment, FinregBillingInstruction)
            .join(
                FinregBillingInstruction,
                LateFeeAssessment.instruction_id == FinregBillingInstruction.id,
            )
            .where(
                LateFeeAssessment.status == "pending",
                FinregBillingInstruction.status.in_(("confirmed", "rejected", "unknown")),
            )
            .limit(limit)
        )
    ).all()
    changed = 0
    for assessment, instruction in rows:
        if instruction.status == "confirmed":
            assessment.status = "issued"
            assessment.finreg_debit_note_id = instruction.finreg_document_id
            assessment.error_code = assessment.error_detail = None
        else:
            assessment.status = "failed"
            assessment.error_code = instruction.error_code
            assessment.error_detail = instruction.error_detail
        changed += 1
    if changed:
        await db.commit()
    return changed
