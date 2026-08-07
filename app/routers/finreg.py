import hashlib
import json
import uuid
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.config import settings
from app.core.dependencies import (
    get_school_id,
    require_finance_access,
    require_parent,
    require_school_admin,
)
from app.models.finance import BillingItem, Payment
from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregEntityMapping,
    FinregSchoolConnection,
)
from app.models.person import Child, Guardian
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
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


class PaymentDraft(BaseModel):
    document_id: uuid.UUID
    amount: Decimal = Field(gt=0)
    method: str = Field(pattern="^(cash|transfer|card|check|mobile|other)$")
    external_reference: uuid.UUID


class CorrectionDraft(BaseModel):
    external_reference: uuid.UUID
    reason: str = Field(min_length=3, max_length=250)


class BillingPlanLineDraft(BaseModel):
    billing_item_id: uuid.UUID
    quantity: Decimal = Field(default=Decimal("1"), gt=0)
    discount_pct: Decimal = Field(default=Decimal("0"), ge=0, le=100)


class BillingPlanDraft(BaseModel):
    external_id: uuid.UUID = Field(default_factory=uuid.uuid4)
    guardian_id: uuid.UUID
    pupil_id: uuid.UUID
    academic_year_id: uuid.UUID | None = None
    academic_year_label: str | None = None
    frequency: str = Field(pattern="^(weekly|monthly|quarterly|annual)$")
    interval_count: int = Field(default=1, ge=1, le=120)
    due_days: int = Field(default=10, ge=0, le=365)
    next_run_date: date
    end_date: date | None = None
    notes: str | None = Field(default=None, max_length=2000)
    lines: list[BillingPlanLineDraft] = Field(min_length=1)


