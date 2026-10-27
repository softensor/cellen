# -*- coding: utf-8 -*-
"""ORM loaders and profile maintenance for fee automation.

The composer is pure; this module is the only place that knows how a
student's policy, enrollment, guardians, modalities, transport and catalogue
prices come together. It also owns the small mutations that keep a finance
profile in step with guardian links.
"""
from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import Optional
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.academic import Enrollment, SchoolYear
from app.models.billing import (
    ExtracurricularModality,
    SchoolFeePolicy,
    StudentFinanceProfile,
    StudentModalityEnrollment,
    StudentTransportAssignment,
    TransportRoute,
)
from app.models.finance import BillingItem, BillingItemPrice
from app.models.person import Child, ChildGuardian, Guardian
from app.services.billing_composer import (
    CatalogItem,
    FeePolicyConfig,
    ModalityCharge,
    StudentBillingInput,
    TransportCharge,
    month_bounds,
)
from app.utils.agt import today_luanda


DEFAULT_POLICY: dict = {
    "default_tuition_billing_item_id": None,
    "default_enrollment_fee": None,
    "sibling_discount_pct": Decimal("5.00"),
    "sibling_discount_min_children": 2,
    "sibling_discount_scope": "additional_children",
    "due_days": 5,
    "billing_day": 1,
    "auto_generate": False,
    "proration_policy": "pro_rata_days",
    "late_fee_enabled": False,
    "late_fee_billing_item_id": None,
    "late_fee_base": "outstanding",
    "late_fee_bands": [],
    "dunning_enabled": False,
    "dunning_schedule": [],
    "dunning_message_template": None,
}


def plan_external_id(child_id: UUID, school_year_id: UUID) -> UUID:
    """A stable plan identity even before the profile row exists."""
    return uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"cellen-billing-plan:{child_id}:{school_year_id}",
    )


def policy_snapshot(policy: Optional[SchoolFeePolicy]) -> FeePolicyConfig:
    if policy is None:
        values = DEFAULT_POLICY
        return FeePolicyConfig(
            sibling_discount_pct=values["sibling_discount_pct"],
            sibling_discount_min_children=values["sibling_discount_min_children"],
            sibling_discount_scope=values["sibling_discount_scope"],
            due_days=values["due_days"],
            billing_day=values["billing_day"],
            proration_policy=values["proration_policy"],
            default_enrollment_fee=values["default_enrollment_fee"],
        )
    return FeePolicyConfig(
        sibling_discount_pct=Decimal(policy.sibling_discount_pct),
        sibling_discount_min_children=policy.sibling_discount_min_children,
        sibling_discount_scope=policy.sibling_discount_scope,
        due_days=policy.due_days,
        billing_day=policy.billing_day,
        proration_policy=policy.proration_policy,
        default_enrollment_fee=(
            Decimal(policy.default_enrollment_fee)
            if policy.default_enrollment_fee is not None
            else None
        ),
    )


def policy_values(policy: Optional[SchoolFeePolicy]) -> dict:
    """API representation of the effective policy (row or virtual defaults)."""
    if policy is None:
        return {
            **DEFAULT_POLICY,
            "sibling_discount_pct": str(DEFAULT_POLICY["sibling_discount_pct"]),
            "default_enrollment_fee": None,
            "is_default": True,
        }
    return {
        "id": str(policy.id),
        "school_year_id": str(policy.school_year_id),
        "default_tuition_billing_item_id": (
            str(policy.default_tuition_billing_item_id)
            if policy.default_tuition_billing_item_id
            else None
        ),
        "default_enrollment_fee": (
            str(policy.default_enrollment_fee)
            if policy.default_enrollment_fee is not None
            else None
        ),
        "sibling_discount_pct": str(policy.sibling_discount_pct),
        "sibling_discount_min_children": policy.sibling_discount_min_children,
        "sibling_discount_scope": policy.sibling_discount_scope,
        "due_days": policy.due_days,
        "billing_day": policy.billing_day,
        "auto_generate": policy.auto_generate,
        "proration_policy": policy.proration_policy,
        "late_fee_enabled": policy.late_fee_enabled,
        "late_fee_billing_item_id": (
            str(policy.late_fee_billing_item_id)
            if policy.late_fee_billing_item_id
            else None
        ),
        "late_fee_base": policy.late_fee_base,
        "late_fee_bands": policy.late_fee_bands or [],
        "dunning_enabled": policy.dunning_enabled,
        "dunning_schedule": policy.dunning_schedule or [],
        "dunning_message_template": policy.dunning_message_template,
        "is_default": False,
    }


