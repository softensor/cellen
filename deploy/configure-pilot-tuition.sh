#!/usr/bin/env bash
# Create/repair the pilot school's fee policy and preview the current month.
#
# This links the school's own tuition service as the policy default, so the
# composer has a tuition line for every enrolled student. It then prints the
# exact composition (prices, sibling discounts, taxes) and exits WITHOUT
# issuing any document. Generation stays a separate, reviewed step.
#
# Idempotent: re-running keeps the same policy row and the same item.
set -uo pipefail

CELLEN_DIR=${CELLEN_DIR:-/var/www/cellen}
SCHOOL_SLUG=${SCHOOL_SLUG:-rainha-njinga}
TUITION_ITEM_CODE=${TUITION_ITEM_CODE:-DEMO-RNJ-1}
BILLING_MONTH=${BILLING_MONTH:-}

[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
[[ -f $CELLEN_DIR/.env ]] || { echo "missing $CELLEN_DIR/.env" >&2; exit 2; }

cd "$CELLEN_DIR" || exit 2
set -a
# shellcheck disable=SC1091
source "$CELLEN_DIR/.env"
set +a
export PYTHONPATH="$CELLEN_DIR"
export PYTHONDONTWRITEBYTECODE=1

"$CELLEN_DIR/.venv/bin/python" - "$SCHOOL_SLUG" "$TUITION_ITEM_CODE" "$BILLING_MONTH" <<'PY'
import asyncio
import json
import sys
from decimal import Decimal

from sqlalchemy import select

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
from app.models.billing import SchoolFeePolicy
from app.models.finance import BillingItem
from app.models.finreg_integration import FinregBillingInstruction
from app.models.school import School
from app.services.billing_profiles import get_fee_policy, get_school_year
from app.services.billing_run import BillingError, preview_billing


def policy_view(policy):
    if policy is None:
        return None
    return {
        "id": str(policy.id),
        "default_tuition_billing_item_id": (
            str(policy.default_tuition_billing_item_id)
            if policy.default_tuition_billing_item_id
            else None
        ),
        "default_enrollment_fee": str(policy.default_enrollment_fee),
        "sibling_discount_pct": str(policy.sibling_discount_pct),
        "sibling_discount_min_children": policy.sibling_discount_min_children,
        "sibling_discount_scope": policy.sibling_discount_scope,
        "due_days": policy.due_days,
        "billing_day": policy.billing_day,
        "proration_policy": policy.proration_policy,
        "late_fee_enabled": policy.late_fee_enabled,
        "dunning_enabled": policy.dunning_enabled,
    }


async def main(slug: str, item_code: str, month: str) -> int:
    async with AsyncSessionLocal() as db:
        school = (
            await db.execute(select(School).where(School.slug == slug))
        ).scalar_one_or_none()
        if school is None:
            print(f"school {slug!r} not found")
            return 3
        year = await get_school_year(db, school.id)
        if year is None:
            print("no school year configured")
            return 3

        all_items = (
            await db.execute(
                select(BillingItem)
                .where(BillingItem.school_id == school.id)
                .order_by(BillingItem.code)
            )
        ).scalars().all()
        by_id = {item.id: item for item in all_items}
        item = next(
            (candidate for candidate in all_items if candidate.code == item_code),
            None,
        )
        if item is None:
            print(f"billing item {item_code!r} not found; catalog:")
            for candidate in all_items:
                print(
                    f"  {candidate.code:12} {candidate.name:35} "
                    f"{candidate.unit_price} IVA {candidate.iva_rate}% "
                    f"{candidate.finreg_tax_option_code or '-'} "
                    f"{'active' if candidate.is_active else 'INACTIVE'}"
                )
            return 3
        if not item.is_active:
            print(f"billing item {item_code!r} is inactive; refusing to use it")
            return 3
        if not item.finreg_tax_option_code:
            print(
                f"billing item {item_code!r} has no fiscal treatment "
                "(finreg_tax_option_code); refusing to use it"
            )
            return 3

        print(
            f"school={slug} id={school.id} segment={school.segment!r} "
            f"year={year.year_label} ({year.start_date} .. {year.end_date})"
        )
        print(
            f"tuition item: {item.code} | {item.name} | "
            f"{item.unit_price} Kz | IVA {item.iva_rate}% | "
            f"tax_option={item.finreg_tax_option_code} | "
            f"exemption={item.iva_exemption_reason or '-'}"
        )

        print("\n== Evidence: existing billing instructions ==")
        instructions = (
            await db.execute(
                select(FinregBillingInstruction)
                .where(FinregBillingInstruction.school_id == school.id)
                .order_by(FinregBillingInstruction.created_at.desc())
                .limit(20)
            )
        ).scalars().all()
        if not instructions:
            print("none")
        for instruction in instructions:
            plan = (instruction.payload or {}).get("plan") or {}
            lines = []
            for line in plan.get("lines") or []:
                product = by_id.get(line.get("product_external_id"))
                label = (
                    f"{product.code} {product.name}"
                    if product is not None
                    else str(line.get("product_external_id"))
                )
                lines.append(
                    f"{label} x{line.get('quantity')} @ {line.get('unit_price')} "
                    f"IVA {line.get('tax_rate')}% {line.get('tax_option_code') or '-'}"
                )
            print(
                f"- {instruction.created_at} | {instruction.status} | "
                f"{instruction.command_type} | {instruction.idempotency_key}"
            )
            for line in lines:
                print(f"    {line}")

        before = await get_fee_policy(db, school.id, year.id)
        print("\n== Fee policy ==")
        print("before:", json.dumps(policy_view(before), ensure_ascii=False))

        if before is None:
            policy = SchoolFeePolicy(
                school_id=school.id,
                school_year_id=year.id,
                default_tuition_billing_item_id=item.id,
                default_enrollment_fee=None,
                sibling_discount_pct=Decimal("5.00"),
                sibling_discount_min_children=2,
                sibling_discount_scope="additional_children",
                due_days=5,
                billing_day=1,
                auto_generate=False,
                proration_policy="pro_rata_days",
                late_fee_enabled=False,
                late_fee_billing_item_id=None,
                late_fee_base="outstanding",
                late_fee_bands=[],
                dunning_enabled=False,
                dunning_schedule=[],
                dunning_message_template=None,
            )
            db.add(policy)
            action = "created"
        else:
            policy = before
            policy.default_tuition_billing_item_id = item.id
            action = "updated"
        await db.commit()
        await db.refresh(policy)
        print(f"after ({action}):", json.dumps(policy_view(policy), ensure_ascii=False))

        print("\n== October preview (NOTHING ISSUED) ==")
        try:
            preview = await preview_billing(
                db,
                school_id=school.id,
                billing_month=month or None,
            )
        except BillingError as exc:
            print(f"preview failed: {exc.code}: {exc.detail}")
            return 5

        print(
            f"month={preview['billing_month']} mode={preview['mode']} "
            f"run_date={preview['run_date']} due_date={preview['due_date']} "
            f"students={len(preview['students'])}"
        )
        print("totals:", json.dumps(preview["totals"], ensure_ascii=False))

        for student in preview["students"]:
            flags = []
            if student["sibling_discount_applied"]:
                flags.append(
                    f"sibling {student['sibling_index']}/{student['family_size']}"
                )
            else:
                flags.append(f"family {student['family_size']}")
            print(
                f"\n- {student['child_name']} / {student['guardian_name']} "
                f"[{', '.join(flags)}] total={student['total']:.2f} "
                f"discount={student['discount_total']:.2f} "
                f"iva={student['iva_total']:.2f}"
            )
            for line in student["lines"]:
                print(
                    f"    {line['description']} x{line['quantity']} "
                    f"@ {line['unit_price']:.2f} "
                    f"IVA {line['tax_rate']:.2f}% {line['tax_option_code'] or '-'} "
                    f"exemption={line['exemption_reason'] or '-'} "
                    f"discount={line['discount_amount']:.2f} "
                    f"net={line['line_net']:.2f} iva={line['iva_amount']:.2f} "
                    f"total={line['line_total']:.2f}"
                )
            if student["warnings"]:
                print(f"    warnings: {student['warnings']}")

        print("\nunbilled:", json.dumps(preview.get("unbilled"), ensure_ascii=False))
        print("warnings:", json.dumps(preview.get("warnings"), ensure_ascii=False))
        blockers = preview.get("blockers") or []
        print("blockers:", json.dumps(blockers, ensure_ascii=False))
        if preview.get("existing_run"):
            print(
                "existing run:",
                json.dumps(preview["existing_run"], ensure_ascii=False, default=str),
            )

        if blockers:
            print("\nSTOPPING: the preview reports blockers; nothing was issued.")
            return 6

        print(
            "\nNOTHING WAS ISSUED. Review the amounts above; generation is the "
            "separate next step."
        )
        return 0


sys.exit(asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3])))
PY