class BillingPlanStateDraft(BaseModel):
    reason: str | None = Field(default=None, max_length=500)
    next_run_date: date | None = None


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
    effective_mode = value.mode if settings.FINREG_INTEGRATION_ENABLED else "disabled"
    return {"mode": effective_mode, "configured": True, "kill_switch": value.kill_switch,
            "configured_mode": value.mode, "globally_enabled": settings.FINREG_INTEGRATION_ENABLED,
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
async def capabilities(user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    if not settings.FINREG_INTEGRATION_ENABLED:
        raise HTTPException(status_code=409, detail="Finreg integration is globally disabled")
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    if connection is None:
        raise HTTPException(status_code=409, detail="Finreg is not configured for this school")
    if connection.mode == "fake":
        manifest = await FakeFinregAdapter().capabilities(str(user.id))
        return {**manifest, "company_id": str(connection.finreg_company_id),
                "terminology": {"customer": "guardian", "beneficiary": "pupil"},
                "enabled_modules": ["billing"], "supported_entity_types": []}
    try:
        manifest = await HttpFinregAdapter().capabilities(str(user.id))
        if str(manifest.get("company_id")) != str(connection.finreg_company_id):
            raise HTTPException(status_code=409, detail={
                "code": "company_mismatch",
                "message": "The configured Finreg credential belongs to another company",
            })
        return manifest
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


async def _writable_or_shadow_connection(school_id, db):
    if not settings.FINREG_INTEGRATION_ENABLED:
        raise HTTPException(status_code=409, detail="Finreg integration is globally disabled")
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    if not connection or connection.mode not in {"shadow", "pilot", "live"} or connection.kill_switch:
        raise HTTPException(status_code=409, detail="Finreg billing plans are not enabled for this school")
    return connection


@router.get("/billing-plans")
async def billing_plans(user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    await _writable_or_shadow_connection(school_id, db)
    try:
        return await HttpFinregAdapter().request(
            "GET", "billing-plans", None, actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422,
                            detail={"code": exc.code, "message": exc.detail})


@router.put("/billing-plans/{external_id}")
async def upsert_billing_plan(
    external_id: uuid.UUID, body: BillingPlanDraft,
    user=Depends(require_school_admin), school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    if body.external_id != external_id:
        raise HTTPException(status_code=422, detail="Billing plan external ID must match the URL")
    connection = await _writable_or_shadow_connection(school_id, db)
    guardian = (await db.execute(select(Guardian).where(
        Guardian.id == body.guardian_id, Guardian.school_id == school_id
    ))).scalar_one_or_none()
    child = (await db.execute(select(Child).where(
        Child.id == body.pupil_id, Child.school_id == school_id
    ))).scalar_one_or_none()
    if guardian is None or child is None:
        raise HTTPException(status_code=404, detail="Guardian or pupil not found")
    item_ids = [line.billing_item_id for line in body.lines]
    items = (await db.execute(select(BillingItem).where(
        BillingItem.id.in_(item_ids), BillingItem.school_id == school_id,
        BillingItem.is_active.is_(True),
    ))).scalars().all()
    by_id = {item.id: item for item in items}
    if len(by_id) != len(set(item_ids)):
        raise HTTPException(status_code=422, detail="Billing item not found or inactive")
    adapter = HttpFinregAdapter()
    actor = str(user.id)
    correlation = str(uuid.uuid4())
    revision = hashlib.sha256(json.dumps(body.model_dump(mode="json"), sort_keys=True).encode()).hexdigest()[:16]
    key = f"cellen-plan-{external_id}-{revision}"
    try:
        customer = await adapter.request("PUT", f"customers/{guardian.id}", {"customer": {
            "tax_id": guardian.nif, "name": f"{guardian.first_name} {guardian.last_name}",
            "email": guardian.email, "phone": guardian.mobile_first,
            "address": guardian.street, "city": guardian.city, "country": "AO", "is_company": False,
        }}, idempotency_key=f"{key}:customer", correlation_id=correlation, actor_reference=actor)
        finreg_products = {}
        for item in items:
            product = await adapter.request("PUT", f"products/{item.id}", {"product": {
                "sku": item.code, "name": item.name, "description": item.description,
                "unit_price": str(item.unit_price), "tax_rate": str(item.iva_rate),
                "tax_exemption_reason": item.iva_exemption_reason, "is_service": True,
            }}, idempotency_key=f"{key}:product:{item.id}", correlation_id=correlation,
               actor_reference=actor)
            finreg_products[item.id] = product["id"]
        context = {
            "schema": "school/v1", "source_system": "cellen",
            "source_reference": str(external_id), "school_id": str(school_id),
            "pupil_id": str(child.id), "pupil_name": f"{child.first_name} {child.last_name}",
            "academic_year_id": str(body.academic_year_id) if body.academic_year_id else None,
            "academic_year_label": body.academic_year_label,
        }
        payload = {"template": {
            "customer_id": customer["id"], "document_type": "invoice",
            "frequency": body.frequency, "interval_count": body.interval_count,
            "due_days": body.due_days,
            "next_run_date": body.next_run_date.isoformat(),
            "end_date": body.end_date.isoformat() if body.end_date else None,
            "generation_mode": "draft" if connection.mode == "shadow" else "finalize",
            "notes": body.notes,
            "lines": [{
                "product_id": finreg_products[line.billing_item_id],
                "description": by_id[line.billing_item_id].name,
                "quantity": str(line.quantity), "unit": "un",
                "unit_price": str(by_id[line.billing_item_id].unit_price),
                "discount_pct": str(line.discount_pct),
                "tax_rate": str(by_id[line.billing_item_id].iva_rate),
                "tax_exemption_reason": by_id[line.billing_item_id].iva_exemption_reason,
            } for line in body.lines],
        }, "context": context, "external_version": "student-billing-plan/v1"}
        return await adapter.request("PUT", f"billing-plans/{external_id}", payload,
                                     idempotency_key=f"{key}:upsert", correlation_id=correlation,
                                     actor_reference=actor)
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422,
                            detail={"code": exc.code, "message": exc.detail})


@router.post("/billing-plans/{external_id}/{action}")
async def change_billing_plan_state(
    external_id: uuid.UUID, action: str, body: BillingPlanStateDraft,
    user=Depends(require_school_admin), school_id=Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
):
    if action not in {"pause", "resume"}:
        raise HTTPException(status_code=404, detail="Unsupported billing-plan action")
    await _writable_or_shadow_connection(school_id, db)
    try:
        return await HttpFinregAdapter().request("POST", f"billing-plans/{external_id}/{action}", {
            "reason": body.reason,
            "next_run_date": body.next_run_date.isoformat() if body.next_run_date else None,
        }, actor_reference=str(user.id))
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422,
                            detail={"code": exc.code, "message": exc.detail})


@router.post("/sales/preview")
async def sales_preview(body: SalesDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    payload = await _sales_payload(body, school_id, db, str(user.id))
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    if connection and connection.mode == "fake":
        net = tax = Decimal("0")
        for line in payload["draft"]["document"]["lines"]:
            base = Decimal(line["quantity"]) * Decimal(line["unit_price"])
            line_net = base * (Decimal("1") - Decimal(line["discount_pct"]) / 100)
            net += line_net
            tax += line_net * Decimal(line["tax_rate"]) / 100
        return {"currency_code": "AOA", "net_total": float(net),
                "tax_total": float(tax), "gross_total": float(net + tax),
                "schema_version": "school/v1"}
    try:
        return await HttpFinregAdapter().request(
            "POST", "preview", payload["draft"], actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422,
                            detail={"code": exc.code, "message": exc.detail})


@router.post("/sales/issue", status_code=201)
async def sales_issue(body: SalesDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    if not settings.FINREG_INTEGRATION_ENABLED:
        raise HTTPException(status_code=409, detail="Finreg integration is globally disabled")
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


async def _writable_connection(school_id, db):
    if not settings.FINREG_INTEGRATION_ENABLED:
        raise HTTPException(status_code=409, detail="Finreg integration is globally disabled")
    connection = (await db.execute(select(FinregSchoolConnection).where(
        FinregSchoolConnection.school_id == school_id
    ))).scalar_one_or_none()
    if not connection or connection.mode not in {"pilot", "live"} or connection.kill_switch:
        raise HTTPException(status_code=409, detail="Finreg fiscal writes are not enabled for this school")
    return connection


@router.get("/documents/{external_reference}")
async def document_detail(external_reference: uuid.UUID, user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    try:
        return await HttpFinregAdapter().request(
            "GET", f"documents/{external_reference}", None, actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/documents/{external_reference}/pdf")
async def document_pdf(external_reference: uuid.UUID, user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    try:
        content = await HttpFinregAdapter().download(
            f"documents/{external_reference}/pdf", actor_reference=str(user.id)
        )
        return Response(content=content, media_type="application/pdf", headers={
            "Content-Disposition": f'inline; filename="finreg-{external_reference}.pdf"'
        })
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.post("/payments", status_code=201)
async def register_payment(body: PaymentDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    await _writable_connection(school_id, db)
    adapter = HttpFinregAdapter()
    key = f"cellen-payment-{body.external_reference}"
    payload = {"payment": {
        "document_id": str(body.document_id), "payment_method": body.method,
        "amount": str(body.amount), "payment_date": date.today().isoformat(),
        "reference": str(body.external_reference),
    }}
    try:
        payment = await adapter.request(
            "POST", f"payments/{body.external_reference}", payload,
            idempotency_key=key, correlation_id=str(body.external_reference), actor_reference=str(user.id),
        )
        receipt = await adapter.request(
            "POST", f"payments/{body.external_reference}/receipt", {},
            idempotency_key=f"{key}:receipt", correlation_id=str(body.external_reference), actor_reference=str(user.id),
        )
        return {"id": payment["id"], "status": "confirmed",
                "receipt_id": receipt.get("receipt_document_id"), "receipt": receipt}
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.post("/documents/{external_reference}/corrections", status_code=201)
async def correct_document(external_reference: uuid.UUID, body: CorrectionDraft, user=Depends(require_finance_access), school_id=Depends(get_school_id), db: AsyncSession = Depends(get_db)):
    await _writable_connection(school_id, db)
    try:
        return await HttpFinregAdapter().request(
            "POST", f"documents/{external_reference}/corrections",
            {"external_id": str(body.external_reference), "reason": body.reason},
            idempotency_key=f"cellen-correction-{body.external_reference}",
            correlation_id=str(body.external_reference), actor_reference=str(user.id),
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/receipts/{payment_reference}/pdf")
async def receipt_pdf(payment_reference: uuid.UUID, user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    try:
        content = await HttpFinregAdapter().download(
            f"receipts/{payment_reference}/pdf", actor_reference=str(user.id)
        )
        return Response(content=content, media_type="application/pdf", headers={
            "Content-Disposition": f'inline; filename="finreg-receipt-{payment_reference}.pdf"'
        })
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/customers/{guardian_id}/statement")
async def customer_statement(guardian_id: uuid.UUID, date_from: date, date_to: date,
                             user=Depends(require_finance_access), school_id=Depends(get_school_id),
                             db: AsyncSession = Depends(get_db)):
    # Tenant ownership is checked locally before the company-scoped Finreg call.
    guardian = (await db.execute(select(Guardian).where(
        Guardian.id == guardian_id, Guardian.school_id == school_id
    ))).scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")
    try:
        return await HttpFinregAdapter().request(
            "GET", f"customers/{guardian_id}/statement?date_from={date_from}&date_to={date_to}",
            None, actor_reference=str(user.id),
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/reports/sales-summary")
async def sales_summary(date_from: date, date_to: date, user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    try:
        return await HttpFinregAdapter().request(
            "GET", f"reports/sales-summary?date_from={date_from}&date_to={date_to}",
            None, actor_reference=str(user.id),
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/reports/delinquent")
async def delinquent_report(as_of: date | None = None, user=Depends(require_finance_access), school_id=Depends(get_school_id)):
    suffix = f"?as_of={as_of}" if as_of else ""
    try:
        return await HttpFinregAdapter().request(
            "GET", f"reports/delinquent{suffix}", None, actor_reference=str(user.id)
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


async def _parent_instruction(instruction_id, current_user, db):
    guardian_id = getattr(current_user, "guardian_id", None)
    school_id = getattr(current_user, "_school_id", None)
    if guardian_id is None or school_id is None:
        raise HTTPException(status_code=403, detail="Guardian and school context required")
    item = await db.get(FinregBillingInstruction, instruction_id)
    if item is None or item.school_id != school_id:
        raise HTTPException(status_code=404, detail="Finreg document not found")
    if str((item.payload.get("guardian") or {}).get("external_id")) != str(guardian_id):
        raise HTTPException(status_code=403, detail="This document does not belong to the guardian")
    return item


@router.get("/parent/documents")
async def parent_documents(current_user=Depends(require_parent), db: AsyncSession = Depends(get_db)):
    guardian_id = getattr(current_user, "guardian_id", None)
    school_id = getattr(current_user, "_school_id", None)
    if guardian_id is None or school_id is None:
        raise HTTPException(status_code=403, detail="Guardian and school context required")
    rows = (await db.execute(select(FinregBillingInstruction).where(
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.status == "confirmed",
    ).order_by(FinregBillingInstruction.created_at.desc()))).scalars().all()
    payment_rows = (await db.execute(select(Payment).where(
        Payment.school_id == school_id,
        Payment.billing_guardian_id == guardian_id,
        Payment.finreg_document_external_reference.is_not(None),
    ).order_by(Payment.created_at))).scalars().all()
    proofs_by_document: dict[str, list[dict]] = {}
    for payment in payment_rows:
        proofs_by_document.setdefault(
            str(payment.finreg_document_external_reference), []
        ).append({
            "id": str(payment.id),
            "status": payment.status,
            "notes": payment.notes,
            "amount": float(payment.amount),
            "receipt_proof_url": payment.receipt_proof_url,
            "created_at": payment.created_at.isoformat() if payment.created_at else None,
        })
    output = []
    for item in rows:
        if str((item.payload.get("guardian") or {}).get("external_id")) != str(guardian_id):
            continue
        context = ((item.payload.get("draft") or {}).get("context") or {})
        document = item.result_snapshot or {}
        total = document.get("gross_total", 0)
        output.append({
            "id": str(item.id), "finreg": True,
            "child_id": context.get("pupil_id"),
            "child_name": context.get("pupil_name") or "—",
            "document_type": document.get("document_type", "invoice"),
            "full_document_number": document.get("full_document_number") or document.get("document_number") or "Finreg",
            "reference_month": f'{context["billing_period"]}-01' if context.get("billing_period") else None,
            "gross_total": total, "status": document.get("status", "issued"),
            "due_date": document.get("due_date"),
            "amount_paid": document.get("amount_paid", 0),
            "balance": document.get("balance", total),
            "payment_proofs": proofs_by_document.get(str(item.id), []),
        })
    return output


@router.get("/parent/documents/{instruction_id}/pdf")
async def parent_document_pdf(instruction_id: uuid.UUID, current_user=Depends(require_parent), db: AsyncSession = Depends(get_db)):
    item = await _parent_instruction(instruction_id, current_user, db)
    try:
        content = await HttpFinregAdapter().download(
            f"documents/{item.id}/pdf", actor_reference=str(current_user.id)
        )
        return Response(content=content, media_type="application/pdf", headers={
            "Content-Disposition": f'inline; filename="finreg-{item.id}.pdf"'
        })
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/parent/receipts")
async def parent_receipts(current_user=Depends(require_parent), db: AsyncSession = Depends(get_db)):
    guardian_id = getattr(current_user, "guardian_id", None)
    school_id = getattr(current_user, "_school_id", None)
    if guardian_id is None or school_id is None:
        raise HTTPException(status_code=403, detail="Guardian and school context required")
    rows = (await db.execute(select(Payment).where(
        Payment.school_id == school_id,
        Payment.billing_guardian_id == guardian_id,
        Payment.status == "normal",
        Payment.finreg_payment_external_reference.is_not(None),
    ).order_by(Payment.created_at.desc()))).scalars().all()
    return [{
        "id": str(payment.id),
        "finreg": True,
        "full_document_number": f"Finreg RC · {str(payment.id)[:8]}",
        "system_entry_date": payment.created_at.isoformat(),
        "gross_total": float(payment.amount),
        "payment_method": payment.payment_method,
    } for payment in rows]


@router.get("/parent/statement")
async def parent_statement(current_user=Depends(require_parent), db: AsyncSession = Depends(get_db)):
    guardian_id = getattr(current_user, "guardian_id", None)
    school_id = getattr(current_user, "_school_id", None)
    if guardian_id is None or school_id is None:
        raise HTTPException(status_code=403, detail="Guardian and school context required")
    guardian = (await db.execute(select(Guardian).where(
        Guardian.id == guardian_id, Guardian.school_id == school_id
    ))).scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")
    today = date.today()
    try:
        return await HttpFinregAdapter().request(
            "GET",
            f"customers/{guardian_id}/statement?date_from={today.year}-01-01&date_to={today.isoformat()}",
            None,
            actor_reference=str(current_user.id),
        )
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})


@router.get("/parent/receipts/{payment_id}/pdf")
async def parent_receipt_pdf(payment_id: uuid.UUID, current_user=Depends(require_parent), db: AsyncSession = Depends(get_db)):
    guardian_id = getattr(current_user, "guardian_id", None)
    school_id = getattr(current_user, "_school_id", None)
    payment = (await db.execute(select(Payment).where(
        Payment.id == payment_id,
        Payment.school_id == school_id,
        Payment.billing_guardian_id == guardian_id,
        Payment.status == "normal",
        Payment.finreg_payment_external_reference.is_not(None),
    ))).scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Finreg receipt not found")
    try:
        content = await HttpFinregAdapter().download(
            f"receipts/{payment.finreg_payment_external_reference}/pdf",
            actor_reference=str(current_user.id),
        )
        return Response(content=content, media_type="application/pdf", headers={
            "Content-Disposition": f'inline; filename="finreg-receipt-{payment.id}.pdf"'
        })
    except FinregError as exc:
        raise HTTPException(status_code=503 if exc.retryable else 422, detail={"code": exc.code, "message": exc.detail})
