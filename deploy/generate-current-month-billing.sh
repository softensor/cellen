#!/usr/bin/env bash
# Cellen school-finance acceptance helper.
#
# Issues the pilot school's current month through the product's own billing
# service, then rebuilds the student plans and prints the resulting FinReg
# plan state. This is the command-line equivalent of:
#
#   /admin/finance/billing-run -> "Gerar dívidas do mês"
#   -> "Reconstruir planos dos alunos"
#
# It calls the same service functions the API routes call, so the composition,
# taxes, sibling discounts and FinReg dispatch are exactly the product's.
#
# Safe by construction: it previews first and aborts without issuing anything
# when the month has no billable students or the preview reports blockers.
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

# SQLAlchemy resolves string relationships lazily; the app's unit tests import
# every model module for the same reason. Importing only School lets the first
# query fail while configuring Mapper[ScheduleSlot] ('Subject' not found).
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
from app.models.school import School
from app.services.billing_profiles import get_school_year
from app.services.billing_run import (
    BillingError,
    current_billing_month,
    preview_billing,
    rebuild_plans,
    run_billing,
    serialize_run,
)
from app.services.finreg import HttpFinregAdapter
from app.services.finreg_dispatch import integration_mode


def dump(label: str, value) -> None:
    print(f"\n== {label} ==")
    print(json.dumps(value, ensure_ascii=False, indent=2, default=str))


async def main(slug: str) -> int:
    month = current_billing_month()
    async with AsyncSessionLocal() as db:
        school = (
            await db.execute(select(School).where(School.slug == slug))
        ).scalar_one_or_none()
        if school is None:
            print(f"school {slug!r} not found")
            return 3
        mode = await integration_mode(db, school.id)
        year = await get_school_year(db, school.id)
        print(
            f"school={slug} id={school.id} mode={mode!r} month={month} "
            f"school_year={getattr(year, 'year_label', None)!r} "
            f"({getattr(year, 'start_date', None)} .. {getattr(year, 'end_date', None)})"
        )
        if mode != "pilot":
            print(f"abort: expected pilot integration mode, found {mode!r}")
            return 4

        try:
            preview = await preview_billing(
                db, school_id=school.id, billing_month=month
            )
        except BillingError as exc:
            print(f"preview failed: {exc.code}: {exc.detail}")
            return 5

        students = preview.get("students") or []
        blockers = preview.get("blockers") or []
        print(
            f"preview: run_date={preview.get('run_date')} "
            f"due_date={preview.get('due_date')} students={len(students)} "
            f"blockers={len(blockers)} unbilled={len(preview.get('unbilled') or [])}"
        )
        print("totals:", json.dumps(preview.get("totals") or {}, ensure_ascii=False, default=str))
        for student in students[:12]:
            print(
                f"  - {student.get('child_name')} / {student.get('guardian_name')}: "
                f"{len(student.get('lines') or [])} lines, total={student.get('total')}"
                + (
                    f", sibling_discount={student.get('discount_total')}"
                    if student.get("sibling_discount_applied")
                    else ""
                )
            )
        if len(students) > 12:
            print(f"  ... {len(students) - 12} more")
        existing = preview.get("existing_run")
        if existing:
            print("existing run:", json.dumps(existing, ensure_ascii=False, default=str))
        if blockers:
            print("abort: the preview reports blockers; nothing was issued")
            dump("blockers", blockers)
            return 6
        if not students:
            print("abort: no billable students; nothing was issued")
            return 6

        adapter = HttpFinregAdapter()
        print("\n== issuing the month (same code path as 'Gerar dívidas do mês') ==")
        run, created = await run_billing(
            db, school_id=school.id, billing_month=month, adapter=adapter
        )
        print(f"created={created}")
        dump("billing run", serialize_run(run))
        stats = run.stats or {}
        failed = int(stats.get("failed") or 0)
        if failed:
            dump("generation failures", stats.get("failures") or [])

        print("\n== rebuilding student plans (same code path as 'Reconstruir planos') ==")
        result = await rebuild_plans(
            db, school_id=school.id, billing_month=month, adapter=adapter
        )
        dump("rebuild", result)
        rebuild_failed = int(result.get("failed") or 0)

        if run.status != "completed" or failed or rebuild_failed:
            print(
                f"\nresult: run.status={run.status} generation_failures={failed} "
                f"rebuild_failures={rebuild_failed}"
            )
            return 7
        return 0


sys.exit(asyncio.run(main(sys.argv[1])))
PY
status=$?

echo
echo '== FinReg plan state (latest plan for the linked company) =='
company_id=$(sudo -u postgres psql -X -A -t -d cellen -c \
  "SELECT fc.finreg_company_id FROM finreg_school_connections fc JOIN schools s ON s.id = fc.school_id WHERE s.slug = '$SCHOOL_SLUG';" \
  2>/dev/null | tr -d '[:space:]')
if [[ -z $company_id ]]; then
  echo 'could not resolve the linked FinReg company'
  [[ $status -eq 0 ]] && status=8
else
  plan_row=$(sudo -u postgres psql -X -A -t -d finreg -c \
    "SELECT id || ' | ' || frequency || '/' || interval_count || ' | due=' || due_days || ' | next=' || next_run_date || ' | mode=' || generation_mode || ' | active=' || is_active || ' | docs=' || (SELECT count(*) FROM documents d WHERE d.recurring_template_id = t.id) FROM recurring_invoice_templates t WHERE company_id = '$company_id' ORDER BY created_at DESC LIMIT 1;" \
    2>/dev/null)
  echo "${plan_row:-no plan found}"
  docs=${plan_row##*docs=}
  if [[ $plan_row == *active=false* && $docs =~ ^[0-9]+$ ]] && (( docs >= 1 )); then
    echo "OK: the latest plan is paused under Cellen control and has $docs document(s)."
  else
    echo 'ATTENTION: the latest plan is not in the state the acceptance gate expects (paused + at least one document).'
    [[ $status -eq 0 ]] && status=9
  fi
fi

echo
echo '== billing outbox =='
sudo -u postgres psql -X -A -t -d cellen -c \
  "SELECT i.status || ' = ' || count(*) FROM finreg_billing_instructions i JOIN schools s ON s.id = i.school_id WHERE s.slug = '$SCHOOL_SLUG' GROUP BY i.status ORDER BY i.status;" \
  2>/dev/null

exit $status
