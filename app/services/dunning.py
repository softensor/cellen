"""Policy-driven guardian reminders (cobrança amigável).

A school defines its own ladder -- level, days after the due date, channels,
optional wording -- in ``school_fee_policies.dunning_schedule``. This service
turns the ladder into deliveries:

* a step fires once its trigger date (``due_date + offset_days``) has
  passed and the document is still open;
* when several steps are already due (first run on an old debt), only the
  latest one is sent; the earlier ones are recorded as ``skipped`` so they
  can never fire later;
* each (document, offset, channel) is unique in the database, so a re-run
  -- or a retried crash -- never sends the same reminder twice;
* a failed delivery is retried on the next run by updating its row, not by
  inserting a new one.

Channels are best-effort by nature. A channel the school has not
configured is recorded as ``skipped`` with the reason, never as failed,
so the delivery log tells the director what to enable.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.academic import SchoolYear
from app.models.billing import DunningDelivery, SchoolFeePolicy
from app.models.modern import Notification
from app.models.person import Guardian
from app.models.school import School
from app.services.billing_profiles import get_fee_policy, get_school_year
from app.services.billing_run import BillingError
from app.services.debt_control import list_debts
from app.services.email import EmailDeliveryError, send_email
from app.services.notifications import _get_parent_user_ids_for_child
from app.services.whatsapp import send_whatsapp
from app.utils.agt import now_luanda, today_luanda

logger = logging.getLogger(__name__)

CHANNELS = ("email", "sms", "whatsapp", "in_app")
DEFAULT_TEMPLATE = (
    "Caro(a) {guardian_name}, a factura {document_number} de {student_name} "
    "no valor de {amount} AOA venceu em {due_date} "
    "(há {days_overdue} dias). Por favor regularize."
)
SOURCE_KINDS = {"finreg": "finreg_document", "internal": "internal_invoice"}


def _empty_result(reference: date, reason: str) -> dict:
    return {
        "as_of": reference.isoformat(),
        "enabled": False,
        "reason": reason,
        "steps": 0,
        "planned": [],
        "sent": 0,
        "failed": 0,
        "skipped": 0,
    }


def _as_date(value) -> Optional[date]:
    if isinstance(value, date):
        return value
    if not value:
        return None
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _fmt_amount(value) -> str:
    amount = Decimal(str(value or 0))
    whole = f"{amount:,.2f}"
    return whole.replace(",", " ")


def _step_offset(step: dict) -> int:
    try:
        return int(step.get("offset_days") or 0)
    except (TypeError, ValueError):
        return 0


def _step_channels(step: dict) -> list[str]:
    channels = step.get("channels") or ["email"]
    return [channel for channel in channels if channel in CHANNELS]


def render_message(
    template: Optional[str],
    *,
    guardian: Guardian,
    row: dict,
    due: date,
    reference: date,
    school_name: Optional[str],
    step: dict,
) -> str:
    """Fill the school's template without ``str.format``.

    Templates are editable data; a stray brace must never crash a run, so
    known tokens are replaced literally and everything else is left alone.
    """
    values = {
        "guardian_name": f"{guardian.first_name} {guardian.last_name}".strip(),
        "student_name": row.get("student_name") or "—",
        "document_number": row.get("document_number") or "",
        "amount": _fmt_amount(row.get("outstanding")),
        "due_date": due.strftime("%d/%m/%Y"),
        "days_overdue": max((reference - due).days, 0),
        "school_name": school_name or "",
        "level": int(step.get("level") or 0),
        "step_message": step.get("message") or "",
    }
    text = template or DEFAULT_TEMPLATE
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


async def _delivery_row(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    source_kind: str,
    source_id: uuid.UUID,
    offset_days: int,
    channel: str,
) -> Optional[DunningDelivery]:
    return (
        await db.execute(
            select(DunningDelivery).where(
                DunningDelivery.school_id == school_id,
                DunningDelivery.source_kind == source_kind,
                DunningDelivery.source_id == source_id,
                DunningDelivery.offset_days == offset_days,
                DunningDelivery.channel == channel,
            )
        )
    ).scalar_one_or_none()


async def _deliver(
    db: AsyncSession,
    *,
    school: School,
    guardian: Guardian,
    row: dict,
    student_id: Optional[uuid.UUID],
    channel: str,
    message: str,
    subject: str,
) -> tuple[str, Optional[str]]:
    """Send one reminder on one channel; return (status, error)."""
    if channel == "in_app":
        if student_id is None:
            return "skipped", "no_student"
        user_ids = await _get_parent_user_ids_for_child(db, school.id, student_id)
        if not user_ids:
            return "skipped", "no_parent_account"
        document_id = uuid.UUID(str(row["document_id"]))
        for user_id in user_ids:
            db.add(
                Notification(
                    school_id=school.id,
                    user_id=user_id,
                    type="fee_reminder",
                    title=subject,
                    body=message,
                    related_id=document_id,
                    related_type="invoice",
                )
            )
        return "sent", None

    if channel == "email":
        if not guardian.email:
            return "skipped", "no_email"
        try:
            await send_email(to=guardian.email, subject=subject, body=message)
        except EmailDeliveryError:
            return "failed", "email_delivery_failed"
        return "sent", None

    if channel == "whatsapp":
        phone = guardian.mobile_first or guardian.mobile_second
        if not phone:
            return "skipped", "no_phone"
        if not school.wa_enabled:
            return "skipped", "whatsapp_not_configured"
        ok = await send_whatsapp(
            phone,
            f"*{subject}*\n{message}",
            phone_number_id=school.wa_phone_number_id or None,
            access_token=school.wa_access_token or None,
        )
        return ("sent", None) if ok else ("failed", "whatsapp_delivery_failed")

    if channel == "sms":
        # No SMS provider is wired; the schedule can name it and the log
        # will say exactly why nothing went out.
        return "skipped", "sms_not_configured"

    return "skipped", "unknown_channel"


async def run_dunning(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    as_of: Optional[date] = None,
    dry_run: bool = False,
    dispatch: bool = True,
    adapter=None,
) -> dict:
    """Walk the school's ladder over every open document.

    ``dry_run``/``dispatch=False`` compute what would be sent without
    writing anything -- the preview the director reviews before enabling
    the schedule.
    """
    reference = as_of or today_luanda()
    year = await get_school_year(db, school_id)
    if year is None:
        return _empty_result(reference, "no_school_year")
    policy = await get_fee_policy(db, school_id, year.id)
    if policy is None or not policy.dunning_enabled:
        return _empty_result(reference, "disabled")
    steps = [step for step in (policy.dunning_schedule or []) if isinstance(step, dict)]
    steps.sort(key=lambda step: (_step_offset(step), int(step.get("level") or 0)))
    steps = [step for step in steps if _step_channels(step)]
    if not steps:
        return _empty_result(reference, "no_schedule")

    debts = await list_debts(
        db, school_id=school_id, as_of=reference, adapter=adapter
    )
    school = await db.get(School, school_id)
    guardians: dict[uuid.UUID, Optional[Guardian]] = {}
    planned: list[dict] = []
    sent = failed = skipped = 0

    for row in debts["rows"]:
        due = _as_date(row.get("due_date"))
        if due is None:
            continue
        due_steps = [
            step
            for step in steps
            if reference >= due + timedelta(days=_step_offset(step))
        ]
        if not due_steps:
            continue
        target = due_steps[-1]
        superseded = due_steps[:-1]
        channels = _step_channels(target)
        guardian_id = row.get("guardian_id")
        if not guardian_id:
            continue
        guardian_uuid = uuid.UUID(str(guardian_id))
        if guardian_uuid not in guardians:
            guardians[guardian_uuid] = await db.get(Guardian, guardian_uuid)
        guardian = guardians[guardian_uuid]
        if guardian is None:
            continue

        message = render_message(
            policy.dunning_message_template,
            guardian=guardian,
            row=row,
            due=due,
            reference=reference,
            school_name=school.name if school else None,
            step=target,
        )
        subject = f"Cobrança: {row.get('document_number') or 'factura'}"

        if dry_run or not dispatch:
            planned.append(
                {
                    "document_id": row.get("document_id"),
                    "document_number": row.get("document_number"),
                    "student_name": row.get("student_name"),
                    "guardian_name": f"{guardian.first_name} {guardian.last_name}",
                    "outstanding": row.get("outstanding"),
                    "due_date": due.isoformat(),
                    "level": int(target.get("level") or 0),
                    "offset_days": _step_offset(target),
                    "channels": channels,
                    "message": message,
                    "superseded_levels": [
                        int(step.get("level") or 0) for step in superseded
                    ],
                }
            )
            continue

        source_kind = SOURCE_KINDS.get(row.get("source") or "finreg", "finreg_document")
        source_id = uuid.UUID(str(row["document_id"]))
        student_id = (
            uuid.UUID(str(row["student_id"])) if row.get("student_id") else None
        )

        # Earlier rungs nobody saw: record them as skipped so enabling the
        # ladder on an old debt does not fire a blast of stale reminders.
        for step in superseded:
            for channel in _step_channels(step):
                exists = await _delivery_row(
                    db,
                    school_id=school_id,
                    source_kind=source_kind,
                    source_id=source_id,
                    offset_days=_step_offset(step),
                    channel=channel,
                )
                if exists is not None:
                    continue
                db.add(
                    DunningDelivery(
                        school_id=school_id,
                        source_kind=source_kind,
                        source_id=source_id,
                        document_number=row.get("document_number"),
                        guardian_id=guardian_uuid,
                        student_id=student_id,
                        level=int(step.get("level") or 0),
                        offset_days=_step_offset(step),
                        channel=channel,
                        status="skipped",
                        error="superseded",
                    )
                )
        if superseded:
            try:
                await db.commit()
            except IntegrityError:
                await db.rollback()

        for channel in channels:
            existing = await _delivery_row(
                db,
                school_id=school_id,
                source_kind=source_kind,
                source_id=source_id,
                offset_days=_step_offset(target),
                channel=channel,
            )
            if existing is not None and existing.status in ("sent", "skipped"):
                continue
            delivery = existing or DunningDelivery(
                school_id=school_id,
                source_kind=source_kind,
                source_id=source_id,
                document_number=row.get("document_number"),
                guardian_id=guardian_uuid,
                student_id=student_id,
                level=int(target.get("level") or 0),
                offset_days=_step_offset(target),
                channel=channel,
                status="failed",
            )
            status, error = await _deliver(
                db,
                school=school,
                guardian=guardian,
                row=row,
                student_id=student_id,
                channel=channel,
                message=message,
                subject=subject,
            )
            delivery.status = status
            delivery.error = error
            delivery.message_snapshot = message
            if status == "sent":
                delivery.sent_at = now_luanda()
                sent += 1
            elif status == "failed":
                failed += 1
            else:
                skipped += 1
            if existing is None:
                db.add(delivery)
            try:
                await db.commit()
            except IntegrityError:
                # Another worker inserted the same (document, offset,
                # channel) first; its outcome stands.
                await db.rollback()

    return {
        "as_of": reference.isoformat(),
        "enabled": True,
        "reason": None,
        "steps": len(steps),
        "planned": planned,
        "sent": sent,
        "failed": failed,
        "skipped": skipped,
    }


async def run_due_dunning(db: AsyncSession) -> dict:
    """Run every opted-in school's ladder (the daily Luanda-midnight job)."""
    school_ids = {
        row[0]
        for row in (
            await db.execute(
                select(SchoolFeePolicy.school_id)
                .join(
                    SchoolYear,
                    SchoolYear.id == SchoolFeePolicy.school_year_id,
                )
                .where(
                    SchoolFeePolicy.dunning_enabled.is_(True),
                    SchoolYear.is_active.is_(True),
                )
            )
        ).all()
    }
    totals = {"schools": 0, "sent": 0, "failed": 0, "skipped": 0}
    for school_id in school_ids:
        try:
            result = await run_dunning(db, school_id=school_id)
            totals["schools"] += 1
            totals["sent"] += result["sent"]
            totals["failed"] += result["failed"]
            totals["skipped"] += result["skipped"]
        except BillingError as exc:
            logger.warning("Dunning skipped for school %s: %s", school_id, exc.code)
            await db.rollback()
        except Exception:
            await db.rollback()
            logger.exception("Dunning failed for school %s", school_id)
    return totals


async def list_deliveries(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    status: Optional[str] = None,
    guardian_id: Optional[uuid.UUID] = None,
    limit: int = 200,
) -> list[DunningDelivery]:
    query = select(DunningDelivery).where(DunningDelivery.school_id == school_id)
    if status:
        query = query.where(DunningDelivery.status == status)
    if guardian_id is not None:
        query = query.where(DunningDelivery.guardian_id == guardian_id)
    return list(
        (
            await db.execute(
                query.order_by(DunningDelivery.created_at.desc()).limit(
                    min(max(limit, 1), 500)
                )
            )
        ).scalars().all()
    )
