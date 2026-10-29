# -*- coding: utf-8 -*-
"""Monthly billing orchestration: preview, generate, rebuild plans.

Two paths share one composition:

* FinReg-active schools get one recurring plan per student and one outbox
  instruction per student and month. The instruction upserts the plan with
  the month's composed lines, runs the period, and pauses the plan again so
  FinReg's own scheduler can never bill a period Cellen did not compose.
* Every other school emits the same composed lines through the local fiscal
  document service. Amounts, taxes and discounts are identical by
  construction because both paths consume the same ``BillingComposition``.

The run row is the idempotency boundary: one school year and month can only
ever have one run, so a double click cannot bill twice.
"""
from __future__ import annotations

import hashlib
import json
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.academic import SchoolYear
from app.models.billing import BillingRun, SchoolFeePolicy, StudentFinanceProfile
from app.models.finance import BillingItem, Invoice
from app.models.finreg_integration import FinregBillingInstruction
from app.models.person import Guardian
from app.services.billing_composer import (
    BillingComposition,
    ChargeLine,
    StudentComposition,
    advance_month,
    billing_date,
    compose_students,
    month_bounds,
)
from app.services.billing_profiles import (
    ensure_profile,
    get_school_year,
    load_billing_inputs,
    policy_snapshot,
    policy_values,
)
from app.services.finance import DocumentEmissionService
from app.services.finreg_dispatch import (
    BILLING_PLAN_UPSERT_COMMAND,
    BILLING_RUN_COMMAND,
    dispatch_instruction,
    enqueue_billing_instruction,
    integration_mode,
)
from app.services.finreg import FakeFinregAdapter, FinregError
from app.utils.agt import today_luanda

FINREG_MODES = {"fake", "shadow", "pilot", "live"}
RUN_NOTE_PREFIX = "cellen-billing-run:"


class BillingError(Exception):
    def __init__(self, code: str, detail: str, status_code: int = 409):
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.status_code = status_code


def current_billing_month() -> str:
    return today_luanda().strftime("%Y-%m")


def _as_float(value) -> float:
    return float(Decimal(str(value)))


def _validate_month(
    billing_month: str, school_year: SchoolYear, *, allow_future: bool = False
) -> tuple[date, date]:
    try:
        first, last = month_bounds(billing_month)
    except ValueError as exc:
        raise BillingError("invalid_billing_month", str(exc), 422) from exc
    if last < school_year.start_date or first > school_year.end_date:
        raise BillingError(
            "billing_month_outside_school_year",
            "O mês está fora do ano letivo selecionado.",
            422,
        )
    current = today_luanda()
    if not allow_future and first > date(current.year, current.month, 1):
        raise BillingError(
            "future_billing_month",
            "Ainda não é possível gerar dívidas de um mês futuro.",
            422,
        )
    return first, last


def _serialize_line(line: ChargeLine) -> dict:
    return {
        "service": line.service,
        "service_label": line.service_label,
        "source_id": str(line.source_id) if line.source_id else None,
        "billing_item_id": str(line.billing_item_id),
        "description": line.description,
        "quantity": _as_float(line.quantity),
        "base_unit_price": _as_float(line.base_unit_price),
        "unit_price": _as_float(line.unit_price),
        "discount_pct": _as_float(line.discount_pct),
        "discount_amount": _as_float(line.discount_amount),
        "tax_rate": _as_float(line.tax_rate),
        "tax_option_code": line.tax_option_code,
        "exemption_reason": line.exemption_reason,
        "proration_factor": (
            _as_float(line.proration_factor) if line.proration_factor is not None else None
        ),
        "line_net": _as_float(line.line_net),
        "iva_amount": _as_float(line.iva_amount),
        "line_total": _as_float(line.line_total),
    }


def serialize_student(student: StudentComposition) -> dict:
    return {
        "child_id": str(student.child_id),
        "child_name": student.child_name,
        "guardian_id": str(student.guardian_id),
        "guardian_name": student.guardian_name,
        "guardian_nif": student.guardian_nif,
        "enrollment_id": str(student.enrollment_id),
        "plan_external_id": str(student.plan_external_id),
        "billing_day": student.billing_day,
        "sibling_index": student.sibling_index,
        "family_size": student.family_size,
        "sibling_discount_applied": student.sibling_discount_applied,
        "lines": [_serialize_line(line) for line in student.lines],
        "subtotal": _as_float(student.subtotal),
        "discount_total": _as_float(student.discount_total),
        "net_total": _as_float(student.net_total),
        "iva_total": _as_float(student.iva_total),
        "total": _as_float(student.total),
        "warnings": list(student.warnings),
    }


