# -*- coding: utf-8 -*-
"""Fee automation: policy, services, student profiles, preview and runs.

The director's workflow lives here:

1. Set the year's fee policy (tuition item, sibling rule, billing day…).
2. Register billable services (modalities, transport routes).
3. Record what each student pays (profile override) and attends.
4. Preview the month with exact amounts and warnings.
5. Press "Gerar dívidas" once; FinReg issues the fiscal documents.

Every number comes from school-editable rows. The composer is pure, so the
preview is computed without a single FinReg call.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import (
    get_school_id,
    require_finance_access,
    require_school_admin,
)
from app.models.academic import Enrollment, SchoolYear
from app.models.billing import (
    BillingRun,
    ExtracurricularModality,
    SchoolFeePolicy,
    StudentFinanceProfile,
    StudentModalityEnrollment,
    StudentTransportAssignment,
    TransportRoute,
)
from app.models.finance import BillingItem, BillingItemPrice, Invoice, PaymentReference
from app.models.finreg_integration import FinregBillingInstruction
from app.models.person import Child, ChildGuardian
from app.schemas.billing import (
    BillingPreviewRequest,
    BillingRunRequest,
    DunningRunRequest,
    EndDatedBody,
    FeePolicyUpdate,
    LateFeeAssessRequest,
    ModalityCreate,
    ModalityEnrollmentCreate,
    ModalityUpdate,
    StudentProfileUpdate,
    TransportAssignmentCreate,
    TransportRouteCreate,
    TransportRouteUpdate,
)
from app.services.billing_profiles import (
    active_enrollment_for_child,
    ensure_profile,
    get_fee_policy,
    get_school_year,
    mark_plans_stale,
    plan_external_id,
    policy_values,
    resolve_billing_guardian,
)
from app.services.billing_run import (
    BillingError,
    FINREG_MODES,
    RUN_NOTE_PREFIX,
    current_billing_month,
    get_run,
    list_runs,
    preview_billing,
    rebuild_plans,
    refresh_run_status,
    run_billing,
    serialize_run,
)
from app.schemas.finance import PaymentReferenceResponse, RailReferenceCreate
from app.services import principia_pay
from app.services.debt_control import dashboard as finance_dashboard
from app.services.debt_control import list_debts, service_report
from app.services.parent_finance import active_rail_references
from app.services.dunning import list_deliveries, run_dunning
from app.services.late_fees import (
    assess_late_fees,
    list_assessments,
    validate_bands,
)
from app.services.finance import DocumentEmissionService
from app.services.finreg import FinregError
from app.services.finreg_dispatch import (
    BILLING_RUN_COMMAND,
    dispatch_instruction,
    enqueue_modality_inscription_instruction,
    integration_mode,
)
from app.utils.agt import today_luanda

router = APIRouter(prefix="/billing", tags=["Billing automation"])
logger = logging.getLogger(__name__)


# ─── helpers ────────────────────────────────────────────────────────────────

def _money(value) -> Optional[float]:
    return float(Decimal(str(value))) if value is not None else None


def _actor_id(user) -> Optional[uuid.UUID]:
    """Only school users exist in ``users.id``; platform admins do not."""
    if getattr(user, "_school_id", None) is None:
        return None
    return getattr(user, "id", None)


def _employee_id(user) -> Optional[uuid.UUID]:
    """Fiscal documents record the employee, never the login account."""
    return getattr(user, "employee_id", None)


def _raise_billing(exc: BillingError) -> None:
    raise HTTPException(
        status_code=exc.status_code,
        detail={"code": exc.code, "message": exc.detail},
    )


def _year_payload(year: SchoolYear) -> dict:
    return {
        "id": str(year.id),
        "year_label": year.year_label,
        "start_date": year.start_date.isoformat(),
        "end_date": year.end_date.isoformat(),
        "is_active": year.is_active,
    }


def _item_payload(item: Optional[BillingItem]) -> Optional[dict]:
    if item is None:
        return None
    return {
        "id": str(item.id),
        "code": item.code,
        "name": item.name,
        "unit_price": _money(item.unit_price),
        "iva_rate": _money(item.iva_rate),
        "finreg_tax_option_code": item.finreg_tax_option_code,
        "iva_exemption_reason": item.iva_exemption_reason,
        "iva_exemption_legend": item.iva_exemption_legend,
        "category": item.category,
        "is_active": item.is_active,
    }


def _policy_payload(policy: Optional[SchoolFeePolicy]) -> dict:
    data = policy_values(policy)
    for key in ("default_enrollment_fee", "sibling_discount_pct"):
        data[key] = _money(data.get(key))
    data["default_tuition_billing_item_id"] = (
        str(data["default_tuition_billing_item_id"])
        if data.get("default_tuition_billing_item_id")
        else None
    )
    return data


async def _school_year_or_404(
    db: AsyncSession, school_id: uuid.UUID, school_year_id: Optional[uuid.UUID]
) -> SchoolYear:
    school_year = await get_school_year(db, school_id, school_year_id)
    if school_year is None:
        raise HTTPException(status_code=404, detail="Nenhum ano letivo configurado")
    return school_year


async def _child_or_404(
    db: AsyncSession, school_id: uuid.UUID, child_id: uuid.UUID
) -> Child:
    child = (
        await db.execute(
            select(Child).where(Child.id == child_id, Child.school_id == school_id)
        )
    ).scalar_one_or_none()
    if child is None:
        raise HTTPException(status_code=404, detail="Aluno não encontrado")
    return child


async def _item_or_422(
    db: AsyncSession, school_id: uuid.UUID, item_id: uuid.UUID
) -> BillingItem:
    item = (
        await db.execute(
            select(BillingItem).where(
                BillingItem.id == item_id, BillingItem.school_id == school_id
            )
        )
    ).scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=422, detail="Serviço fiscal inválido")
    if not item.is_active:
        raise HTTPException(status_code=422, detail="O serviço fiscal está inactivo")
    return item


async def _modality_or_404(
    db: AsyncSession, school_id: uuid.UUID, modality_id: uuid.UUID
) -> ExtracurricularModality:
    modality = (
        await db.execute(
            select(ExtracurricularModality).where(
                ExtracurricularModality.id == modality_id,
                ExtracurricularModality.school_id == school_id,
            )
        )
    ).scalar_one_or_none()
    if modality is None:
        raise HTTPException(status_code=404, detail="Modalidade não encontrada")
    return modality


async def _route_or_404(
    db: AsyncSession, school_id: uuid.UUID, route_id: uuid.UUID
) -> TransportRoute:
    route = (
        await db.execute(
            select(TransportRoute).where(
                TransportRoute.id == route_id, TransportRoute.school_id == school_id
            )
        )
    ).scalar_one_or_none()
    if route is None:
        raise HTTPException(status_code=404, detail="Rota de transporte não encontrada")
    return route


def _modality_payload(
    modality: ExtracurricularModality,
    item: Optional[BillingItem] = None,
    *,
    enrolled_count: int = 0,
    enrolled: Optional[bool] = None,
    enrollment: Optional[StudentModalityEnrollment] = None,
) -> dict:
    data = {
        "id": str(modality.id),
        "name": modality.name,
        "description": modality.description,
        "inscription_fee": _money(modality.inscription_fee),
        "monthly_fee": _money(modality.monthly_fee),
        "billing_item_id": str(modality.billing_item_id) if modality.billing_item_id else None,
        "billing_item": _item_payload(item),
        "is_active": modality.is_active,
        "enrolled_count": enrolled_count,
    }
    if enrolled is not None:
        data["enrolled"] = enrolled
    if enrollment is not None:
        data["enrollment"] = _modality_enrollment_payload(enrollment, modality)
    return data


def _modality_enrollment_payload(
    enrollment: StudentModalityEnrollment,
    modality: Optional[ExtracurricularModality] = None,
    child: Optional[Child] = None,
) -> dict:
    return {
        "id": str(enrollment.id),
        "child_id": str(enrollment.child_id),
        "child_name": (
            f"{child.first_name} {child.last_name}" if child is not None else None
        ),
        "modality_id": str(enrollment.modality_id),
        "modality_name": modality.name if modality is not None else None,
        "start_date": enrollment.start_date.isoformat(),
        "end_date": enrollment.end_date.isoformat() if enrollment.end_date else None,
        "status": enrollment.status,
        "inscription_instruction_id": (
            str(enrollment.inscription_instruction_id)
            if enrollment.inscription_instruction_id
            else None
        ),
        "inscription_invoice_id": (
            str(enrollment.inscription_invoice_id)
            if enrollment.inscription_invoice_id
            else None
        ),
    }


def _route_payload(
    route: TransportRoute,
    item: Optional[BillingItem] = None,
    *,
    assigned_count: int = 0,
    assignment: Optional[StudentTransportAssignment] = None,
) -> dict:
    data = {
        "id": str(route.id),
        "name": route.name,
        "description": route.description,
        "monthly_price": _money(route.monthly_price),
        "billing_item_id": str(route.billing_item_id) if route.billing_item_id else None,
        "billing_item": _item_payload(item),
        "is_active": route.is_active,
        "assigned_count": assigned_count,
    }
    if assignment is not None:
        data["assignment"] = _transport_assignment_payload(assignment, route)
    return data


def _transport_assignment_payload(
    assignment: StudentTransportAssignment,
    route: Optional[TransportRoute] = None,
    child: Optional[Child] = None,
) -> dict:
    return {
        "id": str(assignment.id),
        "child_id": str(assignment.child_id),
        "child_name": (
            f"{child.first_name} {child.last_name}" if child is not None else None
        ),
        "route_id": str(assignment.route_id),
        "route_name": route.name if route is not None else None,
        "start_date": assignment.start_date.isoformat(),
        "end_date": assignment.end_date.isoformat() if assignment.end_date else None,
        "status": assignment.status,
    }


async def _profile_payload(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    child: Child,
    school_year: SchoolYear,
    profile: Optional[StudentFinanceProfile],
    policy: Optional[SchoolFeePolicy],
) -> dict:
    """The profile plus the values actually used by the next composition."""
    link_guardian = await resolve_billing_guardian(
        db,
        school_id=school_id,
        child_id=child.id,
        preferred_guardian_id=(
            profile.billing_guardian_id if profile is not None else None
        ),
    )
    enrollment = await active_enrollment_for_child(
        db, school_id, child.id, school_year.id
    )
    item_id = (
        profile.tuition_billing_item_id
        if profile is not None and profile.tuition_billing_item_id
        else (policy.default_tuition_billing_item_id if policy is not None else None)
    )
    item = await db.get(BillingItem, item_id) if item_id else None
    if item is not None and item.school_id != school_id:
        item = None
    price = None
    if item is not None:
        price = (
            await db.execute(
                select(BillingItemPrice.unit_price).where(
                    BillingItemPrice.school_id == school_id,
                    BillingItemPrice.school_year_id == school_year.id,
                    BillingItemPrice.billing_item_id == item.id,
                )
            )
        ).scalar_one_or_none()
    base_price = (
        Decimal(price)
        if price is not None
        else (Decimal(item.unit_price) if item is not None else None)
    )
    starts_on = (
        profile.starts_on
        if profile is not None and profile.starts_on
        else (
            enrollment.enrollment_date
            if enrollment is not None
            else school_year.start_date
        )
    )
    ends_on = (
        profile.ends_on
        if profile is not None and profile.ends_on
        else school_year.end_date
    )
    billing_day = (
        profile.billing_day
        if profile is not None and profile.billing_day
        else (policy.billing_day if policy is not None else 1)
    )
    return {
        "id": str(profile.id) if profile is not None else None,
        "is_virtual": profile is None,
        "child_id": str(child.id),
        "child_name": f"{child.first_name} {child.last_name}",
        "school_year_id": str(school_year.id),
        "billing_guardian_id": (
            str(link_guardian.id) if link_guardian is not None else None
        ),
        "billing_guardian_name": (
            f"{link_guardian.first_name} {link_guardian.last_name}"
            if link_guardian is not None
            else None
        ),
        "tuition_billing_item_id": str(item.id) if item is not None else None,
        "tuition_billing_item": _item_payload(item),
        "tuition_override": (
            _money(profile.tuition_override)
            if profile is not None and profile.tuition_override is not None
            else None
        ),
        "effective_tuition_price": _money(
            profile.tuition_override
            if profile is not None and profile.tuition_override is not None
            else base_price
        ),
        "billing_day": billing_day,
        "plan_external_id": str(
            profile.plan_external_id
            if profile is not None
            else plan_external_id(child.id, school_year.id)
        ),
        "plan_revision": profile.plan_revision if profile is not None else None,
        "plan_next_run_date": (
            profile.plan_next_run_date.isoformat()
            if profile is not None and profile.plan_next_run_date
            else None
        ),
        "plan_stale": profile.plan_stale if profile is not None else True,
        "status": profile.status if profile is not None else "active",
        "starts_on": starts_on.isoformat() if starts_on else None,
        "ends_on": ends_on.isoformat() if ends_on else None,
        "enrollment_id": str(enrollment.id) if enrollment is not None else None,
        "enrollment_status": enrollment.status if enrollment is not None else None,
    }


async def _run_details(db: AsyncSession, run: BillingRun) -> dict:
    """Per-student outbox state (FinReg) or issued documents (internal)."""
    if run.mode in FINREG_MODES:
        rows = list(
            (
                await db.execute(
                    select(FinregBillingInstruction)
                    .where(
                        FinregBillingInstruction.school_id == run.school_id,
                        FinregBillingInstruction.command_type == BILLING_RUN_COMMAND,
                        FinregBillingInstruction.payload["billing_run_id"].astext
                        == str(run.id),
                    )
                    .order_by(FinregBillingInstruction.created_at)
                )
            ).scalars().all()
        )
        instructions = []
        for row in rows:
            context = (row.payload or {}).get("plan", {}).get("context", {})
            instructions.append({
                "instruction_id": str(row.id),
                "child_id": context.get("pupil_id"),
                "child_name": context.get("pupil_name"),
                "plan_external_id": (row.payload or {}).get("plan_external_id"),
                "status": row.status,
                "error_code": row.error_code,
                "error_detail": row.error_detail,
                "finreg_document_id": (
                    str(row.finreg_document_id) if row.finreg_document_id else None
                ),
                "attempts": row.attempts,
            })
        return {"instructions": instructions, "documents": []}

    invoices = list(
        (
            await db.execute(
                select(Invoice)
                .where(
                    Invoice.school_id == run.school_id,
                    Invoice.notes == f"{RUN_NOTE_PREFIX}{run.id}",
                )
                .order_by(Invoice.series_number)
            )
        ).scalars().all()
    )
    return {
        "instructions": [],
        "documents": [
            {
                "id": str(invoice.id),
                "full_document_number": invoice.full_document_number,
                "child_id": str(invoice.child_id) if invoice.child_id else None,
                "customer_name": invoice.customer_name,
                "invoice_date": invoice.invoice_date.isoformat(),
                "gross_total": _money(invoice.gross_total),
                "status": invoice.status,
            }
            for invoice in invoices
        ],
    }


async def _run_payload(db: AsyncSession, run: BillingRun) -> dict:
    return {**serialize_run(run), **await _run_details(db, run)}


# ─── fee policy ─────────────────────────────────────────────────────────────

@router.get("/fee-policy")
async def get_fee_policy_endpoint(
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    school_year = await _school_year_or_404(db, school_id, school_year_id)
    policy = await get_fee_policy(db, school_id, school_year.id)
    item = (
        await db.get(BillingItem, policy.default_tuition_billing_item_id)
        if policy is not None and policy.default_tuition_billing_item_id
        else None
    )
    late_fee_item = (
        await db.get(BillingItem, policy.late_fee_billing_item_id)
        if policy is not None and policy.late_fee_billing_item_id
        else None
    )
    return {
        "school_year": _year_payload(school_year),
        "policy": _policy_payload(policy),
        "default_tuition_item": _item_payload(item),
        "late_fee_item": _item_payload(late_fee_item),
    }


@router.put("/fee-policy")
async def update_fee_policy(
    body: FeePolicyUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    school_year = await _school_year_or_404(db, school_id, body.school_year_id)
    item = None
    if body.default_tuition_billing_item_id is not None:
        item = await _item_or_422(
            db, school_id, body.default_tuition_billing_item_id
        )
    late_fee_item = None
    if body.late_fee_billing_item_id is not None:
        late_fee_item = await _item_or_422(
            db, school_id, body.late_fee_billing_item_id
        )
    try:
        bands = validate_bands(
            [band.model_dump(mode="json") for band in body.late_fee_bands]
        )
    except BillingError as exc:
        _raise_billing(exc)
    if body.late_fee_enabled and not bands:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "late_fee_no_bands",
                "message": "Active as multas e defina pelo menos uma faixa.",
            },
        )
    if body.late_fee_enabled and late_fee_item is None:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "late_fee_item_missing",
                "message": "Escolha o serviço fiscal usado para emitir a multa.",
            },
        )
    if body.dunning_enabled and not body.dunning_schedule:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "dunning_no_schedule",
                "message": "Active os avisos e defina pelo menos um passo.",
            },
        )

    policy = await get_fee_policy(db, school_id, school_year.id)
    if policy is None:
        policy = SchoolFeePolicy(school_id=school_id, school_year_id=school_year.id)
        db.add(policy)
    policy.default_tuition_billing_item_id = item.id if item is not None else None
    policy.default_enrollment_fee = (
        Decimal(str(body.default_enrollment_fee))
        if body.default_enrollment_fee is not None
        else None
    )
    policy.sibling_discount_pct = Decimal(str(body.sibling_discount_pct))
    policy.sibling_discount_min_children = body.sibling_discount_min_children
    policy.sibling_discount_scope = body.sibling_discount_scope
    policy.due_days = body.due_days
    policy.billing_day = body.billing_day
    policy.auto_generate = body.auto_generate
    policy.proration_policy = body.proration_policy
    policy.late_fee_enabled = body.late_fee_enabled
    policy.late_fee_billing_item_id = (
        late_fee_item.id if late_fee_item is not None else None
    )
    policy.late_fee_base = body.late_fee_base
    policy.late_fee_bands = bands
    policy.dunning_enabled = body.dunning_enabled
    policy.dunning_schedule = [
        step.model_dump(mode="json") for step in body.dunning_schedule
    ]
    policy.dunning_message_template = body.dunning_message_template
    await mark_plans_stale(
        db, school_id=school_id, school_year_id=school_year.id
    )
    await db.commit()
    await db.refresh(policy)
    return {
        "school_year": _year_payload(school_year),
        "policy": _policy_payload(policy),
        "default_tuition_item": _item_payload(item),
        "late_fee_item": _item_payload(late_fee_item),
    }


# ─── late fees (multas) ─────────────────────────────────────────────────────

@router.get("/late-fees")
async def list_late_fees(
    status: Optional[str] = None,
    student_id: Optional[uuid.UUID] = None,
    limit: int = 500,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    return await list_assessments(
        db, school_id=school_id, status=status, student_id=student_id, limit=limit
    )


@router.post("/late-fees/assess")
async def assess_late_fees_endpoint(
    body: LateFeeAssessRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_finance_access),
):
    """Compute (and optionally issue) the school's multa bands.

    ``dry_run`` returns exactly what would be assessed without touching a
    fiscal document; shadow-mode schools always answer in preview form.
    """
    try:
        return await assess_late_fees(
            db,
            school_id=school_id,
            as_of=body.as_of,
            dry_run=body.dry_run,
            issued_by=_employee_id(user),
        )
    except BillingError as exc:
        _raise_billing(exc)


# ─── extracurricular modalities ─────────────────────────────────────────────

@router.get("/modalities")
async def list_modalities(
    active_only: bool = False,
    child_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(ExtracurricularModality).where(
        ExtracurricularModality.school_id == school_id
    )
    if active_only:
        query = query.where(ExtracurricularModality.is_active.is_(True))
    modalities = list(
        (await db.execute(query.order_by(ExtracurricularModality.name)))
        .scalars()
        .all()
    )
    counts = dict(
        (
            await db.execute(
                select(
                    StudentModalityEnrollment.modality_id, func.count()
                )
                .where(
                    StudentModalityEnrollment.school_id == school_id,
                    StudentModalityEnrollment.status == "active",
                )
                .group_by(StudentModalityEnrollment.modality_id)
            )
        ).all()
    )
    item_ids = {
        modality.billing_item_id
        for modality in modalities
        if modality.billing_item_id is not None
    }
    items = {
        item.id: item
        for item in (
            await db.execute(
                select(BillingItem).where(
                    BillingItem.school_id == school_id, BillingItem.id.in_(item_ids)
                )
            )
        ).scalars().all()
    } if item_ids else {}
    child_enrollments: dict[uuid.UUID, StudentModalityEnrollment] = {}
    if child_id is not None:
        await _child_or_404(db, school_id, child_id)
        for enrollment in (
            await db.execute(
                select(StudentModalityEnrollment)
                .where(
                    StudentModalityEnrollment.school_id == school_id,
                    StudentModalityEnrollment.child_id == child_id,
                )
                .order_by(StudentModalityEnrollment.start_date.desc())
            )
        ).scalars().all():
            child_enrollments.setdefault(enrollment.modality_id, enrollment)
    return [
        _modality_payload(
            modality,
            items.get(modality.billing_item_id),
            enrolled_count=counts.get(modality.id, 0),
            enrolled=(
                modality.id in child_enrollments
                if child_id is not None
                else None
            ),
            enrollment=child_enrollments.get(modality.id),
        )
        for modality in modalities
    ]


@router.post("/modalities", status_code=status.HTTP_201_CREATED)
async def create_modality(
    body: ModalityCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="O nome da modalidade é obrigatório")
    item = (
        await _item_or_422(db, school_id, body.billing_item_id)
        if body.billing_item_id
        else None
    )
    modality = ExtracurricularModality(
        school_id=school_id,
        name=name,
        description=body.description,
        inscription_fee=Decimal(str(body.inscription_fee)),
        monthly_fee=Decimal(str(body.monthly_fee)),
        billing_item_id=item.id if item is not None else None,
        is_active=body.is_active,
    )
    db.add(modality)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Já existe uma modalidade com este nome")
    await db.refresh(modality)
    return _modality_payload(modality, item)


@router.patch("/modalities/{modality_id}")
async def update_modality(
    modality_id: uuid.UUID,
    body: ModalityUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    modality = await _modality_or_404(db, school_id, modality_id)
    fields = body.model_fields_set
    item = None
    if "billing_item_id" in fields and body.billing_item_id is not None:
        item = await _item_or_422(db, school_id, body.billing_item_id)
        modality.billing_item_id = item.id
    elif "billing_item_id" in fields:
        modality.billing_item_id = None
    if "name" in fields and body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=422, detail="O nome da modalidade é obrigatório")
        modality.name = name
    if "description" in fields:
        modality.description = body.description
    if "inscription_fee" in fields and body.inscription_fee is not None:
        modality.inscription_fee = Decimal(str(body.inscription_fee))
    if "monthly_fee" in fields and body.monthly_fee is not None:
        modality.monthly_fee = Decimal(str(body.monthly_fee))
    if "is_active" in fields and body.is_active is not None:
        modality.is_active = body.is_active

    school_year = await get_school_year(db, school_id)
    if school_year is not None:
        child_ids = set(
            (
                await db.execute(
                    select(StudentModalityEnrollment.child_id).where(
                        StudentModalityEnrollment.school_id == school_id,
                        StudentModalityEnrollment.modality_id == modality.id,
                    )
                )
            ).scalars().all()
        )
        if child_ids:
            await mark_plans_stale(
                db,
                school_id=school_id,
                school_year_id=school_year.id,
                child_ids=child_ids,
            )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Já existe uma modalidade com este nome")
    await db.refresh(modality)
    if modality.billing_item_id and item is None:
        item = await db.get(BillingItem, modality.billing_item_id)
    return _modality_payload(modality, item)


async def _charge_modality_inscription(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    student_modality: StudentModalityEnrollment,
    modality: ExtracurricularModality,
    child: Child,
    school_year: SchoolYear,
    actor_id: Optional[uuid.UUID],
    issued_by: Optional[uuid.UUID] = None,
) -> dict:
    fee = Decimal(modality.inscription_fee or 0)
    if fee <= 0:
        return {"mode": "none", "status": "not_charged"}
    item = await _item_or_422(db, school_id, modality.billing_item_id) if modality.billing_item_id else None
    if item is None:
        raise HTTPException(
            status_code=422,
            detail="Associe um serviço fiscal à modalidade antes de cobrar a inscrição",
        )
    guardian = await resolve_billing_guardian(
        db, school_id=school_id, child_id=child.id
    )
    if guardian is None:
        raise HTTPException(
            status_code=422,
            detail="A cobrança da inscrição requer um encarregado de facturação",
        )
    charge_date = today_luanda()
    mode = await integration_mode(db, school_id)
    wire_mode = "internal" if mode == "disabled" else mode
    if wire_mode in FINREG_MODES:
        if not item.finreg_tax_option_code:
            raise HTTPException(
                status_code=422,
                detail="O serviço da modalidade não tem tratamento fiscal Finreg configurado",
            )
        if item.iva_rate == 0 and not item.iva_exemption_reason:
            raise HTTPException(
                status_code=422,
                detail="O serviço da modalidade não tem motivo de isenção de IVA",
            )
        instruction = await enqueue_modality_inscription_instruction(
            db,
            school_id=school_id,
            student_modality_id=student_modality.id,
            child_id=child.id,
            child_name=f"{child.first_name} {child.last_name}",
            school_year_id=school_year.id,
            school_year_label=school_year.year_label,
            start_date=charge_date,
            guardian=guardian,
            billing_item=item,
            unit_price=fee,
            actor_reference=str(actor_id) if actor_id else "cellen-system",
        )
        student_modality.inscription_instruction_id = instruction.id
        await db.commit()
        error = None
        try:
            await dispatch_instruction(db, instruction)
        except FinregError as exc:
            error = {"code": exc.code, "message": exc.detail}
            logger.warning(
                "Modality inscription %s for student modality %s left for the outbox: %s",
                instruction.id, student_modality.id, exc.code,
            )
        return {
            "mode": "finreg",
            "status": instruction.status,
            "instruction_id": str(instruction.id),
            "invoice_id": None,
            "error": error,
        }

    try:
        invoice = await DocumentEmissionService(db, school_id).emit_invoice(
            "FT",
            invoice_date=charge_date,
            billing_guardian_id=guardian.id,
            customer_nif=guardian.nif,
            customer_name=f"{guardian.first_name} {guardian.last_name}",
            lines=[{
                "billing_item_id": item.id,
                "description": item.name,
                "quantity": Decimal("1"),
                "unit_price": fee,
                "discount_percent": Decimal("0"),
                "iva_rate": item.iva_rate,
                "iva_exemption_reason": item.iva_exemption_reason,
                "iva_exemption_legend": item.iva_exemption_legend,
            }],
            child_id=child.id,
            issued_by=issued_by,
            school_year_id=school_year.id,
            reference_month=charge_date.replace(day=1),
            description=f"Inscrição — {modality.name}",
            notes=f"cellen-modality-inscription:{student_modality.id}",
            is_final_consumer=not bool(guardian.nif),
        )
    except Exception as exc:  # noqa: BLE001 - configuration error, not a partial charge
        await db.rollback()
        raise HTTPException(
            status_code=422,
            detail=f"Não foi possível emitir a factura da inscrição: {exc}",
        ) from exc
    student_modality.inscription_invoice_id = invoice.id
    await db.commit()
    return {
        "mode": "internal",
        "status": "issued",
        "instruction_id": None,
        "invoice_id": str(invoice.id),
        "invoice_number": invoice.full_document_number,
        "error": None,
    }


@router.post(
    "/modalities/{modality_id}/enroll",
    status_code=status.HTTP_201_CREATED,
)
async def enroll_in_modality(
    modality_id: uuid.UUID,
    body: ModalityEnrollmentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_school_admin),
):
    modality = await _modality_or_404(db, school_id, modality_id)
    if not modality.is_active:
        raise HTTPException(status_code=422, detail="A modalidade está inactiva")
    child = await _child_or_404(db, school_id, body.child_id)
    start_date = body.start_date or today_luanda()
    existing = (
        await db.execute(
            select(StudentModalityEnrollment).where(
                StudentModalityEnrollment.school_id == school_id,
                StudentModalityEnrollment.child_id == child.id,
                StudentModalityEnrollment.modality_id == modality.id,
                StudentModalityEnrollment.status == "active",
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=409, detail="O aluno já está inscrito nesta modalidade"
        )
    school_year = await _school_year_or_404(db, school_id, None)
    enrollment = StudentModalityEnrollment(
        school_id=school_id,
        child_id=child.id,
        modality_id=modality.id,
        start_date=start_date,
        status="active",
    )
    db.add(enrollment)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Já existe uma inscrição desta modalidade com esta data de início",
        )

    try:
        inscription = await _charge_modality_inscription(
            db,
            school_id=school_id,
            student_modality=enrollment,
            modality=modality,
            child=child,
            school_year=school_year,
            actor_id=_actor_id(user),
            issued_by=_employee_id(user),
        )
    except HTTPException:
        await db.rollback()
        raise

    await mark_plans_stale(
        db,
        school_id=school_id,
        school_year_id=school_year.id,
        child_ids={child.id},
    )
    await db.commit()
    await db.refresh(enrollment)
    item = (
        await db.get(BillingItem, modality.billing_item_id)
        if modality.billing_item_id
        else None
    )
    return {
        "enrollment": _modality_enrollment_payload(enrollment, modality, child),
        "inscription": inscription,
        "modality": _modality_payload(modality, item),
    }


@router.post("/modality-enrollments/{enrollment_id}/end")
async def end_modality_enrollment(
    enrollment_id: uuid.UUID,
    body: EndDatedBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    enrollment = (
        await db.execute(
            select(StudentModalityEnrollment).where(
                StudentModalityEnrollment.id == enrollment_id,
                StudentModalityEnrollment.school_id == school_id,
            )
        )
    ).scalar_one_or_none()
    if enrollment is None:
        raise HTTPException(status_code=404, detail="Inscrição não encontrada")
    if enrollment.status != "active":
        raise HTTPException(status_code=409, detail="A inscrição já terminou")
    end_date = body.end_date or today_luanda()
    if end_date < enrollment.start_date:
        raise HTTPException(
            status_code=422, detail="A data de fim não pode ser anterior ao início"
        )
    enrollment.end_date = end_date
    enrollment.status = body.status
    school_year = await get_school_year(db, school_id)
    if school_year is not None:
        await mark_plans_stale(
            db,
            school_id=school_id,
            school_year_id=school_year.id,
            child_ids={enrollment.child_id},
        )
    await db.commit()
    await db.refresh(enrollment)
    modality = await db.get(ExtracurricularModality, enrollment.modality_id)
    child = await db.get(Child, enrollment.child_id)
    return _modality_enrollment_payload(enrollment, modality, child)


# ─── school transport ───────────────────────────────────────────────────────

@router.get("/transport/routes")
async def list_transport_routes(
    active_only: bool = False,
    child_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(TransportRoute).where(TransportRoute.school_id == school_id)
    if active_only:
        query = query.where(TransportRoute.is_active.is_(True))
    routes = list(
        (await db.execute(query.order_by(TransportRoute.name))).scalars().all()
    )
    counts = dict(
        (
            await db.execute(
                select(StudentTransportAssignment.route_id, func.count())
                .where(
                    StudentTransportAssignment.school_id == school_id,
                    StudentTransportAssignment.status == "active",
                )
                .group_by(StudentTransportAssignment.route_id)
            )
        ).all()
    )
    item_ids = {
        route.billing_item_id for route in routes if route.billing_item_id is not None
    }
    items = {
        item.id: item
        for item in (
            await db.execute(
                select(BillingItem).where(
                    BillingItem.school_id == school_id, BillingItem.id.in_(item_ids)
                )
            )
        ).scalars().all()
    } if item_ids else {}
    child_assignments: dict[uuid.UUID, StudentTransportAssignment] = {}
    if child_id is not None:
        await _child_or_404(db, school_id, child_id)
        for assignment in (
            await db.execute(
                select(StudentTransportAssignment)
                .where(
                    StudentTransportAssignment.school_id == school_id,
                    StudentTransportAssignment.child_id == child_id,
                )
                .order_by(StudentTransportAssignment.start_date.desc())
            )
        ).scalars().all():
            child_assignments.setdefault(assignment.route_id, assignment)
    return [
        _route_payload(
            route,
            items.get(route.billing_item_id),
            assigned_count=counts.get(route.id, 0),
            assignment=child_assignments.get(route.id),
        )
        for route in routes
    ]


@router.post("/transport/routes", status_code=status.HTTP_201_CREATED)
async def create_transport_route(
    body: TransportRouteCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="O nome da rota é obrigatório")
    item = (
        await _item_or_422(db, school_id, body.billing_item_id)
        if body.billing_item_id
        else None
    )
    route = TransportRoute(
        school_id=school_id,
        name=name,
        description=body.description,
        monthly_price=Decimal(str(body.monthly_price)),
        billing_item_id=item.id if item is not None else None,
        is_active=body.is_active,
    )
    db.add(route)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Já existe uma rota com este nome")
    await db.refresh(route)
    return _route_payload(route, item)


@router.patch("/transport/routes/{route_id}")
async def update_transport_route(
    route_id: uuid.UUID,
    body: TransportRouteUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    route = await _route_or_404(db, school_id, route_id)
    fields = body.model_fields_set
    item = None
    if "billing_item_id" in fields and body.billing_item_id is not None:
        item = await _item_or_422(db, school_id, body.billing_item_id)
        route.billing_item_id = item.id
    elif "billing_item_id" in fields:
        route.billing_item_id = None
    if "name" in fields and body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(status_code=422, detail="O nome da rota é obrigatório")
        route.name = name
    if "description" in fields:
        route.description = body.description
    if "monthly_price" in fields and body.monthly_price is not None:
        route.monthly_price = Decimal(str(body.monthly_price))
    if "is_active" in fields and body.is_active is not None:
        route.is_active = body.is_active

    school_year = await get_school_year(db, school_id)
    if school_year is not None:
        child_ids = set(
            (
                await db.execute(
                    select(StudentTransportAssignment.child_id).where(
                        StudentTransportAssignment.school_id == school_id,
                        StudentTransportAssignment.route_id == route.id,
                    )
                )
            ).scalars().all()
        )
        if child_ids:
            await mark_plans_stale(
                db,
                school_id=school_id,
                school_year_id=school_year.id,
                child_ids=child_ids,
            )
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Já existe uma rota com este nome")
    await db.refresh(route)
    if route.billing_item_id and item is None:
        item = await db.get(BillingItem, route.billing_item_id)
    return _route_payload(route, item)


@router.post(
    "/transport/routes/{route_id}/assign",
    status_code=status.HTTP_201_CREATED,
)
async def assign_transport(
    route_id: uuid.UUID,
    body: TransportAssignmentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    route = await _route_or_404(db, school_id, route_id)
    if not route.is_active:
        raise HTTPException(status_code=422, detail="A rota está inactiva")
    child = await _child_or_404(db, school_id, body.child_id)
    start_date = body.start_date or today_luanda()
    active_assignments = list(
        (
            await db.execute(
                select(StudentTransportAssignment).where(
                    StudentTransportAssignment.school_id == school_id,
                    StudentTransportAssignment.child_id == child.id,
                    StudentTransportAssignment.status == "active",
                )
            )
        ).scalars().all()
    )
    for current in active_assignments:
        if current.start_date >= start_date:
            raise HTTPException(
                status_code=409,
                detail="Já existe uma atribuição de transporte activa nesta data",
            )
    for current in active_assignments:
        current.end_date = start_date - timedelta(days=1)
        current.status = "ended"
    assignment = StudentTransportAssignment(
        school_id=school_id,
        child_id=child.id,
        route_id=route.id,
        start_date=start_date,
        status="active",
    )
    db.add(assignment)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Já existe uma atribuição de transporte com esta data de início",
        )
    school_year = await get_school_year(db, school_id)
    if school_year is not None:
        await mark_plans_stale(
            db,
            school_id=school_id,
            school_year_id=school_year.id,
            child_ids={child.id},
        )
    await db.commit()
    await db.refresh(assignment)
    return {
        "assignment": _transport_assignment_payload(assignment, route, child),
        "route": _route_payload(
            route,
            await db.get(BillingItem, route.billing_item_id)
            if route.billing_item_id
            else None,
        ),
    }


@router.post("/transport/assignments/{assignment_id}/end")
async def end_transport_assignment(
    assignment_id: uuid.UUID,
    body: EndDatedBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    assignment = (
        await db.execute(
            select(StudentTransportAssignment).where(
                StudentTransportAssignment.id == assignment_id,
                StudentTransportAssignment.school_id == school_id,
            )
        )
    ).scalar_one_or_none()
    if assignment is None:
        raise HTTPException(status_code=404, detail="Atribuição não encontrada")
    if assignment.status != "active":
        raise HTTPException(status_code=409, detail="A atribuição já terminou")
    end_date = body.end_date or today_luanda()
    if end_date < assignment.start_date:
        raise HTTPException(
            status_code=422, detail="A data de fim não pode ser anterior ao início"
        )
    assignment.end_date = end_date
    assignment.status = body.status
    school_year = await get_school_year(db, school_id)
    if school_year is not None:
        await mark_plans_stale(
            db,
            school_id=school_id,
            school_year_id=school_year.id,
            child_ids={assignment.child_id},
        )
    await db.commit()
    await db.refresh(assignment)
    route = await db.get(TransportRoute, assignment.route_id)
    child = await db.get(Child, assignment.child_id)
    return _transport_assignment_payload(assignment, route, child)


# ─── student profile and summary ────────────────────────────────────────────

@router.get("/students/{child_id}/profile")
async def get_student_profile(
    child_id: uuid.UUID,
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    child = await _child_or_404(db, school_id, child_id)
    school_year = await _school_year_or_404(db, school_id, school_year_id)
    profile = (
        await db.execute(
            select(StudentFinanceProfile).where(
                StudentFinanceProfile.school_id == school_id,
                StudentFinanceProfile.child_id == child.id,
                StudentFinanceProfile.school_year_id == school_year.id,
            )
        )
    ).scalar_one_or_none()
    policy = await get_fee_policy(db, school_id, school_year.id)
    return {
        "school_year": _year_payload(school_year),
        "policy": _policy_payload(policy),
        "profile": await _profile_payload(
            db,
            school_id=school_id,
            child=child,
            school_year=school_year,
            profile=profile,
            policy=policy,
        ),
    }


@router.put("/students/{child_id}/profile")
async def update_student_profile(
    child_id: uuid.UUID,
    body: StudentProfileUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    child = await _child_or_404(db, school_id, child_id)
    school_year = await _school_year_or_404(db, school_id, body.school_year_id)
    policy = await get_fee_policy(db, school_id, school_year.id)
    enrollment = await active_enrollment_for_child(
        db, school_id, child.id, school_year.id
    )
    profile = (
        await db.execute(
            select(StudentFinanceProfile).where(
                StudentFinanceProfile.school_id == school_id,
                StudentFinanceProfile.child_id == child.id,
                StudentFinanceProfile.school_year_id == school_year.id,
            )
        )
    ).scalar_one_or_none()
    if profile is None:
        profile = await ensure_profile(
            db,
            school_id=school_id,
            child_id=child.id,
            school_year_id=school_year.id,
            enrollment_date=(
                enrollment.enrollment_date
                if enrollment is not None
                else school_year.start_date
            ),
        )
    fields = body.model_fields_set

    if "billing_guardian_id" in fields and body.billing_guardian_id is not None:
        linked = (
            await db.execute(
                select(ChildGuardian.id).where(
                    ChildGuardian.school_id == school_id,
                    ChildGuardian.child_id == child.id,
                    ChildGuardian.guardian_id == body.billing_guardian_id,
                )
            )
        ).scalar_one_or_none()
        if linked is None:
            raise HTTPException(
                status_code=422,
                detail="O encarregado indicado não está ligado a este aluno",
            )
        profile.billing_guardian_id = body.billing_guardian_id
    elif "billing_guardian_id" in fields:
        profile.billing_guardian_id = None

    if "tuition_billing_item_id" in fields:
        if body.tuition_billing_item_id is not None:
            item = await _item_or_422(
                db, school_id, body.tuition_billing_item_id
            )
            profile.tuition_billing_item_id = item.id
        else:
            profile.tuition_billing_item_id = None

    if "tuition_override" in fields:
        profile.tuition_override = (
            Decimal(str(body.tuition_override))
            if body.tuition_override is not None
            else None
        )
    if "billing_day" in fields:
        profile.billing_day = body.billing_day
    if "status" in fields and body.status is not None:
        profile.status = body.status
    if "starts_on" in fields:
        profile.starts_on = body.starts_on
    if "ends_on" in fields:
        profile.ends_on = body.ends_on
    if profile.starts_on and profile.ends_on and profile.starts_on > profile.ends_on:
        raise HTTPException(
            status_code=422,
            detail="A data de início não pode ser posterior à data de fim",
        )
    profile.plan_stale = True
    await db.commit()
    await db.refresh(profile)
    policy = await get_fee_policy(db, school_id, school_year.id)
    return {
        "school_year": _year_payload(school_year),
        "policy": _policy_payload(policy),
        "profile": await _profile_payload(
            db,
            school_id=school_id,
            child=child,
            school_year=school_year,
            profile=profile,
            policy=policy,
        ),
    }


@router.get("/students/{child_id}/summary")
async def student_finance_summary(
    child_id: uuid.UUID,
    billing_month: Optional[str] = None,
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    child = await _child_or_404(db, school_id, child_id)
    school_year = await _school_year_or_404(db, school_id, school_year_id)
    profile = (
        await db.execute(
            select(StudentFinanceProfile).where(
                StudentFinanceProfile.school_id == school_id,
                StudentFinanceProfile.child_id == child.id,
                StudentFinanceProfile.school_year_id == school_year.id,
            )
        )
    ).scalar_one_or_none()
    policy = await get_fee_policy(db, school_id, school_year.id)
    month = billing_month or current_billing_month()
    preview = None
    preview_error = None
    try:
        preview = await preview_billing(
            db,
            school_id=school_id,
            billing_month=month,
            school_year_id=school_year.id,
            child_id=child.id,
        )
    except BillingError as exc:
        preview_error = {"code": exc.code, "message": exc.detail}

    modality_rows = list(
        (
            await db.execute(
                select(StudentModalityEnrollment, ExtracurricularModality)
                .join(
                    ExtracurricularModality,
                    ExtracurricularModality.id
                    == StudentModalityEnrollment.modality_id,
                )
                .where(
                    StudentModalityEnrollment.school_id == school_id,
                    StudentModalityEnrollment.child_id == child.id,
                    StudentModalityEnrollment.start_date <= school_year.end_date,
                    (
                        StudentModalityEnrollment.end_date.is_(None)
                        | (StudentModalityEnrollment.end_date >= school_year.start_date)
                    ),
                )
                .order_by(StudentModalityEnrollment.start_date.desc())
            )
        ).all()
    )
    transport_rows = list(
        (
            await db.execute(
                select(StudentTransportAssignment, TransportRoute)
                .join(
                    TransportRoute,
                    TransportRoute.id == StudentTransportAssignment.route_id,
                )
                .where(
                    StudentTransportAssignment.school_id == school_id,
                    StudentTransportAssignment.child_id == child.id,
                    StudentTransportAssignment.start_date <= school_year.end_date,
                    (
                        StudentTransportAssignment.end_date.is_(None)
                        | (
                            StudentTransportAssignment.end_date
                            >= school_year.start_date
                        )
                    ),
                )
                .order_by(StudentTransportAssignment.start_date.desc())
            )
        ).all()
    )
    debts = None
    debts_error = None
    try:
        debts = await list_debts(db, school_id=school_id, student_id=child.id)
    except BillingError as exc:
        debts_error = {"code": exc.code, "message": exc.detail}

    return {
        "child": {
            "id": str(child.id),
            "name": f"{child.first_name} {child.last_name}",
            "cedula": child.cedula,
        },
        "school_year": _year_payload(school_year),
        "policy": _policy_payload(policy),
        "profile": await _profile_payload(
            db,
            school_id=school_id,
            child=child,
            school_year=school_year,
            profile=profile,
            policy=policy,
        ),
        "preview": preview,
        "preview_error": preview_error,
        "modalities": [
            _modality_enrollment_payload(enrollment, modality, child)
            for enrollment, modality in modality_rows
        ],
        "transport": [
            _transport_assignment_payload(assignment, route, child)
            for assignment, route in transport_rows
        ],
        "debts": debts,
        "debts_error": debts_error,
    }


# ─── debt control and reports ───────────────────────────────────────────────

@router.get("/debts")
async def debts_endpoint(
    as_of: Optional[date] = None,
    overdue_only: bool = False,
    student_id: Optional[uuid.UUID] = None,
    guardian_id: Optional[uuid.UUID] = None,
    service: Optional[str] = None,
    bucket: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Every open debt, from FinReg or from local invoices, in one shape.

    Each row carries the family's open payment reference, if one exists, so
    the debt list says "reference sent" instead of offering to create one the
    dispatcher already issued.
    """
    try:
        result = await list_debts(
            db,
            school_id=school_id,
            as_of=as_of,
            overdue_only=overdue_only,
            student_id=student_id,
            guardian_id=guardian_id,
            service=service,
            bucket=bucket,
        )
    except BillingError as exc:
        _raise_billing(exc)
    document_ids = []
    for row in result["rows"]:
        try:
            document_ids.append(uuid.UUID(str(row.get("document_id"))))
        except ValueError:
            continue
    references = await active_rail_references(
        db, school_id=school_id, document_ids=document_ids
    )
    for row in result["rows"]:
        row["payment_reference"] = references.get(str(row.get("document_id")))
    return result