async def get_school_year(
    db: AsyncSession, school_id: UUID, school_year_id: Optional[UUID] = None
) -> Optional[SchoolYear]:
    query = select(SchoolYear).where(SchoolYear.school_id == school_id)
    if school_year_id is not None:
        return (await db.execute(query.where(SchoolYear.id == school_year_id))).scalar_one_or_none()
    active = (
        await db.execute(
            query.where(SchoolYear.is_active.is_(True))
            .order_by(SchoolYear.start_date.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if active is not None:
        return active
    return (
        await db.execute(query.order_by(SchoolYear.start_date.desc()).limit(1))
    ).scalar_one_or_none()


async def get_fee_policy(
    db: AsyncSession, school_id: UUID, school_year_id: UUID
) -> Optional[SchoolFeePolicy]:
    return (
        await db.execute(
            select(SchoolFeePolicy).where(
                SchoolFeePolicy.school_id == school_id,
                SchoolFeePolicy.school_year_id == school_year_id,
            )
        )
    ).scalar_one_or_none()


async def ensure_profile(
    db: AsyncSession,
    *,
    school_id: UUID,
    child_id: UUID,
    school_year_id: UUID,
    guardian_id: Optional[UUID] = None,
    enrollment_date: Optional[date] = None,
    commit: bool = False,
) -> StudentFinanceProfile:
    profile = (
        await db.execute(
            select(StudentFinanceProfile).where(
                StudentFinanceProfile.child_id == child_id,
                StudentFinanceProfile.school_year_id == school_year_id,
            )
        )
    ).scalar_one_or_none()
    if profile is None:
        profile = StudentFinanceProfile(
            school_id=school_id,
            child_id=child_id,
            school_year_id=school_year_id,
            billing_guardian_id=guardian_id,
            plan_external_id=plan_external_id(child_id, school_year_id),
            starts_on=enrollment_date or today_luanda(),
            status="active",
            plan_stale=True,
        )
        db.add(profile)
        await db.flush()
    elif profile.billing_guardian_id is None and guardian_id is not None:
        profile.billing_guardian_id = guardian_id
        profile.plan_stale = True
    if commit:
        await db.commit()
    return profile


async def mark_plans_stale(
    db: AsyncSession,
    *,
    school_id: UUID,
    school_year_id: UUID,
    guardian_ids: set[UUID] | None = None,
    child_ids: set[UUID] | None = None,
) -> int:
    """Mark affected plans for rebuild after a family or service change.

    A sibling count change can alter every child's tuition discount in the
    family, not only the child whose guardian link changed, so the caller
    supplies the guardians whose families moved.
    """
    conditions = [
        StudentFinanceProfile.school_id == school_id,
        StudentFinanceProfile.school_year_id == school_year_id,
    ]
    if guardian_ids:
        conditions.append(StudentFinanceProfile.billing_guardian_id.in_(guardian_ids))
    if child_ids:
        if guardian_ids:
            conditions[-1] = (
                StudentFinanceProfile.billing_guardian_id.in_(guardian_ids)
                | StudentFinanceProfile.child_id.in_(child_ids)
            )
        else:
            conditions.append(StudentFinanceProfile.child_id.in_(child_ids))
    result = await db.execute(
        update(StudentFinanceProfile)
        .where(*conditions)
        .values(plan_stale=True)
    )
    return result.rowcount or 0


async def guardian_links_for_child(
    db: AsyncSession, school_id: UUID, child_id: UUID
) -> list[ChildGuardian]:
    return list(
        (
            await db.execute(
                select(ChildGuardian)
                .where(
                    ChildGuardian.school_id == school_id,
                    ChildGuardian.child_id == child_id,
                )
                .order_by(ChildGuardian.is_primary_contact.desc(), ChildGuardian.id)
            )
        )
        .scalars()
        .all()
    )


async def resolve_billing_guardian(
    db: AsyncSession,
    *,
    school_id: UUID,
    child_id: UUID,
    preferred_guardian_id: Optional[UUID] = None,
) -> Optional[Guardian]:
    links = await guardian_links_for_child(db, school_id, child_id)
    if not links:
        return None
    chosen = None
    if preferred_guardian_id is not None:
        chosen = next((l for l in links if l.guardian_id == preferred_guardian_id), None)
    if chosen is None:
        chosen = links[0]
    return await db.get(Guardian, chosen.guardian_id)


async def active_enrollment_for_child(
    db: AsyncSession, school_id: UUID, child_id: UUID, school_year_id: UUID
) -> Optional[Enrollment]:
    return (
        await db.execute(
            select(Enrollment).where(
                Enrollment.school_id == school_id,
                Enrollment.child_id == child_id,
                Enrollment.school_year_id == school_year_id,
                Enrollment.status == "active",
            )
        )
    ).scalar_one_or_none()


def _catalog_item(item: Optional[BillingItem]) -> Optional[CatalogItem]:
    if item is None:
        return None
    return CatalogItem(
        id=item.id,
        code=item.code,
        name=item.name,
        unit_price=Decimal(item.unit_price),
        iva_rate=Decimal(item.iva_rate),
        tax_option_code=item.finreg_tax_option_code,
        exemption_reason=item.iva_exemption_reason,
        exemption_legend=item.iva_exemption_legend,
        category=item.category,
        is_active=item.is_active,
    )


async def load_billing_inputs(
    db: AsyncSession,
    *,
    school_id: UUID,
    school_year: SchoolYear,
    billing_month: str,
    child_id: Optional[UUID] = None,
) -> tuple[list[StudentBillingInput], list[dict], Optional[SchoolFeePolicy]]:
    """Load everything the pure composer needs for one month.

    Returns the billable inputs, the active enrollments that cannot be billed
    (so the director sees why), and the policy row in use.
    """
    month_start, month_end = month_bounds(billing_month)
    enrollment_query = select(Enrollment).where(
        Enrollment.school_id == school_id,
        Enrollment.school_year_id == school_year.id,
        Enrollment.status == "active",
    )
    if child_id is not None:
        enrollment_query = enrollment_query.where(Enrollment.child_id == child_id)
    enrollments = list(
        (await db.execute(enrollment_query.order_by(Enrollment.created_at))).scalars().all()
    )
    policy = await get_fee_policy(db, school_id, school_year.id)
    if not enrollments:
        return [], [], policy

    child_ids = [enrollment.child_id for enrollment in enrollments]
    children = {
        child.id: child
        for child in (
            await db.execute(select(Child).where(Child.id.in_(child_ids)))
        ).scalars().all()
    }
    profiles = {
        profile.child_id: profile
        for profile in (
            await db.execute(
                select(StudentFinanceProfile).where(
                    StudentFinanceProfile.school_id == school_id,
                    StudentFinanceProfile.school_year_id == school_year.id,
                    StudentFinanceProfile.child_id.in_(child_ids),
                )
            )
        ).scalars().all()
    }
    links = list(
        (
            await db.execute(
                select(ChildGuardian)
                .where(
                    ChildGuardian.school_id == school_id,
                    ChildGuardian.child_id.in_(child_ids),
                )
                .order_by(ChildGuardian.is_primary_contact.desc(), ChildGuardian.id)
            )
        ).scalars().all()
    )
    links_by_child: dict[UUID, list[ChildGuardian]] = {}
    for link in links:
        links_by_child.setdefault(link.child_id, []).append(link)
    guardian_ids = {link.guardian_id for link in links}
    guardians = {
        guardian.id: guardian
        for guardian in (
            await db.execute(select(Guardian).where(Guardian.id.in_(guardian_ids)))
        ).scalars().all()
    } if guardian_ids else {}

    modality_rows = list(
        (
            await db.execute(
                select(StudentModalityEnrollment, ExtracurricularModality)
                .join(
                    ExtracurricularModality,
                    ExtracurricularModality.id == StudentModalityEnrollment.modality_id,
                )
                .where(
                    StudentModalityEnrollment.school_id == school_id,
                    StudentModalityEnrollment.child_id.in_(child_ids),
                    StudentModalityEnrollment.status.in_(("active", "ended")),
                    StudentModalityEnrollment.start_date <= month_end,
                    (
                        StudentModalityEnrollment.end_date.is_(None)
                        | (StudentModalityEnrollment.end_date >= month_start)
                    ),
                )
                .order_by(StudentModalityEnrollment.start_date)
            )
        ).all()
    )
    transport_rows = list(
        (
            await db.execute(
                select(StudentTransportAssignment, TransportRoute)
                .join(TransportRoute, TransportRoute.id == StudentTransportAssignment.route_id)
                .where(
                    StudentTransportAssignment.school_id == school_id,
                    StudentTransportAssignment.child_id.in_(child_ids),
                    StudentTransportAssignment.status.in_(("active", "ended")),
                    StudentTransportAssignment.start_date <= month_end,
                    (
                        StudentTransportAssignment.end_date.is_(None)
                        | (StudentTransportAssignment.end_date >= month_start)
                    ),
                )
                .order_by(StudentTransportAssignment.start_date)
            )
        ).all()
    )

    item_ids = {
        item_id
        for item_id in (
            [policy.default_tuition_billing_item_id if policy else None]
            + [profile.tuition_billing_item_id for profile in profiles.values()]
            + [modality.billing_item_id for _, modality in modality_rows]
            + [route.billing_item_id for _, route in transport_rows]
        )
        if item_id is not None
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
    prices = {
        price.billing_item_id: Decimal(price.unit_price)
        for price in (
            await db.execute(
                select(BillingItemPrice).where(
                    BillingItemPrice.school_id == school_id,
                    BillingItemPrice.school_year_id == school_year.id,
                    BillingItemPrice.billing_item_id.in_(item_ids),
                )
            )
        ).scalars().all()
    } if item_ids else {}

    modalities_by_child: dict[UUID, list[ModalityCharge]] = {}
    for enrollment, modality in modality_rows:
        modalities_by_child.setdefault(enrollment.child_id, []).append(
            ModalityCharge(
                enrollment_id=enrollment.id,
                modality_id=modality.id,
                name=modality.name,
                monthly_fee=Decimal(modality.monthly_fee),
                item=_catalog_item(items.get(modality.billing_item_id)),
                start_date=enrollment.start_date,
                end_date=enrollment.end_date,
            )
        )
    transport_by_child: dict[UUID, TransportCharge] = {}
    for assignment, route in transport_rows:
        existing = transport_by_child.get(assignment.child_id)
        if existing is None or assignment.start_date > existing.start_date:
            transport_by_child[assignment.child_id] = TransportCharge(
                assignment_id=assignment.id,
                route_id=route.id,
                route_name=route.name,
                monthly_price=Decimal(route.monthly_price),
                item=_catalog_item(items.get(route.billing_item_id)),
                start_date=assignment.start_date,
                end_date=assignment.end_date,
            )

    inputs: list[StudentBillingInput] = []
    unbilled: list[dict] = []
    for enrollment in enrollments:
        child = children.get(enrollment.child_id)
        if child is None:
            continue
        profile = profiles.get(child.id)
        child_links = links_by_child.get(child.id) or []
        if not child_links:
            unbilled.append({
                "child_id": str(child.id),
                "child_name": f"{child.first_name} {child.last_name}",
                "reason": "missing_guardian",
            })
            continue
        preferred = profile.billing_guardian_id if profile else None
        chosen_link = (
            next((l for l in child_links if l.guardian_id == preferred), None)
            if preferred
            else None
        ) or child_links[0]
        guardian = guardians.get(chosen_link.guardian_id)
        if guardian is None:
            unbilled.append({
                "child_id": str(child.id),
                "child_name": f"{child.first_name} {child.last_name}",
                "reason": "missing_guardian",
            })
            continue
        if profile is not None and profile.status != "active":
            unbilled.append({
                "child_id": str(child.id),
                "child_name": f"{child.first_name} {child.last_name}",
                "reason": "plan_paused" if profile.status == "paused" else "plan_withdrawn",
            })
            continue

        tuition_item_id = (
            profile.tuition_billing_item_id
            if profile is not None and profile.tuition_billing_item_id
            else (policy.default_tuition_billing_item_id if policy else None)
        )
        tuition_item = items.get(tuition_item_id) if tuition_item_id else None
        tuition_base = (
            prices.get(tuition_item.id, Decimal(tuition_item.unit_price))
            if tuition_item is not None
            else Decimal("0")
        )
        starts_on = max(enrollment.enrollment_date, school_year.start_date)
        if profile is not None and profile.starts_on and profile.starts_on > starts_on:
            starts_on = profile.starts_on
        ends_on = school_year.end_date
        if profile is not None and profile.ends_on and profile.ends_on < ends_on:
            ends_on = profile.ends_on
        billing_day = (
            profile.billing_day
            if profile is not None and profile.billing_day
            else (policy.billing_day if policy else DEFAULT_POLICY["billing_day"])
        )
        inputs.append(StudentBillingInput(
            child_id=child.id,
            child_name=f"{child.first_name} {child.last_name}",
            guardian_id=guardian.id,
            guardian_name=f"{guardian.first_name} {guardian.last_name}",
            guardian_nif=guardian.nif,
            enrollment_id=enrollment.id,
            enrollment_date=enrollment.enrollment_date,
            tuition_item=_catalog_item(tuition_item),
            tuition_base_price=tuition_base,
            tuition_override=(
                Decimal(profile.tuition_override)
                if profile is not None and profile.tuition_override is not None
                else None
            ),
            starts_on=starts_on,
            ends_on=ends_on,
            billing_day=billing_day,
            plan_external_id=(
                profile.plan_external_id
                if profile is not None
                else plan_external_id(child.id, school_year.id)
            ),
            transport=transport_by_child.get(child.id),
            modalities=tuple(modalities_by_child.get(child.id, ())),
            sort_created_at=child.created_at,
        ))
    return inputs, unbilled, policy
