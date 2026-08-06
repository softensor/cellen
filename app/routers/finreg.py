import uuid
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import (
    get_school_id,
    require_finance_access,
    require_school_admin,
)
from app.models.finance import BillingItem
from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregEntityMapping,
    FinregSchoolConnection,
)
from app.models.person import Child, Guardian
from app.services.finreg import FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import dispatch_instruction

router = APIRouter(prefix="/finreg", tags=["Finreg Integration"])


class ConnectionUpdate(BaseModel):
    finreg_company_id: uuid.UUID
    mode: str = Field(pattern="^(disabled|fake|shadow|pilot|live)$")
    kill_switch: bool = False


class SalesLine(BaseModel):
    billing_item_id: uuid.UUID
    quantity: Decimal = Field(gt=0)
    unit_price: Decimal = Field(ge=0)
    discount_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)


class SalesDraft(BaseModel):
    request_id: uuid.UUID
    guardian_id: uuid.UUID
    pupil_id: uuid.UUID
    academic_year_id: uuid.UUID | None = None
    academic_year_label: str | None = None
    billing_period: str = Field(pattern=r"^\d{4}-(0[1-9]|1[0-2])$")
    due_date: date | None = None
    lines: list[SalesLine] = Field(min_length=1)


async def _sales_payload(body: SalesDraft, school_id, db, actor_reference):
    guardian = (await db.execute(select(Guardian).where(
        Guardian.id == body.guardian_id, Guardian.school_id == school_id
    ))).scalar_one_or_none()
    child = (await db.execute(select(Child).where(
        Child.id == body.pupil_id, Child.school_id == school_id
    ))).scalar_one_or_none()
    if not guardian or not child:
        raise HTTPException(status_code=404, detail="Guardian or pupil not found")
    item_ids = [line.billing_item_id for line in body.lines]
    items = (await db.execute(select(BillingItem).where(
        BillingItem.id.in_(item_ids), BillingItem.school_id == school_id,
        BillingItem.is_active.is_(True),
    ))).scalars().all()
    by_id = {item.id: item for item in items}
    if len(by_id) != len(set(item_ids)):
        raise HTTPException(status_code=422, detail="Billing item not found or inactive")
    products, lines = [], []
    for line in body.lines:
        item = by_id[line.billing_item_id]
        external_id = str(item.id)
        products.append({"external_id": external_id, "data": {
            "sku": item.code, "name": item.name, "description": item.description,
            "unit_price": str(line.unit_price), "tax_rate": str(item.iva_rate),
            "tax_exemption_reason": item.iva_exemption_reason, "is_service": True,
        }})
        lines.append({"product_external_id": external_id, "description": item.name,
            "quantity": str(line.quantity), "unit_price": str(line.unit_price),
            "discount_pct": str(line.discount_pct), "tax_rate": str(item.iva_rate),
            "tax_exemption_reason": item.iva_exemption_reason})
    context = {"schema": "school/v1", "source_system": "cellen",
        "source_reference": str(body.request_id), "school_id": str(school_id),
        "pupil_id": str(child.id), "pupil_name": f"{child.first_name} {child.last_name}",
        "academic_year_id": str(body.academic_year_id) if body.academic_year_id else None,
        "academic_year_label": body.academic_year_label, "billing_period": body.billing_period}
    return {"actor_reference": actor_reference,
        "guardian": {"external_id": str(guardian.id), "data": {
            "tax_id": guardian.nif, "name": f"{guardian.first_name} {guardian.last_name}",
            "email": guardian.email, "phone": guardian.mobile_first,
            "address": guardian.street, "city": guardian.city, "country": "AO", "is_company": False}},
        "products": products, "draft": {"document": {
            "client_request_id": str(body.request_id), "document_type": "invoice",
            "due_date": body.due_date.isoformat() if body.due_date else None, "lines": lines,
        }, "context": context}}


@router.get("/connection")
async def connection(school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db), _=Depends(require_finance_access)):
    value = (await db.execute(select(FinregSchoolConnection).where(FinregSchoolConnection.school_id == school_id))).scalar_one_or_none()
    if not value: return {"mode": "disabled", "configured": False, "kill_switch": False}
    return {"mode": value.mode, "configured": True, "kill_switch": value.kill_switch,
            "finreg_company_id": str(value.finreg_company_id), "last_sync_at": value.last_sync_at,
            "last_event_sequence": value.last_event_sequence}


