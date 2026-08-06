import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregEntityMapping,
    FinregEventReceipt,
    FinregSchoolConnection,
)
from app.core.config import settings
from app.services.finreg import FinregError, HttpFinregAdapter


async def synchronize_connection(
    db: AsyncSession,
    connection: FinregSchoolConnection,
    *,
    adapter: HttpFinregAdapter | None = None,
    limit: int = 100,
) -> int:
    """Consume one ordered, idempotent page of the company-bound event feed."""
    if connection.mode not in {"shadow", "pilot", "live"} or connection.kill_switch:
        return 0
    adapter = adapter or HttpFinregAdapter()
    actor = f"cellen-event-sync:{connection.school_id}"
    manifest = await adapter.capabilities(actor)
    if str(manifest.get("company_id")) != str(connection.finreg_company_id):
        raise FinregError(
            "company_mismatch",
            "The configured Finreg credential belongs to another company",
        )
    events = await adapter.request(
        "GET",
        f"events?after={connection.last_event_sequence}&limit={limit}",
        None,
        actor_reference=actor,
    )
    processed = 0
    for event in events:
        sequence = int(event["sequence_id"])
        if sequence <= connection.last_event_sequence:
            continue
        event_id = uuid.UUID(str(event["event_id"]))
        exists = (await db.execute(select(FinregEventReceipt).where(
            FinregEventReceipt.school_id == connection.school_id,
            FinregEventReceipt.event_id == event_id,
        ))).scalar_one_or_none()
        if exists is None:
            payload = event.get("payload") or {}
            external_id = payload.get("external_id")
            entity_type = str(event.get("entity_type") or "")
            try:
                cellen_id = uuid.UUID(str(external_id)) if external_id else None
                finreg_id = uuid.UUID(str(event["entity_id"]))
            except (TypeError, ValueError):
                cellen_id = None
            if cellen_id and entity_type in {"customer", "product", "document", "payment", "receipt"}:
                mapping = (await db.execute(select(FinregEntityMapping).where(
                    FinregEntityMapping.school_id == connection.school_id,
                    FinregEntityMapping.entity_type == entity_type,
                    FinregEntityMapping.cellen_id == cellen_id,
                ))).scalar_one_or_none()
                if mapping is None:
                    db.add(FinregEntityMapping(
                        school_id=connection.school_id,
                        entity_type=entity_type,
                        cellen_id=cellen_id,
                        finreg_id=finreg_id,
                    ))
                else:
                    mapping.finreg_id = finreg_id
                    mapping.status = "confirmed"
                    mapping.last_error_code = None
            if entity_type == "document" and external_id:
                try:
                    instruction_id = uuid.UUID(str(external_id))
                except (TypeError, ValueError):
                    instruction_id = None
                if instruction_id:
                    instruction = await db.get(FinregBillingInstruction, instruction_id)
                    if instruction and instruction.school_id == connection.school_id:
                        instruction.finreg_document_id = uuid.UUID(str(event["entity_id"]))
                        instruction.status = "confirmed"
                        instruction.result_snapshot = payload
                        instruction.error_code = instruction.error_detail = None
            db.add(FinregEventReceipt(
                school_id=connection.school_id,
                event_id=event_id,
                sequence_id=sequence,
                event_type=str(event["event_type"]),
                payload=payload,
            ))
            processed += 1
        connection.last_event_sequence = sequence
    connection.last_sync_at = datetime.now(timezone.utc)
    await db.commit()
    return processed


async def synchronize_enabled_connections(db: AsyncSession) -> tuple[int, int]:
    if not settings.FINREG_INTEGRATION_ENABLED:
        return 0, 0
    rows = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.mode.in_(["shadow", "pilot", "live"]),
        FinregSchoolConnection.kill_switch.is_(False),
    ))).scalars().all()
    processed = failed = 0
    for connection in rows:
        try:
            processed += await synchronize_connection(db, connection)
        except FinregError:
            failed += 1
            await db.rollback()
    return processed, failed
