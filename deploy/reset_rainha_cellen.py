#!/usr/bin/env python3
"""Reset the Rainha Njinga test school in Cellen.

Removes the school's people (guardians, children, parent logins) and every
record tied to them or to its finance history, while keeping the school
itself and its configuration (staff, school years, classes, timetable
skeleton, billing catalogue, fee policy, FinReg/principia-pay connections,
document series).

Dry-run by default: it only counts. With ``--apply --confirm <slug>`` it
deletes in FK-safe order inside one transaction.

Run on the VPS from the deployed checkout, as a user that can reach the
database (the app's own DATABASE_URL is used unless --dsn is given):

    cd /var/www/cellen && PYTHONPATH=. .venv/bin/python \
        deploy/reset_rainha_cellen.py --school-slug rainha-njinga

Take a pg_dump of the cellen database first; this script does not back up.
"""
from __future__ import annotations

import argparse
import asyncio
import importlib
import pkgutil
import sys
from uuid import UUID

from sqlalchemy import delete, func, or_, select, text
from sqlalchemy.ext.asyncio import create_async_engine

import app.models

# app.models.__init__ is empty; importing every module registers every table
# and resolves the string-based relationships before any query runs.
for _module in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{_module.name}")

from app.models.base import Base
from app.models.school import School

DEFAULT_SLUG = "rainha-njinga"
EXPECTED_SCHOOL_ID = UUID("65794af5-2831-4709-9b53-437bb5d50515")

# School configuration that survives the reset.
KEEP_TABLES = {
    "billing_item_prices",
    "billing_items",
    "document_series",
    "employees",
    "expense_categories",
    "extracurricular_modalities",
    "finreg_school_connections",
    "grade_schemes",
    "principia_pay_connections",
    "schedule_teachers",
    "schedules",
    "school_fee_policies",
    "school_years",
    "schools",
    "subjects",
    "timetable_periods",
    "timetable_requirements",
    "timetable_teacher_constraints",
    "transport_routes",
    "turma_subjects",
    "turmas",
}

# Tables with no school_id; scoped through the parent row.
DEPENDENT_TABLES = {
    "invoice_lines": ("invoices", "invoice_id"),
    "payment_allocations": ("payments", "payment_id"),
    "payment_plan_installments": ("payment_plans", "plan_id"),
}


def deletion_order(names: set[str]) -> list[str]:
    """Every table before the tables it references (children first)."""
    parents: dict[str, set[str]] = {name: set() for name in names}
    for name in names:
        for fk in Base.metadata.tables[name].foreign_keys:
            parent = fk.column.table.name
            if parent in names and parent != name:
                parents[name].add(parent)
    remaining = set(names)
    order: list[str] = []
    while remaining:
        candidates = sorted(
            name
            for name in remaining
            if not any(name in parents[other] for other in remaining if other != name)
        )
        if not candidates:
            raise RuntimeError(
                "FK cycle between: " + ", ".join(sorted(remaining))
            )
        order.extend(candidates)
        remaining -= set(candidates)
    return order


def _condition(table, school_id: UUID):
    name = table.name
    if name == "users":
        # Staff and platform accounts survive; parent/student logins do not.
        return (
            (table.c.school_id == school_id)
            & or_(
                table.c.guardian_id.isnot(None),
                table.c.roles.overlap(["parent", "student"]),
            )
        )
    if name in DEPENDENT_TABLES:
        parent_name, column = DEPENDENT_TABLES[name]
        parent = Base.metadata.tables[parent_name]
        return table.c[column].in_(
            select(parent.c.id).where(parent.c.school_id == school_id)
        )
    return table.c.school_id == school_id