@router.put("/connection")
async def update_connection(body: ConnectionUpdate, school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db), _=Depends(require_school_admin)):
    value = (await db.execute(select(FinregSchoolConnection).where(FinregSchoolConnection.school_id == school_id))).scalar_one_or_none()
    if not value:
        value = FinregSchoolConnection(school_id=school_id, finreg_company_id=body.finreg_company_id)
        db.add(value)
    value.finreg_company_id, value.mode, value.kill_switch = body.finreg_company_id, body.mode, body.kill_switch
    await db.commit()
    return {"mode": value.mode, "kill_switch": value.kill_switch, "finreg_company_id": str(value.finreg_company_id)}


@router.get("/capabilities")
async def capabilities(user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    try: return await HttpFinregAdapter().capabilities(str(user.id))
    except FinregError as exc: raise HTTPException(status_code=503 if exc.retryable else 502, detail={"code": exc.code, "message": exc.detail})


@router.get("/instructions")
async def instructions(limit: int = 100, school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db), _=Depends(require_finance_access)):
    rows = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id).order_by(FinregBillingInstruction.created_at.desc()).limit(min(limit, 500)))).scalars().all()
    return [{"id": str(x.id), "status": x.status, "attempts": x.attempts,
             "finreg_document_id": str(x.finreg_document_id) if x.finreg_document_id else None,
             "error_code": x.error_code, "error_detail": x.error_detail,
             "correlation_id": str(x.correlation_id), "created_at": x.created_at} for x in rows]


@router.post("/instructions/{instruction_id}/retry")
async def retry(instruction_id: uuid.UUID, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    item = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.id == instruction_id, FinregBillingInstruction.school_id == school_id))).scalar_one_or_none()
    if not item: raise HTTPException(status_code=404, detail="Billing instruction not found")
    if item.status == "confirmed": return {"id": str(item.id), "status": item.status}
    item.status, item.next_attempt_at = "pending", None
    item.payload["actor_reference"] = str(user.id)
    try: await dispatch_instruction(db, item)
    except FinregError as exc: raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})
    return {"id": str(item.id), "status": item.status, "finreg_document_id": str(item.finreg_document_id)}


@router.get("/mappings")
async def mappings(school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db), _=Depends(require_finance_access)):
    rows = (await db.execute(select(FinregEntityMapping).where(FinregEntityMapping.school_id == school_id))).scalars().all()
    return [{"entity_type": x.entity_type, "cellen_id": str(x.cellen_id), "finreg_id": str(x.finreg_id),
             "status": x.status, "last_error_code": x.last_error_code} for x in rows]


@router.post("/sales/preview")
async def sales_preview(body: SalesDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    payload = await _sales_payload(body, school_id, db, str(user.id))
    try:
        return await HttpFinregAdapter().request(
            "POST", "preview", payload["draft"], actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422,
                            detail={"code": exc.code, "message": exc.detail})


@router.post("/sales/issue", status_code=201)
async def sales_issue(body: SalesDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    if not connection or connection.mode not in {"fake", "pilot", "live"} or connection.kill_switch:
        raise HTTPException(status_code=409, detail="Finreg issuance is not enabled for this school")
    existing = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.id == body.request_id,
    ))).scalar_one_or_none()
    if existing:
        return {"id": str(existing.id), "status": existing.status,
                "finreg_document_id": str(existing.finreg_document_id) if existing.finreg_document_id else None}
    payload = await _sales_payload(body, school_id, db, str(user.id))
    instruction = FinregBillingInstruction(
        id=body.request_id, school_id=school_id,
        idempotency_key=f"cellen-sales-{body.request_id}", payload=payload,
    )
    db.add(instruction)
    await db.commit()
    try:
        await dispatch_instruction(db, instruction)
    except FinregError as exc:
        if not exc.retryable:
            raise HTTPException(status_code=422, detail={"code": exc.code, "message": exc.detail})
    return {"id": str(instruction.id), "status": instruction.status,
            "finreg_document_id": str(instruction.finreg_document_id) if instruction.finreg_document_id else None}
