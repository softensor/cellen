import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregSchoolConnection,
)
from app.core.config import settings
from app.services.finreg import (
    FakeFinregAdapter,
    FinregError,
    HttpFinregAdapter,
    billing_idempotency_key,
    school_context,
)


async def integration_mode(db: AsyncSession, school_id) -> str:
    if not settings.FINREG_INTEGRATION_ENABLED:
        return "disabled"
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    return connection.mode if connection and not connection.kill_switch else "disabled"


async def enqueue_contract_instruction(
    db: AsyncSession, *, school_id, contract_id, guardian, child, billing_item_id,
    description: str, quantity, unit_price, discount_percent, discount_amount,
    tax_rate, tax_exemption_reason, reference_month, due_date, school_year_id,
    school_year_label, actor_reference: str,
):
    period = reference_month.strftime("%Y-%m")
    key = billing_idempotency_key(school_id, contract_id, period)
    existing = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.idempotency_key == key,
    ))).scalar_one_or_none()
    if existing:
        return existing
    instruction = FinregBillingInstruction(
        school_id=school_id, contract_id=contract_id, idempotency_key=key,
        payload={},
    )
    db.add(instruction)
    await db.flush()
    effective_discount = discount_percent
    base = quantity * unit_price
    if discount_amount and base:
        effective_discount = discount_amount * 100 / base
    line = {"description": description, "quantity": str(quantity), "unit_price": str(unit_price),
            "discount_pct": str(effective_discount),
            "tax_rate": str(tax_rate), "tax_exemption_reason": tax_exemption_reason}
    instruction.payload = {
        "actor_reference": actor_reference,
        "guardian": {"external_id": str(guardian.id), "data": {
            "tax_id": guardian.nif, "name": f"{guardian.first_name} {guardian.last_name}",
            "email": guardian.email, "phone": guardian.mobile_first,
            "address": guardian.street, "city": guardian.city, "country": "AO", "is_company": False,
        }},
        "product": {"external_id": str(billing_item_id or contract_id), "data": {
            "sku": str(billing_item_id or contract_id), "name": description,
            "unit_price": str(unit_price), "tax_rate": str(tax_rate),
            "tax_exemption_reason": tax_exemption_reason, "is_service": True,
        }},
        "draft": {"document": {
            "client_request_id": str(instruction.id), "document_type": "invoice",
            "document_date": reference_month.isoformat(),
            "due_date": due_date.isoformat() if due_date else None, "lines": [line],
        }, "context": school_context(
            instruction_id=instruction.id, school_id=school_id, pupil_id=child.id,
            pupil_name=f"{child.first_name} {child.last_name}", enrolment_id=None,
            academic_year_id=school_year_id, academic_year_label=school_year_label,
            billing_period=period,
        )},
    }
    await db.commit()
    return instruction


async def dispatch_instruction(db: AsyncSession, instruction: FinregBillingInstruction, *, adapter=None):
    if not settings.FINREG_INTEGRATION_ENABLED:
        raise FinregError("integration_disabled", "Finreg integration is globally disabled")
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == instruction.school_id
    ))).scalar_one_or_none()
    if connection is None or connection.mode == "disabled" or connection.kill_switch:
        raise FinregError("integration_disabled", "Finreg integration is disabled for this school")
    instruction.status = "processing"
    instruction.attempts += 1
    await db.commit()
    adapter = adapter or (FakeFinregAdapter() if connection.mode == "fake" else HttpFinregAdapter())
    payload = instruction.payload
    actor = payload.get("actor_reference", "cellen-system")
    try:
        if isinstance(adapter, FakeFinregAdapter):
            document = await adapter.execute("drafts", payload["draft"],
                idempotency_key=instruction.idempotency_key, correlation_id=str(instruction.correlation_id), actor_reference=actor)
        else:
            guardian = payload["guardian"]
            customer = await adapter.request("PUT", f"customers/{guardian['external_id']}",
                {"customer": guardian["data"]}, idempotency_key=f"{instruction.idempotency_key}:customer",
                correlation_id=str(instruction.correlation_id), actor_reference=actor)
            draft = dict(payload["draft"])
            draft["document"] = dict(draft["document"], customer_id=customer["id"])
            items = payload.get("products") or ([payload["product"]] if payload.get("product") else [])
            product_ids = {}
            for item in items:
                product = await adapter.request("PUT", f"products/{item['external_id']}",
                    {"product": item["data"]},
                    idempotency_key=f"{instruction.idempotency_key}:product:{item['external_id']}",
                    correlation_id=str(instruction.correlation_id), actor_reference=actor)
                product_ids[item["external_id"]] = product["id"]
            for line in draft["document"]["lines"]:
                external_product = line.pop("product_external_id", None)
                if external_product:
                    line["product_id"] = product_ids[external_product]
            document = await adapter.request("POST", "drafts", draft,
                idempotency_key=f"{instruction.idempotency_key}:draft",
                correlation_id=str(instruction.correlation_id), actor_reference=actor)
            if connection.mode in {"pilot", "live"}:
                document = await adapter.request("POST", f"documents/{instruction.id}/finalize", {},
                    idempotency_key=f"{instruction.idempotency_key}:finalize",
                    correlation_id=str(instruction.correlation_id), actor_reference=actor)
        instruction.finreg_document_id = uuid.UUID(document["id"])
        instruction.result_snapshot = document
        instruction.status = "confirmed"
        instruction.error_code = instruction.error_detail = None
        instruction.next_attempt_at = None
        await db.commit()
        return instruction
    except FinregError as exc:
        instruction.error_code, instruction.error_detail = exc.code, exc.detail
        instruction.status = "unknown" if exc.unknown_outcome else ("pending" if exc.retryable else "rejected")
        if exc.retryable:
            instruction.next_attempt_at = datetime.now(timezone.utc) + timedelta(seconds=min(3600, 2 ** min(instruction.attempts, 10)))
        await db.commit()
        raise


async def dispatch_pending(db: AsyncSession, limit: int = 50) -> tuple[int, int]:
    now = datetime.now(timezone.utc)
    rows = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.status == "pending",
        (FinregBillingInstruction.next_attempt_at.is_(None) | (FinregBillingInstruction.next_attempt_at <= now)),
    ).order_by(FinregBillingInstruction.created_at).with_for_update(skip_locked=True).limit(limit))).scalars().all()
    confirmed = failed = 0
    for row in rows:
        try:
            await dispatch_instruction(db, row)
            confirmed += 1
        except FinregError:
            failed += 1
    return confirmed, failed