def serialize_composition(composition: BillingComposition) -> dict:
    return {
        "billing_month": composition.billing_month,
        "students": [serialize_student(student) for student in composition.students],
        "totals": {
            key: (_as_float(value) if isinstance(value, Decimal) else value)
            for key, value in composition.totals.items()
        },
        "warnings": list(composition.warnings),
    }


def serialize_run(run: BillingRun) -> dict:
    return {
        "id": str(run.id),
        "school_year_id": str(run.school_year_id),
        "billing_month": run.billing_month,
        "status": run.status,
        "mode": run.mode,
        "stats": run.stats or {},
        "created_at": run.created_at.isoformat() if run.created_at else None,
        "completed_at": run.completed_at.isoformat() if run.completed_at else None,
    }


def _planned_dates(
    billing_month: str, billing_day: int, today: date
) -> tuple[date, date]:
    """Return (document/run date, next schedule date).

    A current month whose billing day has not arrived is issued today rather
    than future-dated; the schedule then advances from today.
    """
    first, last = month_bounds(billing_month)
    run_date = billing_date(billing_month, billing_day)
    if run_date > today:
        run_date = today
    if run_date < first:
        run_date = first
    if run_date > last:
        run_date = last
    return run_date, advance_month(run_date)


def _guardian_data(guardian: Guardian) -> dict:
    return {
        "tax_id": guardian.nif,
        "name": f"{guardian.first_name} {guardian.last_name}",
        "email": guardian.email,
        "phone": guardian.mobile_first,
        "address": guardian.street,
        "city": guardian.city,
        "country": "AO",
        "is_company": False,
    }


def _product_data(item: BillingItem) -> dict:
    return {
        "sku": item.code,
        "name": item.name,
        "description": item.description,
        "unit_price": str(item.unit_price),
        "tax_rate": str(item.iva_rate),
        "tax_option_code": item.finreg_tax_option_code,
        "tax_exemption_reason": item.iva_exemption_reason,
        "is_service": True,
    }


