"""Scheduled background tasks.

Runs daily at midnight (Luanda time) to:
- Mark overdue invoices
- Expire stale payment references
- Breach overdue payment plans
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from app.core.database import AsyncSessionLocal

logger = logging.getLogger(__name__)

# Luanda is UTC+1
_LUANDA_TZ = timezone(timedelta(hours=1))


def _seconds_until_midnight_luanda() -> float:
    """Seconds until the next midnight in Africa/Luanda (UTC+1)."""
    now = datetime.now(_LUANDA_TZ)
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=5, second=0, microsecond=0)
    return (tomorrow - now).total_seconds()


async def _daily_overdue_sweep():
    """Mark invoices as overdue across all active schools and notify parents."""
    from sqlalchemy import select

    from app.models.finance import Invoice
    from app.models.school import School
    from app.services.finance import mark_overdue_invoices
    from app.services.notifications import notify_parents_of_child

    async with AsyncSessionLocal() as db:
        try:
            result = await db.execute(
                select(School.id).where(School.is_active.is_(True))
            )
            school_ids = [row[0] for row in result.all()]

            total = 0
            for sid in school_ids:
                # Find invoices that will become overdue (before marking)
                from app.utils.agt import today_luanda
                today = today_luanda()
                newly_overdue = await db.execute(
                    select(Invoice).where(
                        Invoice.school_id == sid,
                        Invoice.status.in_(["pending", "partially_paid"]),
                        Invoice.due_date < today,
                    )
                )
                overdue_invoices = newly_overdue.scalars().all()

                # Notify parents for each newly overdue invoice
                for inv in overdue_invoices:
                    if inv.child_id:
                        await notify_parents_of_child(
                            db, sid, inv.child_id,
                            notif_type="invoice_overdue",
                            title="Factura em Atraso",
                            body=f"A factura {inv.full_document_number or ''} encontra-se em atraso.",
                            related_id=inv.id,
                            related_type="invoice",
                        )

                count = await mark_overdue_invoices(db, sid)
                total += count
            await db.commit()

            if total:
                logger.info("Overdue sweep: marked %d invoices across %d schools", total, len(school_ids))
        except Exception:
            logger.exception("Error in daily overdue sweep")


async def _daily_expire_payment_references():
    """Expire payment references past their expiry date."""
    from sqlalchemy import update

    from app.models.finance import PaymentReference
    from app.utils.agt import now_luanda

    async with AsyncSessionLocal() as db:
        try:
            now = now_luanda()
            result = await db.execute(
                update(PaymentReference)
                .where(
                    PaymentReference.status == "active",
                    PaymentReference.expires_at < now,
                )
                .values(status="expired")
            )
            if result.rowcount:
                await db.commit()
                logger.info("Expired %d payment references", result.rowcount)
        except Exception:
            logger.exception("Error expiring payment references")


async def _daily_breach_payment_plans():
    """Breach payment plans with overdue installments."""
    from sqlalchemy import select

    from app.models.finance import PaymentPlan, PaymentPlanInstallment
    from app.utils.agt import today_luanda

    async with AsyncSessionLocal() as db:
        try:
            today = today_luanda()
            # Find active plans with at least one overdue pending installment
            result = await db.execute(
                select(PaymentPlan.id).where(PaymentPlan.status == "active")
            )
            plan_ids = [row[0] for row in result.all()]

            breached = 0
            for plan_id in plan_ids:
                overdue = await db.execute(
                    select(PaymentPlanInstallment).where(
                        PaymentPlanInstallment.plan_id == plan_id,
                        PaymentPlanInstallment.status == "pending",
                        PaymentPlanInstallment.due_date < today,
                    )
                )
                missed = overdue.scalars().all()
                if missed:
                    # Mark missed installments
                    for inst in missed:
                        inst.status = "missed"
                    # Breach the plan
                    plan_result = await db.execute(
                        select(PaymentPlan).where(PaymentPlan.id == plan_id)
                    )
                    plan = plan_result.scalar_one_or_none()
                    if plan:
                        plan.status = "breached"
                        breached += 1

            if breached:
                await db.commit()
                logger.info("Breached %d payment plans with overdue installments", breached)
        except Exception:
            logger.exception("Error breaching payment plans")


async def run_scheduled_tasks():
    """Main loop: wait until midnight Luanda, then run daily tasks."""
    while True:
        wait = _seconds_until_midnight_luanda()
        logger.info("Scheduled tasks: sleeping %.0f seconds until next run", wait)
        await asyncio.sleep(wait)

        logger.info("Running daily scheduled tasks")
        await _daily_overdue_sweep()
        await _daily_expire_payment_references()
        await _daily_breach_payment_plans()


async def run_finreg_dispatcher():
    """Continuously drain the transactional Finreg outbox with safe retries."""
    from app.services.finreg_dispatch import dispatch_pending
    from app.services.finreg_events import synchronize_enabled_connections

    while True:
        async with AsyncSessionLocal() as db:
            try:
                confirmed, failed = await dispatch_pending(db)
                events, sync_failed = await synchronize_enabled_connections(db)
                if confirmed or failed:
                    logger.info("Finreg outbox: confirmed=%d failed=%d", confirmed, failed)
                if events or sync_failed:
                    logger.info("Finreg events: processed=%d failed=%d", events, sync_failed)
            except Exception:
                logger.exception("Finreg outbox dispatch failed")
        await asyncio.sleep(30)
