#!/usr/bin/env python3
"""Repair FinReg outbox instructions stranded in "processing".

Monthly billing runs and plan upserts built their payload without the
``products`` list, so the HTTP dispatcher raised ``KeyError`` while resolving
each plan line's fiscal product, before creating any document. Because an
unexpected exception never reset the row, the instruction stayed in
``processing`` forever: the dispatcher only selects ``pending`` rows, and
parents therefore saw nothing to pay.

This script rebuilds the missing ``products`` from the school's current
billing items and returns the row to the outbox. Run against the deployed
database:

    cd /var/www/cellen && PYTHONPATH=. .venv/bin/python \
        deploy/repair_stuck_finreg_instructions.py --school-slug rainha-njinga

Dry run by default. ``--apply`` writes the repair; it is idempotent.
"""
from __future__ import annotations

import argparse
import asyncio
import importlib
import pkgutil
import sys
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

import app.models

# app.models.__init__ is empty; importing every module registers every table
# and resolves the string-based relationships before any query runs.
for _module in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module(f"app.models.{_module.name}")

from app.models.finance import BillingItem
from app.models.finreg_integration import FinregBillingInstruction
from app.models.school import School
from app.services.billing_run import _product_data

TARGET_COMMANDS = {"billing_run", "billing_plan_upsert"}


def _line_product_ids(payload: dict) -> list[str]:
    plan = payload.get("plan") or {}
    lines = ((plan.get("template") or {}).get("lines")) or []
    return [
        str(line["product_external_id"])
        for line in lines
        if line.get("product_external_id")
    ]


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--school-slug", default="rainha-njinga")
    parser.add_argument("--dsn", default=None)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    dsn = args.dsn
    if dsn is None:
        from app.core.config import settings

        dsn = settings.DATABASE_URL

    engine = create_async_engine(dsn)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with sessions() as session:
            school = (
                await session.execute(
                    select(School.id, School.name).where(
                        School.slug == args.school_slug
                    )
                )
            ).first()
            if school is None:
                print(f"School '{args.school_slug}' not found.", file=sys.stderr)
                sys.exit(2)
            school_id, school_name = school
            rows = list(
                (
                    await session.execute(
                        select(FinregBillingInstruction)
                        .where(
                            FinregBillingInstruction.school_id == school_id,
                            FinregBillingInstruction.command_type.in_(TARGET_COMMANDS),
                            FinregBillingInstruction.status == "processing",
                        )
                        .order_by(FinregBillingInstruction.created_at)
                    )
                ).scalars().all()
            )

            print(f"School: {school_name} ({school_id})")
            print(f"Mode:   {'APPLY' if args.apply else 'dry run'}")
            print(f"Instructions in processing: {len(rows)}")
            print()

            repaired = 0
            rejected = 0
            already = 0
            for instruction in rows:
                payload = dict(instruction.payload or {})
                if payload.get("products"):
                    already += 1
                    continue
                product_ids = _line_product_ids(payload)
                items = {}
                if product_ids:
                    items = {
                        str(item.id): item
                        for item in (
                            await session.execute(
                                select(BillingItem).where(
                                    BillingItem.school_id == instruction.school_id,
                                    BillingItem.id.in_(
                                        [UUID(value) for value in product_ids]
                                    ),
                                )
                            )
                        ).scalars().all()
                    }
                missing = [value for value in product_ids if value not in items]
                if missing or not product_ids:
                    instruction.status = "rejected"
                    instruction.error_code = "product_not_declared"
                    instruction.error_detail = (
                        "Run gerado sem produtos fiscais; volte a gerar o mês."
                    )
                    instruction.next_attempt_at = None
                    rejected += 1
                    print(
                        f"  reject  {instruction.id} {instruction.command_type} "
                        f"({len(missing)} produto(s) em falta)"
                    )
                    continue
                payload["products"] = [
                    {"external_id": external_id, "data": _product_data(item)}
                    for external_id, item in items.items()
                ]
                instruction.payload = payload
                instruction.status = "pending"
                instruction.attempts = 0
                instruction.error_code = None
                instruction.error_detail = None
                instruction.next_attempt_at = None
                repaired += 1
                print(
                    f"  repair  {instruction.id} {instruction.command_type} "
                    f"({len(items)} produto(s))"
                )

            print()
            print(
                f"repaired={repaired} rejected={rejected} "
                f"already-with-products={already}"
            )
            if not args.apply:
                print("Dry run only. Re-run with --apply to write the repair.")
                await session.rollback()
                return
            await session.commit()
            print("Repair committed; the dispatcher picks these up on its next pass.")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