def tables_to_clear() -> dict[str, object]:
    tables: dict[str, object] = {}
    for name, table in Base.metadata.tables.items():
        if name in KEEP_TABLES:
            continue
        if "school_id" in table.columns or name in DEPENDENT_TABLES:
            tables[name] = table
    return tables


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--school-slug", default=DEFAULT_SLUG)
    parser.add_argument("--dsn", default=None)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    parser.add_argument(
        "--allow-other-school",
        action="store_true",
        help="permit a slug whose id is not the known Rainha Njinga id",
    )
    args = parser.parse_args()

    if args.apply and args.confirm != args.school_slug:
        print(
            f"Refusing to delete: pass --confirm {args.school_slug} together "
            "with --apply.",
            file=sys.stderr,
        )
        sys.exit(2)

    dsn = args.dsn
    if dsn is None:
        from app.core.config import settings

        dsn = settings.DATABASE_URL

    engine = create_async_engine(dsn)
    tables = tables_to_clear()
    order = deletion_order(set(tables))

    try:
        async with engine.begin() as conn:
            row = (
                await conn.execute(
                    select(School.id, School.name).where(School.slug == args.school_slug)
                )
            ).first()
            if row is None:
                print(f"School '{args.school_slug}' not found.", file=sys.stderr)
                sys.exit(2)
            school_id, school_name = row
            if school_id != EXPECTED_SCHOOL_ID and not args.allow_other_school:
                print(
                    f"School '{args.school_slug}' has id {school_id}, expected "
                    f"{EXPECTED_SCHOOL_ID}. Pass --allow-other-school to proceed.",
                    file=sys.stderr,
                )
                sys.exit(2)

            print(f"School: {school_name} ({school_id})")
            print(f"Mode:   {'APPLY' if args.apply else 'dry run'}")
            print(f"Tables to clear: {len(tables)}")
            print()

            print("-- configuration kept (what the next billing run will use)")
            policy_rows = (
                await conn.execute(
                    text(
                        "select bi.code as tuition_item, bi.unit_price as tuition_price, "
                        "bi.iva_rate, bi.finreg_tax_option_code, "
                        "p.sibling_discount_pct, p.due_days, p.billing_day, "
                        "p.proration_policy "
                        "from public.school_fee_policies p "
                        "left join public.billing_items bi "
                        "on bi.id = p.default_tuition_billing_item_id "
                        "where p.school_id = :sid"
                    ),
                    {"sid": school_id},
                )
            ).mappings().all()
            if not policy_rows:
                print("  fee policy: NONE — configure it before generating debts")
            for row in policy_rows:
                print(
                    "  fee policy: tuition item {tuition_item} ({tuition_price}), "
                    "IVA {iva_rate}%, tax option {finreg_tax_option_code}, "
                    "sibling {sibling_discount_pct}%, due {due_days}d, "
                    "billing day {billing_day}, {proration_policy}".format(**row)
                )
            item_rows = (
                await conn.execute(
                    text(
                        "select bi.code, bi.name, bi.unit_price, bi.iva_rate, "
                        "bi.finreg_tax_option_code, bip.unit_price as year_price "
                        "from public.billing_items bi "
                        "left join public.billing_item_prices bip "
                        "on bip.billing_item_id = bi.id "
                        "and bip.school_year_id = ("
                        "  select id from public.school_years "
                        "  where school_id = :sid and is_active "
                        "  order by start_date desc limit 1) "
                        "where bi.school_id = :sid and bi.is_active "
                        "order by bi.code"
                    ),
                    {"sid": school_id},
                )
            ).mappings().all()
            for row in item_rows:
                print(
                    "  item: {code} | {name} | {unit_price} | IVA {iva_rate}% | "
                    "tax option {finreg_tax_option_code} | year price {year_price}".format(**row)
                )
            print()

            total = 0
            counts: dict[str, int] = {}
            for name in order:
                table = tables[name]
                count = (
                    await conn.execute(
                        select(func.count()).select_from(table).where(
                            _condition(table, school_id)
                        )
                    )
                ).scalar_one()
                counts[name] = count
                total += count
            width = max(len(name) for name in order)
            for name in order:
                if counts[name]:
                    print(f"  {name:<{width}}  {counts[name]}")
            print(f"  {'TOTAL':<{width}}  {total}")
            print()

            if not args.apply:
                print("Dry run only. Re-run with --apply --confirm", args.school_slug)
                return

            deleted_total = 0
            for name in order:
                if not counts[name]:
                    continue
                result = await conn.execute(
                    delete(tables[name]).where(_condition(tables[name], school_id))
                )
                print(f"  deleted {name}: {result.rowcount}")
                deleted_total += result.rowcount or 0
            print(f"Deleted {deleted_total} row(s).")

            # Prove the people are gone and the school configuration is not.
            remaining = {}
            for name in ("guardians", "children", "child_guardians", "users"):
                table = Base.metadata.tables[name]
                remaining[name] = (
                    await conn.execute(
                        select(func.count()).select_from(table).where(
                            _condition(table, school_id)
                        )
                    )
                ).scalar_one()
            school_still_there = (
                await conn.execute(select(func.count()).select_from(School).where(School.id == school_id))
            ).scalar_one()
            print(f"Remaining people rows: {remaining}")
            print(f"School row still present: {school_still_there == 1}")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
