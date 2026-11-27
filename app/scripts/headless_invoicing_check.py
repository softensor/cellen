"""Rollout check for headless invoicing, one school or every connected one.

    .venv/bin/python -m app.scripts.headless_invoicing_check
    .venv/bin/python -m app.scripts.headless_invoicing_check --school rainha-njinga
    .venv/bin/python -m app.scripts.headless_invoicing_check --school rainha-njinga --refresh

Without --refresh it makes no FinReg call: it ledgers what the outbox already
confirmed (the same backfill the screens run) and reports, per school, what
the native fiscal screens will show. --refresh also re-reads from FinReg the
documents it may still change, as the dispatcher tick does every 30 seconds.

Exit status 1 when any school has failed operations or AGT rejections, so the
command can gate a rollout step.
"""
from __future__ import annotations

import argparse
import asyncio
import sys

from sqlalchemy import func, select

from app.core.database import AsyncSessionLocal
from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregDocument,
    FinregSchoolConnection,
)
from app.models.school import School
from app.services import finreg_ledger
from app.services.finreg import FinregError, HttpFinregAdapter


async def _report(db, school: School, connection: FinregSchoolConnection | None, refresh: bool) -> dict:
    backfilled = await finreg_ledger.backfill(db, school.id)
    await db.commit()
    refreshed = refresh_failed = 0
    if refresh and connection and connection.mode in {"shadow", "pilot", "live"} and not connection.kill_switch:
        adapter = HttpFinregAdapter()
        rows = (await db.execute(select(FinregDocument).where(
            FinregDocument.school_id == school.id,
            FinregDocument.needs_refresh.is_(True),
        ).limit(200))).scalars().all()
        for row in rows:
            try:
                await finreg_ledger.refresh_document(db, row, adapter=adapter)
                refreshed += 1
            except FinregError:
                refresh_failed += 1
        await db.commit()

    documents = (await db.execute(select(FinregDocument).where(
        FinregDocument.school_id == school.id
    ))).scalars().all()
    from app.routers.finreg_admin import agt_state

    states: dict[str, int] = {}
    for row in documents:
        state = agt_state(row)
        states[state] = states.get(state, 0) + 1
    unledgered = (await db.execute(select(func.count()).select_from(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school.id,
        FinregBillingInstruction.status == "confirmed",
        FinregBillingInstruction.finreg_document_id.is_not(None),
        FinregBillingInstruction.command_type != "billing_plan_upsert",
        FinregBillingInstruction.finreg_document_id.not_in(
            select(FinregDocument.finreg_document_id).where(FinregDocument.school_id == school.id)
        ),
    ))).scalar_one()
    failed = (await db.execute(select(func.count()).select_from(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school.id,
        FinregBillingInstruction.status == "rejected",
        FinregBillingInstruction.command_type != "billing_plan_upsert",
    ))).scalar_one()
    in_flight = (await db.execute(select(func.count()).select_from(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school.id,
        FinregBillingInstruction.status.in_(["pending", "processing", "unknown"]),
    ))).scalar_one()
    return {
        "slug": school.slug,
        "mode": connection.mode if connection else "disabled",
        "kill_switch": bool(connection and connection.kill_switch),
        "documents": len(documents),
        "states": states,
        "backfilled_now": backfilled,
        "unledgered": unledgered,
        "refreshed": refreshed,
        "refresh_failed": refresh_failed,
        "failed_operations": failed,
        "in_flight": in_flight,
    }


def _print(report: dict) -> None:
    states = ", ".join(f"{key}={value}" for key, value in sorted(report["states"].items())) or "none"
    print(f"{report['slug']}: mode={report['mode']}{' KILL-SWITCH' if report['kill_switch'] else ''}")
    print(f"  documents={report['documents']} ({states})")
    print(f"  backfilled_now={report['backfilled_now']} unledgered={report['unledgered']}")
    if report["refreshed"] or report["refresh_failed"]:
        print(f"  refreshed={report['refreshed']} refresh_failed={report['refresh_failed']}")
    print(f"  failed_operations={report['failed_operations']} in_flight={report['in_flight']}")


async def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--school", help="school slug; default: every school with a connection")
    parser.add_argument("--refresh", action="store_true", help="also re-read pending documents from FinReg")
    args = parser.parse_args(argv)
    attention = False
    async with AsyncSessionLocal() as db:
        query = select(School, FinregSchoolConnection).outerjoin(
            FinregSchoolConnection, FinregSchoolConnection.school_id == School.id
        )
        if args.school:
            query = query.where(School.slug == args.school)
        else:
            query = query.where(FinregSchoolConnection.id.is_not(None))
        rows = (await db.execute(query.order_by(School.slug))).all()
        if not rows:
            print("No matching school.")
            return 2
        for school, connection in rows:
            report = await _report(db, school, connection, args.refresh)
            _print(report)
            if report["failed_operations"] or report["states"].get("rejected"):
                attention = True
    return 1 if attention else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