@router.get("/students/{child_id}/debts")
async def student_debts_endpoint(
    child_id: uuid.UUID,
    overdue_only: bool = False,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    child = await _child_or_404(db, school_id, child_id)
    try:
        return await list_debts(
            db, school_id=school_id, student_id=child.id, overdue_only=overdue_only
        )
    except BillingError as exc:
        _raise_billing(exc)


@router.get("/reports/services")
async def services_report_endpoint(
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    today = today_luanda()
    start = date_from or today.replace(day=1)
    end = date_to or today
    try:
        return await service_report(
            db, school_id=school_id, date_from=start, date_to=end
        )
    except BillingError as exc:
        _raise_billing(exc)


@router.get("/dashboard")
async def finance_dashboard_endpoint(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    try:
        return await finance_dashboard(db, school_id=school_id)
    except BillingError as exc:
        _raise_billing(exc)


# ─── billing runs ───────────────────────────────────────────────────────────

@router.post("/runs/preview")
async def preview_run(
    body: BillingPreviewRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    try:
        return await preview_billing(
            db,
            school_id=school_id,
            billing_month=body.billing_month,
            school_year_id=body.school_year_id,
            child_id=body.child_id,
        )
    except BillingError as exc:
        _raise_billing(exc)


@router.post("/runs", status_code=status.HTTP_201_CREATED)
async def generate_billing_run(
    body: BillingRunRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_finance_access),
):
    try:
        run, created = await run_billing(
            db,
            school_id=school_id,
            billing_month=body.billing_month,
            school_year_id=body.school_year_id,
            actor_id=_actor_id(user),
            issued_by=_employee_id(user),
        )
    except BillingError as exc:
        _raise_billing(exc)
    return {
        "created": created,
        "run": await _run_payload(db, run),
    }


@router.get("/runs")
async def list_billing_runs(
    limit: int = 24,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    runs = await list_runs(db, school_id=school_id, limit=min(max(limit, 1), 100))
    return [await _run_payload(db, run) for run in runs]


@router.get("/runs/{run_id}")
async def get_billing_run(
    run_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    run = await get_run(db, school_id=school_id, run_id=run_id)
    if run is None:
        raise HTTPException(status_code=404, detail="Execução não encontrada")
    await refresh_run_status(db, run)
    return await _run_payload(db, run)


@router.post("/rebuild-plans")
async def rebuild_student_plans(
    body: BillingRunRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_school_admin),
):
    try:
        return await rebuild_plans(
            db,
            school_id=school_id,
            billing_month=body.billing_month,
            school_year_id=body.school_year_id,
            actor_id=_actor_id(user),
        )
    except BillingError as exc:
        _raise_billing(exc)


# ═══════════════════════════════════════════════════════════════════════════
# principia-pay reference payments
#
# A reference is only ever opened against an open debt (FinReg receivable or
# local invoice), and its settlement goes back to the engine that owns the
# school. The rail never sees a fiscal document; the fiscal identity stays
# here.
# ═══════════════════════════════════════════════════════════════════════════


async def _rail_reference_or_404(
    db: AsyncSession, *, school_id: uuid.UUID, reference_id: uuid.UUID
) -> PaymentReference:
    row = (
        await db.execute(
            select(PaymentReference).where(
                PaymentReference.id == reference_id,
                PaymentReference.school_id == school_id,
                PaymentReference.provider == principia_pay.PROVIDER,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="Referência não encontrada")
    return row


@router.get("/principia-pay")
async def principia_pay_connection_status(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    return await principia_pay.connection_status(db, school_id=school_id)


@router.get("/principia-pay/check")
async def principia_pay_check_connection(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Live probe: is the stored key still accepted by the rail?

    The plain status route is a database read and can look green long after
    a key stopped working. This one earns the tick.
    """
    return await principia_pay.probe_connection(db, school_id=school_id)


@router.post("/principia-pay/register")
async def register_principia_pay(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    try:
        await principia_pay.ensure_connection(db, school_id=school_id)
    except BillingError as exc:
        _raise_billing(exc)
    return await principia_pay.connection_status(db, school_id=school_id)


@router.get("/principia-pay/references")
async def list_rail_references(
    status_filter: Optional[str] = None,
    billing_guardian_id: Optional[uuid.UUID] = None,
    limit: int = 100,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    rows = await principia_pay.list_references(
        db,
        school_id=school_id,
        status_filter=status_filter,
        guardian_id=billing_guardian_id,
        limit=limit,
    )
    return [PaymentReferenceResponse.model_validate(row) for row in rows]


@router.post(
    "/principia-pay/references",
    response_model=PaymentReferenceResponse,
    status_code=201,
)
async def create_rail_reference(
    body: RailReferenceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_finance_access),
):
    try:
        reference = await principia_pay.create_reference(
            db,
            school_id=school_id,
            document_id=body.document_id,
            amount=body.amount,
            return_url=body.return_url,
            requested_by=_employee_id(user) or _actor_id(user),
        )
    except BillingError as exc:
        _raise_billing(exc)
    return PaymentReferenceResponse.model_validate(reference)


@router.post(
    "/principia-pay/references/{reference_id}/refresh",
    response_model=PaymentReferenceResponse,
)
async def refresh_rail_reference(
    reference_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    reference = await _rail_reference_or_404(
        db, school_id=school_id, reference_id=reference_id
    )
    try:
        await principia_pay.refresh_reference(db, reference=reference)
    except BillingError as exc:
        _raise_billing(exc)
    return PaymentReferenceResponse.model_validate(reference)


@router.post("/principia-pay/callback", include_in_schema=False)
async def principia_pay_callback(request: Request, db: AsyncSession = Depends(get_db)):
    """Public rail webhook. The HMAC is per school; the poll is authoritative."""
    body = await request.body()
    signature = request.headers.get(
        principia_pay.PrincipiaPayClient.WEBHOOK_SIGNATURE_HEADER
    )
    try:
        return await principia_pay.handle_callback(
            db, body=body, signature=signature
        )
    except BillingError as exc:
        raise HTTPException(
            status_code=exc.status_code,
            detail={"code": exc.code, "message": exc.detail},
        ) from exc


# ═══════════════════════════════════════════════════════════════════════════
# Dunning (cobrança amigável)
#
# The ladder is policy data; these endpoints preview it and show exactly
# what was delivered on which channel. Sending itself runs daily at Luanda
# midnight.
# ═══════════════════════════════════════════════════════════════════════════


def _delivery_payload(row) -> dict:
    return {
        "id": str(row.id),
        "source_kind": row.source_kind,
        "source_id": str(row.source_id),
        "document_number": row.document_number,
        "guardian_id": str(row.guardian_id) if row.guardian_id else None,
        "student_id": str(row.student_id) if row.student_id else None,
        "level": row.level,
        "offset_days": row.offset_days,
        "channel": row.channel,
        "status": row.status,
        "error": row.error,
        "message_snapshot": row.message_snapshot,
        "sent_at": row.sent_at.isoformat() if row.sent_at else None,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


@router.get("/dunning/deliveries")
async def get_dunning_deliveries(
    status_filter: Optional[str] = None,
    billing_guardian_id: Optional[uuid.UUID] = None,
    limit: int = 200,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    rows = await list_deliveries(
        db,
        school_id=school_id,
        status=status_filter,
        guardian_id=billing_guardian_id,
        limit=limit,
    )
    return [_delivery_payload(row) for row in rows]


@router.post("/dunning/run")
async def run_dunning_now(
    body: DunningRunRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Preview (dry_run) or send today's reminders for this school."""
    try:
        return await run_dunning(
            db,
            school_id=school_id,
            as_of=body.as_of,
            dry_run=body.dry_run,
        )
    except BillingError as exc:
        _raise_billing(exc)