def _plan_revision(plan: dict) -> str:
    return hashlib.sha256(
        json.dumps(plan, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()[:16]




async def preview_billing(
    db: AsyncSession,
    *,
    school_id: UUID,
    billing_month: Optional[str] = None,
    school_year_id: Optional[UUID] = None,
    child_id: Optional[UUID] = None,
) -> dict:
    school_year = await get_school_year(db, school_id, school_year_id)
    if school_year is None:
        raise BillingError("school_year_not_found", "Nenhum ano letivo configurado.", 404)
    month = billing_month or current_billing_month()
    _validate_month(month, school_year, allow_future=True)

    inputs, unbilled, policy_row = await load_billing_inputs(
        db,
        school_id=school_id,
        school_year=school_year,
        billing_month=month,
        child_id=child_id,
    )
    composition = compose_students(inputs, policy_snapshot(policy_row), month)
    mode = await integration_mode(db, school_id)
    wire_mode = "internal" if mode == "disabled" else mode
    run = (
        await db.execute(
            select(BillingRun).where(
                BillingRun.school_id == school_id,
                BillingRun.school_year_id == school_year.id,
                BillingRun.billing_month == month,
            )
        )
    ).scalar_one_or_none()

    blockers: list[dict] = []
    warnings = list(composition.warnings)
    if not composition.students:
        blockers.append({
            "code": "no_billable_students",
            "message": "Nenhum aluno ativo com valores a cobrar neste mês.",
        })
    if wire_mode in FINREG_MODES:
        missing_tax = sorted({
            line.service_label
            for student in composition.students
            for line in student.lines
            if not line.tax_option_code
        })
        if missing_tax:
            blockers.append({
                "code": "finreg_tax_option_missing",
                "message": "Configure o tratamento fiscal destes serviços: "
                + ", ".join(missing_tax),
                "items": missing_tax,
            })
        missing_exemption = sorted({
            line.service_label
            for student in composition.students
            for line in student.lines
            if line.tax_rate == 0 and not line.exemption_reason
        })
        if missing_exemption:
            blockers.append({
                "code": "finreg_tax_exemption_missing",
                "message": "Indique o motivo de isenção de IVA destes serviços: "
                + ", ".join(missing_exemption),
                "items": missing_exemption,
            })
    today = today_luanda()
    run_date, _ = _planned_dates(month, composition.policy.billing_day, today)
    due_date = _add_days(run_date, composition.policy.due_days)

    return {
        "school_year": {
            "id": str(school_year.id),
            "year_label": school_year.year_label,
            "start_date": school_year.start_date.isoformat(),
            "end_date": school_year.end_date.isoformat(),
        },
        "billing_month": month,
        "mode": wire_mode,
        "policy": policy_values(policy_row),
        "run_date": run_date.isoformat(),
        "due_date": due_date.isoformat(),
        **serialize_composition(composition),
        "unbilled": unbilled,
        "warnings": warnings,
        "blockers": blockers,
        "existing_run": serialize_run(run) if run else None,
    }


def _add_days(value: date, days: int) -> date:
    from datetime import timedelta
    return value + timedelta(days=max(days, 0))


async def _get_or_create_run(
    db: AsyncSession,
    *,
    school_id: UUID,
    school_year_id: UUID,
    billing_month: str,
    mode: str,
    actor_id: Optional[UUID],
    stats: dict,
) -> tuple[BillingRun, bool]:
    existing = (
        await db.execute(
            select(BillingRun).where(
                BillingRun.school_id == school_id,
                BillingRun.school_year_id == school_year_id,
                BillingRun.billing_month == billing_month,
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing, False
    run = BillingRun(
        school_id=school_id,
        school_year_id=school_year_id,
        billing_month=billing_month,
        status="running",
        mode=mode,
        stats=stats,
        requested_by=actor_id,
    )
    db.add(run)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        run = (
            await db.execute(
                select(BillingRun).where(
                    BillingRun.school_id == school_id,
                    BillingRun.school_year_id == school_year_id,
                    BillingRun.billing_month == billing_month,
                )
            )
        ).scalar_one()
        return run, False
    return run, True


async def run_billing(
    db: AsyncSession,
    *,
    school_id: UUID,
    billing_month: Optional[str] = None,
    school_year_id: Optional[UUID] = None,
    actor_id: Optional[UUID] = None,
    issued_by: Optional[UUID] = None,
    adapter=None,
) -> tuple[BillingRun, bool]:
    school_year = await get_school_year(db, school_id, school_year_id)
    if school_year is None:
        raise BillingError("school_year_not_found", "Nenhum ano letivo configurado.", 404)
    month = billing_month or current_billing_month()
    _validate_month(month, school_year)
    mode = await integration_mode(db, school_id)
    wire_mode = "internal" if mode == "disabled" else mode

    inputs, unbilled, policy_row = await load_billing_inputs(
        db, school_id=school_id, school_year=school_year, billing_month=month
    )
    policy = policy_snapshot(policy_row)
    composition = compose_students(inputs, policy, month)
    today = today_luanda()
    run_date, _ = _planned_dates(month, policy.billing_day, today)
    due_date = _add_days(run_date, policy.due_days)

    stats = {
        "students": len(composition.students),
        "lines": composition.totals.get("lines", 0),
        "generated": 0,
        "queued": 0,
        "failed": 0,
        "skipped": 0,
        "unbilled": unbilled,
        "failures": [],
        "totals": {
            key: (_as_float(value) if isinstance(value, Decimal) else value)
            for key, value in composition.totals.items()
        },
        "run_date": run_date.isoformat(),
        "due_date": due_date.isoformat(),
        "policy": policy_values(policy_row),
    }

    run, created = await _get_or_create_run(
        db,
        school_id=school_id,
        school_year_id=school_year.id,
        billing_month=month,
        mode=wire_mode,
        actor_id=actor_id,
        stats=stats,
    )
    if not created and run.status == "completed":
        return run, False
    if not created:
        run.status = "running"
        run.stats = stats
        run.completed_at = None
        run.mode = wire_mode
        await db.commit()

    if not composition.students:
        run.status = "failed"
        run.stats = {**stats, "blockers": [{"code": "no_billable_students"}]}
        run.completed_at = datetime.now(timezone.utc)
        await db.commit()
        return run, created

    if wire_mode in FINREG_MODES:
        await _run_finreg(
            db,
            run=run,
            composition=composition,
            school_year=school_year,
            month=month,
            mode=wire_mode,
            actor_id=actor_id,
            run_date=run_date,
            adapter=adapter,
        )
    else:
        await _run_internal(
            db,
            run=run,
            composition=composition,
            school_year=school_year,
            month=month,
            actor_id=actor_id,
            issued_by=issued_by,
            run_date=run_date,
            due_date=due_date,
            stats=stats,
        )
    await refresh_run_status(db, run)
    return run, created


async def _run_finreg(
    db: AsyncSession,
    *,
    run: BillingRun,
    composition: BillingComposition,
    school_year: SchoolYear,
    month: str,
    mode: str,
    actor_id: Optional[UUID],
    run_date: date,
    adapter=None,
) -> None:
    generation_mode = "finalize" if mode in {"pilot", "live"} else "draft"
    actor = str(actor_id) if actor_id else "cellen-system"
    profiles: dict[UUID, StudentFinanceProfile] = {}
    for student in composition.students:
        profiles[student.child_id] = await ensure_profile(
            db,
            school_id=run.school_id,
            child_id=student.child_id,
            school_year_id=school_year.id,
            guardian_id=student.guardian_id,
            enrollment_date=student.starts_on,
        )
    await db.commit()

    guardian_ids = {student.guardian_id for student in composition.students}
    guardians = {
        guardian.id: guardian
        for guardian in (
            await db.execute(select(Guardian).where(Guardian.id.in_(guardian_ids)))
        ).scalars().all()
    } if guardian_ids else {}
    item_ids = {
        line.billing_item_id
        for student in composition.students
        for line in student.lines
    }
    items = {
        item.id: item
        for item in (
            await db.execute(
                select(BillingItem).where(
                    BillingItem.id.in_(item_ids),
                    BillingItem.school_id == run.school_id,
                )
            )
        ).scalars().all()
    } if item_ids else {}

    adapter = adapter or (FakeFinregAdapter() if mode == "fake" else None)
    stats = dict(run.stats or {})
    failures = list(stats.get("failures") or [])
    generated = queued = failed = skipped = 0

    for student in composition.students:
        if not student.lines:
            skipped += 1
            continue
        guardian = guardians.get(student.guardian_id)
        if guardian is None:
            failed += 1
            failures.append(_failure(student, "missing_guardian", "Encarregado não encontrado."))
            continue
        missing_tax = sorted({
            line.service_label for line in student.lines if not line.tax_option_code
        })
        if missing_tax:
            failed += 1
            failures.append(_failure(
                student,
                "tax_option_missing",
                "Tratamento fiscal em falta: " + ", ".join(missing_tax),
            ))
            continue
        missing_exemption = sorted({
            line.service_label
            for line in student.lines
            if line.tax_rate == 0 and not line.exemption_reason
        })
        if missing_exemption:
            failed += 1
            failures.append(_failure(
                student,
                "tax_exemption_missing",
                "Motivo de isenção de IVA em falta: " + ", ".join(missing_exemption),
            ))
            continue
        if any(line.billing_item_id not in items for line in student.lines):
            failed += 1
            failures.append(_failure(
                student, "billing_item_missing", "Serviço fiscal não encontrado."
            ))
            continue

        profile = profiles[student.child_id]
        scheduled = run_date
        plan, products, revision = _build_plan(
            student,
            school_id=run.school_id,
            school_year=school_year,
            billing_month=month,
            generation_mode=generation_mode,
            next_run_date=scheduled,
            policy_due_days=(composition.policy.due_days),
            items=items,
        )
        key = f"cellen-run-{student.plan_external_id}-{month}"
        payload = {
            "actor_reference": actor,
            "billing_run_id": str(run.id),
            "plan_external_id": str(student.plan_external_id),
            "plan_revision": revision,
            "guardian": {
                "external_id": str(guardian.id),
                "data": _guardian_data(guardian),
            },
            "plan": plan,
            "products": products,
            "scheduled_run_date": scheduled.isoformat(),
            "run_date": run_date.isoformat(),
            "billing_month": month,
            "pause_after_run": True,
        }
        instruction, _ = await enqueue_billing_instruction(
            db,
            school_id=run.school_id,
            idempotency_key=key,
            command_type=BILLING_RUN_COMMAND,
            payload=payload,
        )
        profile.plan_stale = True
        if instruction.status == "confirmed":
            generated += 1
        elif adapter is not None:
            try:
                await dispatch_instruction(db, instruction, adapter=adapter)
                generated += 1
            except FinregError as exc:
                failed += 1
                failures.append(_failure(student, exc.code, exc.detail))
        else:
            queued += 1
    await db.commit()

    stats.update({
        "generated": generated,
        "queued": queued,
        "failed": failed,
        # Pre-flight failures never reach the outbox, so the run refresh must
        # keep counting them apart from FinReg rejections.
        "preflight_failed": failed,
        "skipped": skipped,
        "failures": failures,
    })
    run.stats = stats
    await db.commit()


def _failure(student: StudentComposition, code: str, detail: str) -> dict:
    return {
        "child_id": str(student.child_id),
        "child_name": student.child_name,
        "guardian_name": student.guardian_name,
        "code": code,
        "detail": detail,
    }


def _build_plan(
    student: StudentComposition,
    *,
    school_id: UUID,
    school_year: SchoolYear,
    billing_month: str,
    generation_mode: str,
    next_run_date: date,
    policy_due_days: int,
    items: dict,
) -> tuple[dict, list[dict], str]:
    lines = [{
        "product_external_id": str(line.billing_item_id),
        "description": line.description,
        "quantity": str(line.quantity),
        "unit": "un",
        "unit_price": str(line.unit_price),
        "discount_pct": str(line.discount_pct),
        "tax_rate": str(line.tax_rate),
        "tax_option_code": line.tax_option_code,
        "tax_exemption_reason": line.exemption_reason,
    } for line in student.lines]
    template = {
        "document_type": "invoice",
        "frequency": "monthly",
        "interval_count": 1,
        "due_days": policy_due_days,
        "next_run_date": next_run_date.isoformat(),
        "generation_mode": generation_mode,
        "notes": f"Mensalidade Cellen — {billing_month}",
        "lines": lines,
    }
    context = {
        "schema": "school/v1",
        "source_system": "cellen",
        "source_reference": str(student.plan_external_id),
        "school_id": str(school_id),
        "pupil_id": str(student.child_id),
        "pupil_name": student.child_name,
        "academic_year_id": str(school_year.id),
        "academic_year_label": school_year.year_label,
    }
    plan = {
        "external_id": str(student.plan_external_id),
        "template": template,
        "context": context,
        "external_version": "cellen-fee-plan/v1",
    }
    product_map: dict[str, dict] = {}
    for line in student.lines:
        item = items.get(line.billing_item_id)
        if item is None:
            continue
        product_map[str(item.id)] = _product_data(item)
    products = [
        {"external_id": external_id, "data": data}
        for external_id, data in product_map.items()
    ]
    return plan, products, _plan_revision({"plan": plan, "products": products})


async def _run_internal(
    db: AsyncSession,
    *,
    run: BillingRun,
    composition: BillingComposition,
    school_year: SchoolYear,
    month: str,
    actor_id: Optional[UUID],
    issued_by: Optional[UUID],
    run_date: date,
    due_date: date,
    stats: dict,
) -> None:
    school_id = run.school_id
    marker = f"{RUN_NOTE_PREFIX}{run.id}"
    service = DocumentEmissionService(db, school_id)
    generated = queued = failed = skipped = 0
    failures: list[dict] = []
    profiles: dict[UUID, StudentFinanceProfile] = {}
    for student in composition.students:
        profiles[student.child_id] = await ensure_profile(
            db,
            school_id=school_id,
            child_id=student.child_id,
            school_year_id=school_year.id,
            guardian_id=student.guardian_id,
            enrollment_date=student.starts_on,
        )
    await db.flush()

    for student in composition.students:
        if not student.lines:
            skipped += 1
            continue
        existing = (
            await db.execute(
                select(Invoice.id).where(
                    Invoice.school_id == school_id,
                    Invoice.child_id == student.child_id,
                    Invoice.notes == marker,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            generated += 1
            continue
        profile = profiles[student.child_id]
        try:
            await service.emit_invoice(
                "FT",
                invoice_date=run_date,
                billing_guardian_id=student.guardian_id,
                customer_nif=student.guardian_nif,
                customer_name=student.guardian_name,
                lines=[{
                    "billing_item_id": line.billing_item_id,
                    "description": line.description,
                    "quantity": line.quantity,
                    "unit_price": line.unit_price,
                    "discount_percent": line.discount_pct,
                    "iva_rate": line.tax_rate,
                    "iva_exemption_reason": line.exemption_reason,
                    "iva_exemption_legend": line.exemption_legend,
                } for line in student.lines],
                child_id=student.child_id,
                due_date=due_date,
                issued_by=issued_by,
                school_year_id=school_year.id,
                reference_month=month_bounds(month)[0],
                description=f"Mensalidade {month}",
                notes=marker,
                is_final_consumer=not bool(student.guardian_nif),
            )
            profile.plan_next_run_date = advance_month(run_date)
            profile.plan_stale = False
            await db.commit()
            generated += 1
        except Exception as exc:  # noqa: BLE001 - a single student must not stop the run
            await db.rollback()
            failed += 1
            failures.append(_failure(student, "internal_emission_failed", str(exc)))

    stats.update({
        "generated": generated,
        "queued": queued,
        "failed": failed,
        "skipped": skipped,
        "failures": failures,
    })
    run.stats = stats
    # Internal runs have no outbox to refresh from, so they become terminal
    # here; otherwise every local run would stay "running" forever.
    if failed and not generated:
        run.status = "failed"
    elif failed:
        run.status = "partial_failed"
    else:
        run.status = "completed"
    run.completed_at = datetime.now(timezone.utc)
    await db.commit()


async def refresh_run_status(db: AsyncSession, run: BillingRun) -> BillingRun:
    """Recompute a FinReg run from its outbox instructions.

    The dispatcher confirms instructions in the background; the run row is a
    read model over them, never a second source of truth.
    """
    if run.mode not in FINREG_MODES:
        return run
    rows = list(
        (
            await db.execute(
                select(FinregBillingInstruction).where(
                    FinregBillingInstruction.school_id == run.school_id,
                    FinregBillingInstruction.command_type == BILLING_RUN_COMMAND,
                    FinregBillingInstruction.payload["billing_run_id"].astext == str(run.id),
                )
            )
        ).scalars().all()
    )
    stats = dict(run.stats or {})
    # Students rejected before enqueueing never get an instruction row; their
    # count has to survive every refresh or the run would look cleaner than
    # it is.
    preflight_failed = int(stats.get("preflight_failed") or 0)
    if not rows:
        if preflight_failed:
            stats.update({
                "generated": 0,
                "queued": 0,
                "failed": preflight_failed,
            })
            run.status = "failed"
            run.stats = stats
            run.completed_at = datetime.now(timezone.utc)
            await db.commit()
        elif "preflight_failed" in stats:
            # _run_finreg records preflight_failed once its pass finishes, so
            # its presence with no instruction rows means every student was
            # skipped before enqueueing (e.g. no billable lines). Without this
            # branch the run would stay "running" forever; the key is absent
            # during composition, which keeps a concurrent refresh from
            # settling a run whose instructions are not committed yet.
            stats.update({"generated": 0, "queued": 0, "failed": 0})
            run.status = "completed"
            run.stats = stats
            run.completed_at = datetime.now(timezone.utc)
            await db.commit()
        return run
    confirmed = [row for row in rows if row.status == "confirmed"]
    rejected = [row for row in rows if row.status == "rejected"]
    queued = [
        row for row in rows
        if row.status not in {"confirmed", "rejected"}
    ]
    stats["generated"] = len(confirmed)
    stats["queued"] = len(queued)
    stats["failed"] = len(rejected) + preflight_failed
    if rejected:
        failures = list(stats.get("failures") or [])
        known = {(f.get("child_id"), f.get("code")) for f in failures}
        for row in rejected:
            context = row.payload.get("plan", {}).get("context", {})
            child_id = context.get("pupil_id")
            key = (child_id, row.error_code)
            if key in known:
                continue
            known.add(key)
            failures.append({
                "child_id": child_id,
                "child_name": context.get("pupil_name"),
                "code": row.error_code or "finreg_rejected",
                "detail": row.error_detail,
            })
        stats["failures"] = failures

    for row in confirmed:
        profile = (
            await db.execute(
                select(StudentFinanceProfile).where(
                    StudentFinanceProfile.school_id == run.school_id,
                    StudentFinanceProfile.plan_external_id == _uuid_or_none(
                        row.payload.get("plan_external_id")
                    ),
                )
            )
        ).scalar_one_or_none()
        if profile is None:
            continue
        snapshot = row.result_snapshot or {}
        next_run = snapshot.get("next_run_date")
        if next_run:
            try:
                profile.plan_next_run_date = date.fromisoformat(str(next_run))
            except ValueError:
                pass
        elif row.payload.get("run_date"):
            try:
                profile.plan_next_run_date = advance_month(
                    date.fromisoformat(str(row.payload["run_date"]))
                )
            except ValueError:
                pass
        profile.plan_revision = row.payload.get("plan_revision")
        profile.plan_stale = False

    if queued:
        run.status = "running"
        run.completed_at = None
    elif stats["failed"] and not confirmed:
        run.status = "failed"
        run.completed_at = datetime.now(timezone.utc)
    elif stats["failed"]:
        run.status = "partial_failed"
        run.completed_at = datetime.now(timezone.utc)
    else:
        run.status = "completed"
        run.completed_at = datetime.now(timezone.utc)
    run.stats = stats
    await db.commit()
    return run


def _uuid_or_none(value):
    try:
        return UUID(str(value)) if value else None
    except (ValueError, TypeError):
        return None


async def rebuild_plans(
    db: AsyncSession,
    *,
    school_id: UUID,
    billing_month: Optional[str] = None,
    school_year_id: Optional[UUID] = None,
    actor_id: Optional[UUID] = None,
    adapter=None,
) -> dict:
    """Re-upsert every active student plan with the current composition.

    Used after a sibling discount, tuition override, modality, transport or
    policy change. The revision key keeps unchanged plans from churning.
    """
    school_year = await get_school_year(db, school_id, school_year_id)
    if school_year is None:
        raise BillingError("school_year_not_found", "Nenhum ano letivo configurado.", 404)
    month = billing_month or current_billing_month()
    _validate_month(month, school_year, allow_future=True)
    mode = await integration_mode(db, school_id)
    if mode not in FINREG_MODES:
        raise BillingError(
            "finreg_inactive",
            "Os planos escolares só existem quando o FinReg está ativo.",
            409,
        )
    inputs, unbilled, policy_row = await load_billing_inputs(
        db, school_id=school_id, school_year=school_year, billing_month=month
    )
    composition = compose_students(inputs, policy_snapshot(policy_row), month)
    generation_mode = "finalize" if mode in {"pilot", "live"} else "draft"
    today = today_luanda()
    run_date, _ = _planned_dates(month, composition.policy.billing_day, today)
    next_run = advance_month(run_date)
    actor = str(actor_id) if actor_id else "cellen-system"
    fake = adapter or (FakeFinregAdapter() if mode == "fake" else None)

    guardian_ids = {student.guardian_id for student in composition.students}
    guardians = {
        guardian.id: guardian
        for guardian in (
            await db.execute(select(Guardian).where(Guardian.id.in_(guardian_ids)))
        ).scalars().all()
    } if guardian_ids else {}
    item_ids = {
        line.billing_item_id
        for student in composition.students
        for line in student.lines
    }
    items = {
        item.id: item
        for item in (
            await db.execute(
                select(BillingItem).where(
                    BillingItem.id.in_(item_ids),
                    BillingItem.school_id == school_id,
                )
            )
        ).scalars().all()
    } if item_ids else {}

    queued = confirmed = failed = unchanged = skipped = 0
    failures: list[dict] = []
    for student in composition.students:
        if not student.lines:
            skipped += 1
            continue
        guardian = guardians.get(student.guardian_id)
        if guardian is None:
            failed += 1
            failures.append(_failure(student, "missing_guardian", "Encarregado não encontrado."))
            continue
        if any(not line.tax_option_code for line in student.lines):
            failed += 1
            failures.append(_failure(
                student, "tax_option_missing", "Serviço sem tratamento fiscal."
            ))
            continue
        if any(
            line.tax_rate == 0 and not line.exemption_reason
            for line in student.lines
        ):
            failed += 1
            failures.append(_failure(
                student, "tax_exemption_missing", "Serviço sem motivo de isenção de IVA."
            ))
            continue
        profile = await ensure_profile(
            db,
            school_id=school_id,
            child_id=student.child_id,
            school_year_id=school_year.id,
            guardian_id=student.guardian_id,
            enrollment_date=student.starts_on,
        )
        plan, products, revision = _build_plan(
            student,
            school_id=school_id,
            school_year=school_year,
            billing_month=month,
            generation_mode=generation_mode,
            next_run_date=next_run,
            policy_due_days=composition.policy.due_days,
            items=items,
        )
        if profile.plan_revision == revision and not profile.plan_stale:
            unchanged += 1
            continue
        key = f"cellen-plan-rebuild-{student.plan_external_id}-{revision}"
        payload = {
            "actor_reference": actor,
            "plan_external_id": str(student.plan_external_id),
            "plan_revision": revision,
            "next_run_date": next_run.isoformat(),
            "guardian": {
                "external_id": str(guardian.id),
                "data": _guardian_data(guardian),
            },
            "plan": plan,
            "products": products,
            "pause_after_run": True,
        }
        instruction, _ = await enqueue_billing_instruction(
            db,
            school_id=school_id,
            idempotency_key=key,
            command_type=BILLING_PLAN_UPSERT_COMMAND,
            payload=payload,
        )
        if instruction.status == "confirmed":
            confirmed += 1
            profile.plan_revision = revision
            profile.plan_next_run_date = next_run
            profile.plan_stale = False
        elif fake is not None:
            try:
                await dispatch_instruction(db, instruction, adapter=fake)
                confirmed += 1
                profile.plan_revision = revision
                profile.plan_next_run_date = next_run
                profile.plan_stale = False
            except FinregError as exc:
                failed += 1
                failures.append(_failure(student, exc.code, exc.detail))
        else:
            queued += 1
    await db.commit()
    return {
        "billing_month": month,
        "mode": mode,
        "queued": queued,
        "confirmed": confirmed,
        "unchanged": unchanged,
        "skipped": skipped,
        "failed": failed,
        "failures": failures,
        "unbilled": unbilled,
    }


async def apply_confirmed_plan_results(
    db: AsyncSession, *, school_id: Optional[UUID] = None, limit: int = 100
) -> int:
    """Copy confirmed plan-upsert results into the student profiles.

    The dispatcher may confirm instructions after the request returned; this
    reconciliation runs on each dispatcher tick and is idempotent.
    """
    query = select(FinregBillingInstruction).where(
        FinregBillingInstruction.command_type == BILLING_PLAN_UPSERT_COMMAND,
        FinregBillingInstruction.status == "confirmed",
    ).order_by(FinregBillingInstruction.created_at.desc()).limit(limit)
    if school_id is not None:
        query = query.where(FinregBillingInstruction.school_id == school_id)
    rows = list((await db.execute(query)).scalars().all())
    changed = 0
    for row in rows:
        external_id = _uuid_or_none(row.payload.get("plan_external_id"))
        if external_id is None:
            continue
        profile = (
            await db.execute(
                select(StudentFinanceProfile).where(
                    StudentFinanceProfile.school_id == row.school_id,
                    StudentFinanceProfile.plan_external_id == external_id,
                )
            )
        ).scalar_one_or_none()
        if profile is None:
            continue
        revision = row.payload.get("plan_revision")
        if profile.plan_revision == revision and not profile.plan_stale:
            continue
        profile.plan_revision = revision
        profile.plan_stale = False
        next_run = row.payload.get("next_run_date")
        if next_run:
            try:
                profile.plan_next_run_date = date.fromisoformat(str(next_run))
            except ValueError:
                pass
        changed += 1
    if changed:
        await db.commit()
    return changed


async def list_runs(
    db: AsyncSession, *, school_id: UUID, limit: int = 24
) -> list[BillingRun]:
    return list(
        (
            await db.execute(
                select(BillingRun)
                .where(BillingRun.school_id == school_id)
                .order_by(BillingRun.billing_month.desc())
                .limit(limit)
            )
        ).scalars().all()
    )


async def get_run(db: AsyncSession, *, school_id: UUID, run_id: UUID) -> Optional[BillingRun]:
    return (
        await db.execute(
            select(BillingRun).where(
                BillingRun.id == run_id, BillingRun.school_id == school_id
            )
        )
    ).scalar_one_or_none()


async def refresh_open_runs(db: AsyncSession, limit: int = 50) -> int:
    """Recompute runs whose outbox work finished after the request returned."""
    runs = list(
        (
            await db.execute(
                select(BillingRun)
                .where(BillingRun.status == "running")
                .order_by(BillingRun.created_at.desc())
                .limit(limit)
            )
        ).scalars().all()
    )
    refreshed = 0
    for run in runs:
        await refresh_run_status(db, run)
        refreshed += 1
    return refreshed


async def auto_generate_due(db: AsyncSession) -> dict:
    """Generate runs for schools whose policy opts into automatic billing.

    Called by the daily Luanda-midnight sweep after the billing day. A school
    that already has a completed run for the month is untouched, making the
    job safe to re-run.
    """
    today = today_luanda()
    month = today.strftime("%Y-%m")
    policies = list(
        (
            await db.execute(
                select(SchoolFeePolicy, SchoolYear)
                .join(SchoolYear, SchoolYear.id == SchoolFeePolicy.school_year_id)
                .where(
                    SchoolFeePolicy.auto_generate.is_(True),
                    SchoolFeePolicy.billing_day <= today.day,
                    SchoolYear.is_active.is_(True),
                )
            )
        ).all()
    )
    generated = skipped = failed = 0
    failures: list[dict] = []
    for policy, school_year in policies:
        existing = (
            await db.execute(
                select(BillingRun).where(
                    BillingRun.school_id == policy.school_id,
                    BillingRun.school_year_id == school_year.id,
                    BillingRun.billing_month == month,
                    BillingRun.status == "completed",
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            skipped += 1
            continue
        try:
            await run_billing(
                db,
                school_id=policy.school_id,
                school_year_id=school_year.id,
                billing_month=month,
            )
            generated += 1
        except Exception as exc:  # noqa: BLE001 - one school must not stop the sweep
            await db.rollback()
            failed += 1
            failures.append({
                "school_id": str(policy.school_id),
                "error": str(exc),
            })
    return {
        "billing_month": month,
        "schools": len(policies),
        "generated": generated,
        "skipped": skipped,
        "failed": failed,
        "failures": failures,
    }
