#!/usr/bin/env bash
# Read-only diagnosis of a school's fee-automation inputs.
#
# Prints the billing catalog, the school-year price overrides, the fee
# policy and every active student's class level and finance profile, so the
# tuition item can be linked deliberately instead of guessed. It writes
# nothing.
set -uo pipefail

CELLEN_DIR=${CELLEN_DIR:-/var/www/cellen}
SCHOOL_SLUG=${SCHOOL_SLUG:-rainha-njinga}

[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
[[ -f $CELLEN_DIR/.env ]] || { echo "missing $CELLEN_DIR/.env" >&2; exit 2; }

cd "$CELLEN_DIR" || exit 2
set -a
# shellcheck disable=SC1091
source "$CELLEN_DIR/.env"
set +a
export PYTHONPATH="$CELLEN_DIR"
export PYTHONDONTWRITEBYTECODE=1

"$CELLEN_DIR/.venv/bin/python" - "$SCHOOL_SLUG" <<'PY'
import asyncio
import json
import sys

from sqlalchemy import select

# SQLAlchemy resolves string relationships lazily; import every model module
# for the same reason the acceptance helper does.
import app.models.absence  # noqa: F401
import app.models.academic  # noqa: F401
import app.models.billing  # noqa: F401
import app.models.billing_item  # noqa: F401
import app.models.caderneta  # noqa: F401
import app.models.employee  # noqa: F401
import app.models.finance  # noqa: F401
import app.models.finreg_integration  # noqa: F401
import app.models.food  # noqa: F401
import app.models.grades  # noqa: F401
import app.models.immunization  # noqa: F401
import app.models.modern  # noqa: F401
import app.models.person  # noqa: F401
import app.models.pickup_auth  # noqa: F401
import app.models.principia_pay  # noqa: F401
import app.models.school  # noqa: F401
import app.models.trip_authorization  # noqa: F401
import app.models.user  # noqa: F401
import app.models.website  # noqa: F401

from app.core.database import AsyncSessionLocal
from app.models.academic import Enrollment, Schedule, SchoolYear, Turma
from app.models.billing import (
    BillingRun,
    ExtracurricularModality,
    SchoolFeePolicy,
    StudentFinanceProfile,
    StudentModalityEnrollment,
    StudentTransportAssignment,
    TransportRoute,
)
from app.models.finance import BillingItem, BillingItemPrice
from app.models.person import Child, ChildGuardian, Guardian
from app.models.school import School


def money(value):
    return None if value is None else str(value)


async def main(slug: str) -> int:
    async with AsyncSessionLocal() as db:
        school = (
            await db.execute(select(School).where(School.slug == slug))
        ).scalar_one_or_none()
        if school is None:
            print(json.dumps({"error": f"school {slug!r} not found"}))
            return 3

        years = (
            await db.execute(
                select(SchoolYear)
                .where(SchoolYear.school_id == school.id)
                .order_by(SchoolYear.start_date.desc())
            )
        ).scalars().all()
        year = next((y for y in years if y.is_active), years[0] if years else None)

        policy = None
        if year is not None:
            policy = (
                await db.execute(
                    select(SchoolFeePolicy).where(
                        SchoolFeePolicy.school_id == school.id,
                        SchoolFeePolicy.school_year_id == year.id,
                    )
                )
            ).scalar_one_or_none()

        items = (
            await db.execute(
                select(BillingItem)
                .where(BillingItem.school_id == school.id)
                .order_by(BillingItem.code)
            )
        ).scalars().all()
        prices = []
        if year is not None:
            prices = (
                await db.execute(
                    select(BillingItemPrice).where(
                        BillingItemPrice.school_id == school.id,
                        BillingItemPrice.school_year_id == year.id,
                    )
                )
            ).scalars().all()

        students = []
        if year is not None:
            rows = (
                await db.execute(
                    select(Enrollment, Child, Turma)
                    .join(Child, Child.id == Enrollment.child_id)
                    .join(Schedule, Schedule.id == Enrollment.schedule_id)
                    .join(Turma, Turma.id == Schedule.turma_id)
                    .where(
                        Enrollment.school_id == school.id,
                        Enrollment.school_year_id == year.id,
                        Enrollment.status == "active",
                    )
                    .order_by(Turma.level, Child.first_name, Child.last_name)
                )
            ).all()
            profiles = {
                profile.child_id: profile
                for profile in (
                    await db.execute(
                        select(StudentFinanceProfile).where(
                            StudentFinanceProfile.school_id == school.id,
                            StudentFinanceProfile.school_year_id == year.id,
                        )
                    )
                ).scalars().all()
            }
            links = {
                link.child_id: link
                for link in (
                    await db.execute(
                        select(ChildGuardian)
                        .where(ChildGuardian.school_id == school.id)
                        .order_by(
                            ChildGuardian.is_primary_contact.desc(),
                            ChildGuardian.id,
                        )
                    )
                ).scalars().all()
            }
            guardian_names = {
                guardian.id: f"{guardian.first_name} {guardian.last_name}"
                for guardian in (
                    await db.execute(
                        select(Guardian).where(
                            Guardian.school_id == school.id
                        )
                    )
                ).scalars().all()
            }
            for enrollment, child, turma in rows:
                profile = profiles.get(child.id)
                link = links.get(child.id)
                students.append(
                    {
                        "child_id": str(child.id),
                        "child_name": f"{child.first_name} {child.last_name}",
                        "turma": turma.name,
                        "level": turma.level,
                        "guardian": (
                            guardian_names.get(link.guardian_id) if link else None
                        ),
                        "profile_status": profile.status if profile else None,
                        "profile_item": (
                            str(profile.tuition_billing_item_id)
                            if profile and profile.tuition_billing_item_id
                            else None
                        ),
                        "profile_override": money(
                            profile.tuition_override if profile else None
                        ),
                    }
                )

        modalities = (
            await db.execute(
                select(ExtracurricularModality)
                .where(ExtracurricularModality.school_id == school.id)
                .order_by(ExtracurricularModality.name)
            )
        ).scalars().all()
        modality_enrollments = (
            await db.execute(
                select(StudentModalityEnrollment).where(
                    StudentModalityEnrollment.school_id == school.id,
                    StudentModalityEnrollment.status == "active",
                )
            )
        ).scalars().all()
        routes = (
            await db.execute(
                select(TransportRoute)
                .where(TransportRoute.school_id == school.id)
                .order_by(TransportRoute.name)
            )
        ).scalars().all()
        transport_assignments = (
            await db.execute(
                select(StudentTransportAssignment).where(
                    StudentTransportAssignment.school_id == school.id,
                    StudentTransportAssignment.status == "active",
                )
            )
        ).scalars().all()
        runs = (
            await db.execute(
                select(BillingRun)
                .where(BillingRun.school_id == school.id)
                .order_by(BillingRun.created_at.desc())
                .limit(5)
            )
        ).scalars().all()

        print(json.dumps(
            {
                "school": {
                    "id": str(school.id),
                    "name": school.name,
                    "slug": school.slug,
                    "segment": getattr(school, "segment", None),
                },
                "school_year": (
                    {
                        "id": str(year.id),
                        "label": year.year_label,
                        "start": year.start_date.isoformat(),
                        "end": year.end_date.isoformat(),
                        "active": year.is_active,
                    }
                    if year is not None
                    else None
                ),
                "policy": (
                    {
                        "id": str(policy.id),
                        "default_tuition_billing_item_id": (
                            str(policy.default_tuition_billing_item_id)
                            if policy.default_tuition_billing_item_id
                            else None
                        ),
                        "default_enrollment_fee": money(policy.default_enrollment_fee),
                        "sibling_discount_pct": str(policy.sibling_discount_pct),
                        "due_days": policy.due_days,
                        "billing_day": policy.billing_day,
                        "proration_policy": policy.proration_policy,
                        "late_fee_enabled": policy.late_fee_enabled,
                        "late_fee_bands": policy.late_fee_bands,
                        "dunning_enabled": policy.dunning_enabled,
                    }
                    if policy is not None
                    else None
                ),
                "billing_items": [
                    {
                        "id": str(item.id),
                        "code": item.code,
                        "name": item.name,
                        "unit_price": money(item.unit_price),
                        "iva_rate": money(item.iva_rate),
                        "tax_option_code": item.finreg_tax_option_code,
                        "exemption_reason": item.iva_exemption_reason,
                        "active": item.is_active,
                    }
                    for item in items
                ],
                "billing_item_prices": [
                    {
                        "billing_item_id": str(price.billing_item_id),
                        "unit_price": money(price.unit_price),
                    }
                    for price in prices
                ],
                "students": students,
                "modalities": [
                    {
                        "id": str(modality.id),
                        "name": modality.name,
                        "monthly_fee": money(modality.monthly_fee),
                        "inscription_fee": money(modality.inscription_fee),
                        "billing_item_id": (
                            str(modality.billing_item_id)
                            if modality.billing_item_id
                            else None
                        ),
                        "active": modality.is_active,
                    }
                    for modality in modalities
                ],
                "modality_enrollments": len(modality_enrollments),
                "transport_routes": [
                    {
                        "id": str(route.id),
                        "name": route.name,
                        "monthly_price": money(route.monthly_price),
                        "billing_item_id": (
                            str(route.billing_item_id)
                            if route.billing_item_id
                            else None
                        ),
                        "active": route.is_active,
                    }
                    for route in routes
                ],
                "transport_assignments": len(transport_assignments),
                "billing_runs": [
                    {
                        "id": str(run.id),
                        "month": run.billing_month,
                        "status": run.status,
                        "stats": run.stats,
                    }
                    for run in runs
                ],
            },
            ensure_ascii=False,
            indent=2,
            default=str,
        ))
    return 0


sys.exit(asyncio.run(main(sys.argv[1])))
PY
