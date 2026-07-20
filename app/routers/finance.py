# -*- coding: utf-8 -*-
"""
Finance API router - AGT-compliant invoicing, payments, and reporting.

Organized by domain:
- Billing Items & Price Tables
- Contracts
- Invoices (FT/FR/ND emission, bulk generation)
- Credit Notes (NC)
- Payments & Receipts
- Payment References (Multicaixa)
- Credit Balances
- Cash Sessions
- Payment Plans & Dunning
- Reports (P&L, delinquency, SAF-T, account statement)
- Expenses
"""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_parent, require_school_admin
from app.models.finance import (
    BillingItem, BillingItemPrice, CashSession, Contract, CreditEntry, CreditNote,
    CreditRefund, DocumentSeries, Expense, ExpenseCategory, FinanceAuditEntry,
    Invoice, InvoiceLine, Payment, PaymentAllocation, PaymentPlan,
    PaymentPlanInstallment, PaymentReference, Receipt, ReminderLog,
)
from app.models.person import Child, Guardian
from app.schemas.finance import (
    AccountStatementResponse,
    BillingItemCreate, BillingItemPriceCreate, BillingItemPriceResponse,
    BillingItemPriceRollRequest, BillingItemResponse, BillingItemUpdate,
    CashFlowMonth, CashSessionClose, CashSessionOpen, CashSessionResponse,
    ContractCreate, ContractResponse, ContractUpdate,
    CreditApplyRequest, CreditEntryResponse, CreditNoteCreate, CreditNoteResponse,
    CreditRefundRequest, GuardianCreditSummary,
    DocumentSeriesResponse,
    ExpenseCategoryCreate, ExpenseCategoryResponse, ExpenseCategoryUpdate,
    ExpenseCreate, ExpenseResponse, ExpenseUpdate,
    InvoiceBulkCreate, InvoiceCreate, InvoiceResponse, OutstandingInvoice,
    ParentInvoiceResponse, PaymentCreate, PaymentPlanCreate, PaymentPlanResponse,
    PaymentReferenceCreate, PaymentReferenceMarkPaid, PaymentReferenceResponse,
    PaymentResponse, ReceiptResponse, ReminderCreate, ReminderResponse,
)
from app.services.finance import (
    DocumentEmissionService, PaymentIntakeService,
    apply_credit_to_invoice, generate_annual_pl, generate_monthly_pl,
    get_account_statement, get_guardian_credit_balance, get_guardians_with_credit,
    get_invoice_amount_paid, get_invoice_balance, get_outstanding_invoices,
    mark_overdue_invoices, recalculate_invoice_status, resolve_unit_price, reverse_payment,
)
from app.services.storage import save_upload
from app.utils.agt import now_luanda, signature_excerpt, today_luanda

router = APIRouter(prefix="/finance", tags=["Finance"])


# ─── Permission helpers ──────────────────────────────────────────────────────

async def require_finance_access(user=Depends(get_current_user)):
    """finance_officer or school_admin can access finance."""
    role = getattr(user, "_role", None)
    if role not in ("school_admin", "finance_officer", "platform_admin"):
        raise HTTPException(status_code=403, detail="Finance access required")
    return user


# ═══════════════════════════════════════════════════════════════════════════════
# BILLING ITEMS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/billing-items", response_model=list[BillingItemResponse])
async def list_billing_items(
    active_only: bool = True,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(BillingItem).where(BillingItem.school_id == school_id)
    if active_only:
        query = query.where(BillingItem.is_active)
    result = await db.execute(query.order_by(BillingItem.code))
    return result.scalars().all()


@router.post("/billing-items", response_model=BillingItemResponse, status_code=201)
async def create_billing_item(
    body: BillingItemCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    if body.iva_rate == Decimal("0") and not body.iva_exemption_reason:
        raise HTTPException(status_code=422, detail="iva_exemption_reason required when iva_rate is 0%")
    existing = await db.execute(
        select(BillingItem).where(BillingItem.school_id == school_id, BillingItem.code == body.code)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail=f"Code '{body.code}' already exists")
    item = BillingItem(school_id=school_id, **body.model_dump())
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.get("/billing-items/{item_id}", response_model=BillingItemResponse)
async def get_billing_item(
    item_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(BillingItem).where(BillingItem.id == item_id, BillingItem.school_id == school_id)
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Billing item not found")
    return item


@router.patch("/billing-items/{item_id}", response_model=BillingItemResponse)
async def update_billing_item(
    item_id: uuid.UUID,
    body: BillingItemUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(BillingItem).where(BillingItem.id == item_id, BillingItem.school_id == school_id)
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Billing item not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    await db.commit()
    await db.refresh(item)
    return item


# ─── Price Tables (20.17) ────────────────────────────────────────────────────

@router.get("/billing-items/{item_id}/prices", response_model=list[BillingItemPriceResponse])
async def list_item_prices(
    item_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(BillingItemPrice).where(
            BillingItemPrice.billing_item_id == item_id,
            BillingItemPrice.school_id == school_id,
        )
    )
    return result.scalars().all()


@router.post("/billing-items/prices", response_model=BillingItemPriceResponse, status_code=201)
async def set_item_price(
    body: BillingItemPriceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Upsert
    existing = await db.execute(
        select(BillingItemPrice).where(
            BillingItemPrice.billing_item_id == body.billing_item_id,
            BillingItemPrice.school_year_id == body.school_year_id,
        )
    )
    price = existing.scalar_one_or_none()
    if price:
        price.unit_price = body.unit_price
    else:
        price = BillingItemPrice(school_id=school_id, **body.model_dump())
        db.add(price)
    await db.commit()
    await db.refresh(price)
    return price


@router.post("/billing-items/prices/bulk-roll", status_code=201)
async def bulk_roll_prices(
    body: BillingItemPriceRollRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    """Copy prices from one school year to another with an optional % increase (UC-BI4)."""
    source_result = await db.execute(
        select(BillingItemPrice).where(
            BillingItemPrice.school_id == school_id,
            BillingItemPrice.school_year_id == body.from_school_year_id,
        )
    )
    source_prices = source_result.scalars().all()
    if not source_prices:
        raise HTTPException(status_code=404, detail="No prices found for source school year")

    created = 0
    updated = 0
    multiplier = Decimal("1") + body.increase_percent / Decimal("100")

    for sp in source_prices:
        new_price = (sp.unit_price * multiplier).quantize(Decimal("0.01"))
        existing = await db.execute(
            select(BillingItemPrice).where(
                BillingItemPrice.billing_item_id == sp.billing_item_id,
                BillingItemPrice.school_year_id == body.to_school_year_id,
            )
        )
        target = existing.scalar_one_or_none()
        if target:
            target.unit_price = new_price
            updated += 1
        else:
            db.add(BillingItemPrice(
                school_id=school_id,
                billing_item_id=sp.billing_item_id,
                school_year_id=body.to_school_year_id,
                unit_price=new_price,
            ))
            created += 1

    await db.commit()
    return {"created": created, "updated": updated}


# ═══════════════════════════════════════════════════════════════════════════════
# CONTRACTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/contracts", response_model=list[ContractResponse])
async def list_contracts(
    child_id: Optional[uuid.UUID] = None,
    is_active: Optional[bool] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(Contract).where(Contract.school_id == school_id)
    if child_id:
        query = query.where(Contract.child_id == child_id)
    if is_active is not None:
        query = query.where(Contract.is_active == is_active)
    result = await db.execute(query.order_by(Contract.created_at.desc()).offset(skip).limit(limit))
    contracts = result.scalars().all()

    child_ids = list({c.child_id for c in contracts})
    child_map: dict = {}
    if child_ids:
        cr = await db.execute(select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids)))
        child_map = {r.id: f"{r.first_name} {r.last_name}" for r in cr}

    return [{**c.__dict__, "child_name": child_map.get(c.child_id)} for c in contracts]


@router.post("/contracts", response_model=ContractResponse, status_code=201)
async def create_contract(
    body: ContractCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    if body.discount_percent > 0 and body.discount_amount > 0:
        raise HTTPException(status_code=422, detail="Only one of discount_percent or discount_amount may be set")
    data = body.model_dump()
    # Resolve price from billing item if not overridden
    if body.billing_item_id and body.unit_price is None:
        bi = await db.execute(
            select(BillingItem).where(BillingItem.id == body.billing_item_id, BillingItem.school_id == school_id)
        )
        item = bi.scalar_one_or_none()
        if item:
            data["unit_price"] = item.unit_price
            if not data.get("service_name"):
                data["service_name"] = item.name
            if data["iva_rate"] == Decimal("0"):
                data["iva_rate"] = item.iva_rate

    contract = Contract(school_id=school_id, **data)
    db.add(contract)
    await db.commit()
    await db.refresh(contract)
    return {**contract.__dict__, "child_name": None}


@router.get("/contracts/{contract_id}", response_model=ContractResponse)
async def get_contract(
    contract_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    return {**contract.__dict__, "child_name": None}


@router.post("/contracts/{contract_id}/generate-invoice", status_code=201)
async def generate_contract_invoice(
    contract_id: uuid.UUID,
    body: dict = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    """Generate a single invoice for a specific contract for the current month."""
    if body is None:
        body = {}
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    if not contract.is_active:
        raise HTTPException(status_code=422, detail="Contract is not active")

    today = today_luanda()
    ref_month_str = body.get("reference_month")
    ref_month = date.fromisoformat(ref_month_str) if ref_month_str else date(today.year, today.month, 1)
    due_date_str = body.get("due_date")
    due_date_val = date.fromisoformat(due_date_str) if due_date_str else None
    school_year_id_str = body.get("school_year_id")
    school_year_id_val = uuid.UUID(school_year_id_str) if school_year_id_str else None

    # Resolve guardian
    from app.models.person import ChildGuardian
    guardian_id = contract.guardian_id
    if not guardian_id:
        cg_result = await db.execute(
            select(ChildGuardian.guardian_id).where(
                ChildGuardian.child_id == contract.child_id,
                ChildGuardian.is_primary_contact == True,
            )
        )
        guardian_id = cg_result.scalar_one_or_none()
    if not guardian_id:
        raise HTTPException(status_code=422, detail="No billing guardian found for this contract")

    # Resolve price
    if contract.billing_item_id:
        unit_price = await resolve_unit_price(
            db, school_id, contract.billing_item_id, school_year_id_val, contract.unit_price,
        )
    else:
        unit_price = contract.unit_price or Decimal("0")

    # Get guardian details
    g_result = await db.execute(select(Guardian).where(Guardian.id == guardian_id))
    guardian = g_result.scalar_one_or_none()
    customer_nif = guardian.nif if guardian else None
    customer_name = f"{guardian.first_name} {guardian.last_name}" if guardian else None
    is_final_consumer = not customer_nif

    bi_name = contract.service_name or "Mensalidade"
    lines_data = [{
        "billing_item_id": str(contract.billing_item_id) if contract.billing_item_id else None,
        "description": bi_name,
        "quantity": 1,
        "unit_price": float(unit_price),
        "discount_percent": float(contract.discount_percent),
        "discount_amount": float(contract.discount_amount),
        "iva_rate": float(contract.iva_rate),
    }]

    emission = DocumentEmissionService(db, school_id)
    try:
        invoice = await emission.emit_invoice(
            document_type="FT",
            invoice_date=today,
            billing_guardian_id=guardian_id,
            customer_nif=customer_nif,
            customer_name=customer_name,
            lines=lines_data,
            child_id=contract.child_id,
            due_date=due_date_val,
            issued_by=getattr(current_user, "employee_id", None),
            school_year_id=school_year_id_val,
            reference_month=ref_month,
            description=body.get("description") or bi_name,
            is_final_consumer=is_final_consumer,
        )
        contract.last_invoiced_month = ref_month
        await db.commit()
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return {"invoice_id": str(invoice.id), "full_document_number": invoice.full_document_number}


@router.patch("/contracts/{contract_id}", response_model=ContractResponse)
async def update_contract(
    contract_id: uuid.UUID,
    body: ContractUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(contract, field, value)
    # Enforce mutual exclusivity of discount fields
    if (contract.discount_percent or 0) > 0 and (contract.discount_amount or 0) > 0:
        raise HTTPException(status_code=422, detail="Only one of discount_percent or discount_amount may be set")
    await db.commit()
    await db.refresh(contract)
    return {**contract.__dict__, "child_name": None}


@router.delete("/contracts/{contract_id}")
async def terminate_contract(
    contract_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    """Terminate a contract (spec UC-CO4): set end_date and status=terminated."""
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    if contract.status == "terminated":
        raise HTTPException(status_code=400, detail="Contract already terminated")
    contract.status = "terminated"
    contract.is_active = False
    if not contract.end_date:
        contract.end_date = today_luanda()
    await db.commit()
    return {"message": "Contract terminated"}


# ═══════════════════════════════════════════════════════════════════════════════
# INVOICES (FT / FR / ND)
# ═══════════════════════════════════════════════════════════════════════════════

async def _enrich_invoice(db: AsyncSession, invoice: Invoice) -> dict:
    """Add computed fields to invoice response."""
    amount_paid = await get_invoice_amount_paid(db, invoice.id)
    balance = await get_invoice_balance(db, invoice.id)

    # Load lines
    lines_result = await db.execute(
        select(InvoiceLine).where(InvoiceLine.invoice_id == invoice.id)
        .order_by(InvoiceLine.line_number)
    )
    lines = lines_result.scalars().all()

    child_name = None
    if invoice.child_id:
        cr = await db.execute(select(Child.first_name, Child.last_name).where(Child.id == invoice.child_id))
        row = cr.first()
        if row:
            child_name = f"{row[0]} {row[1]}"

    return InvoiceResponse(
        id=invoice.id,
        school_id=invoice.school_id,
        document_type=invoice.document_type,
        series_year=invoice.series_year,
        series_number=invoice.series_number,
        full_document_number=invoice.full_document_number,
        invoice_date=invoice.invoice_date,
        system_entry_date=invoice.system_entry_date,
        due_date=invoice.due_date,
        billing_guardian_id=invoice.billing_guardian_id,
        child_id=invoice.child_id,
        customer_nif=invoice.customer_nif,
        customer_name=invoice.customer_name,
        is_final_consumer=invoice.is_final_consumer,
        gross_total=invoice.gross_total,
        net_total=invoice.net_total,
        iva_total=invoice.iva_total,
        hash_code=invoice.hash_code,
        status=invoice.status,
        is_void=invoice.is_void,
        description=invoice.description,
        reference_month=invoice.reference_month,
        corrected_invoice_id=invoice.corrected_invoice_id,
        correction_reason=invoice.correction_reason,
        created_at=invoice.created_at,
        lines=lines,
        amount_paid=amount_paid,
        balance=balance,
        child_name=child_name,
        signature_excerpt=signature_excerpt(invoice.hash_code) if invoice.hash_code else None,
    )


@router.get("/invoices", response_model=list[InvoiceResponse])
async def list_invoices(
    skip: int = 0,
    limit: int = 50,
    child_id: Optional[uuid.UUID] = None,
    billing_guardian_id: Optional[uuid.UUID] = None,
    invoice_status: Optional[str] = None,
    document_type: Optional[str] = None,
    reference_month: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(Invoice).where(Invoice.school_id == school_id)
    if child_id:
        query = query.where(Invoice.child_id == child_id)
    if billing_guardian_id:
        query = query.where(Invoice.billing_guardian_id == billing_guardian_id)
    if invoice_status:
        query = query.where(Invoice.status == invoice_status)
    if document_type:
        query = query.where(Invoice.document_type == document_type)
    if reference_month:
        query = query.where(Invoice.reference_month == reference_month)
    result = await db.execute(
        query.order_by(Invoice.system_entry_date.desc()).offset(skip).limit(limit)
    )
    invoices = result.scalars().all()
    return [await _enrich_invoice(db, inv) for inv in invoices]


@router.post("/invoices", response_model=InvoiceResponse, status_code=201)
async def create_invoice(
    body: InvoiceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    """Create a single FT, FR, or ND document."""
    if not body.lines:
        raise HTTPException(status_code=422, detail="At least one line item is required")

    # Resolve guardian info.
    # If billing_guardian_id not supplied but child_id is, auto-resolve from the
    # child's primary contact so the invoice is always linked to a guardian.
    resolved_guardian_id = body.billing_guardian_id
    if not resolved_guardian_id and body.child_id:
        from app.models.person import ChildGuardian
        pg_r = await db.execute(
            select(ChildGuardian.guardian_id).where(
                ChildGuardian.child_id == body.child_id,
                ChildGuardian.is_primary_contact == True,
            )
        )
        resolved_guardian_id = pg_r.scalar_one_or_none()

    customer_nif = None
    customer_name = None
    is_final_consumer = False
    if resolved_guardian_id:
        g_result = await db.execute(select(Guardian).where(Guardian.id == resolved_guardian_id))
        guardian = g_result.scalar_one_or_none()
        if guardian:
            customer_nif = guardian.nif
            customer_name = f"{guardian.first_name} {guardian.last_name}"
    if not customer_nif:
        customer_nif = "999999999"
        customer_name = customer_name or "Consumidor Final"
        is_final_consumer = True

    # Resolve line details from billing items
    lines_data = []
    for line in body.lines:
        line_dict = line.model_dump()
        if line.billing_item_id:
            bi_r = await db.execute(
                select(BillingItem).where(BillingItem.id == line.billing_item_id, BillingItem.school_id == school_id)
            )
            bi = bi_r.scalar_one_or_none()
            if bi:
                if not line_dict.get("description"):
                    line_dict["description"] = bi.name
                if line_dict.get("iva_rate") is None:
                    line_dict["iva_rate"] = float(bi.iva_rate)
                if not line_dict.get("iva_exemption_reason"):
                    line_dict["iva_exemption_reason"] = bi.iva_exemption_reason
                    line_dict["iva_exemption_legend"] = bi.iva_exemption_legend
        if not line_dict.get("description"):
            line_dict["description"] = "Serviço"
        if line_dict.get("iva_rate") is None:
            line_dict["iva_rate"] = 0
        lines_data.append(line_dict)

    invoice_date = body.invoice_date or today_luanda()
    emission = DocumentEmissionService(db, school_id)

    invoice = await emission.emit_invoice(
        document_type=body.document_type,
        invoice_date=invoice_date,
        billing_guardian_id=resolved_guardian_id,
        customer_nif=customer_nif,
        customer_name=customer_name,
        lines=lines_data,
        child_id=body.child_id,
        due_date=body.due_date,
        issued_by=getattr(current_user, "employee_id", None),
        school_year_id=body.school_year_id,
        reference_month=body.reference_month,
        description=body.description,
        notes=body.notes,
        is_final_consumer=is_final_consumer,
        corrected_invoice_id=body.corrected_invoice_id,
        correction_reason=body.correction_reason,
    )

    # For FR: also create a payment immediately
    if body.document_type == "FR" and body.payment_method:
        if not resolved_guardian_id:
            raise HTTPException(status_code=422, detail="billing_guardian_id (or child with primary contact) required for FR")
        intake = PaymentIntakeService(db, school_id)
        await intake.intake(
            billing_guardian_id=resolved_guardian_id,
            amount=invoice.gross_total,
            payment_method=body.payment_method,
            payment_date=invoice_date,
            target_invoice_ids=[invoice.id],
            received_by=getattr(current_user, "employee_id", None),
            skip_receipt=True,  # FR is its own receipt
        )

    await db.commit()
    await db.refresh(invoice)
    return await _enrich_invoice(db, invoice)


@router.get("/invoices/{invoice_id}", response_model=InvoiceResponse)
async def get_invoice(
    invoice_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    return await _enrich_invoice(db, invoice)


@router.post("/invoices/bulk", status_code=201)
async def bulk_create_invoices(
    body: InvoiceBulkCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    """Auto-generate invoices from active contracts for a reference month."""
    from app.models.person import ChildGuardian

    today = today_luanda()
    ref_month = body.reference_month
    emission = DocumentEmissionService(db, school_id)

    contracts_result = await db.execute(
        select(Contract).where(
            Contract.school_id == school_id,
            Contract.is_active == True,
            Contract.status == "active",
            Contract.auto_invoice == True,
            Contract.start_date <= ref_month,
        )
    )
    contracts = contracts_result.scalars().all()

    created = []
    warnings = []

    for contract in contracts:
        # Skip if already invoiced
        if contract.last_invoiced_month and contract.last_invoiced_month >= ref_month:
            continue
        if contract.end_date and contract.end_date < today:
            continue

        # Resolve guardian
        guardian_id = contract.guardian_id
        if not guardian_id:
            cg_result = await db.execute(
                select(ChildGuardian.guardian_id).where(
                    ChildGuardian.child_id == contract.child_id,
                    ChildGuardian.is_primary_contact == True,
                )
            )
            guardian_id = cg_result.scalar_one_or_none()

        if not guardian_id:
            cr = await db.execute(select(Child.first_name, Child.last_name).where(Child.id == contract.child_id))
            row = cr.first()
            warnings.append({
                "child_id": str(contract.child_id),
                "child_name": f"{row[0]} {row[1]}" if row else "Unknown",
                "reason": "No billing guardian",
            })
            continue

        # Resolve price
        if contract.billing_item_id:
            unit_price = await resolve_unit_price(
                db, school_id,
                contract.billing_item_id,
                body.school_year_id,
                contract.unit_price,
            )
        else:
            unit_price = contract.unit_price or Decimal("0")

        # Get guardian NIF
        g_result = await db.execute(select(Guardian).where(Guardian.id == guardian_id))
        guardian = g_result.scalar_one_or_none()
        customer_nif = guardian.nif if guardian else None
        customer_name = f"{guardian.first_name} {guardian.last_name}" if guardian else None
        is_final_consumer = not customer_nif
        if is_final_consumer:
            customer_nif = "999999999"
            customer_name = customer_name or "Consumidor Final"

        # Build line
        bi_name = contract.service_name or "Mensalidade"
        lines_data = [{
            "billing_item_id": str(contract.billing_item_id) if contract.billing_item_id else None,
            "description": bi_name,
            "quantity": 1,
            "unit_price": float(unit_price),
            "discount_percent": float(contract.discount_percent),
            "discount_amount": float(contract.discount_amount),
            "iva_rate": float(contract.iva_rate),
        }]

        try:
            invoice = await emission.emit_invoice(
                document_type="FT",
                invoice_date=today,
                billing_guardian_id=guardian_id,
                customer_nif=customer_nif,
                customer_name=customer_name,
                lines=lines_data,
                child_id=contract.child_id,
                due_date=body.due_date,
                issued_by=getattr(current_user, "employee_id", None),
                school_year_id=body.school_year_id,
                reference_month=ref_month,
                description=body.description or bi_name,
                is_final_consumer=is_final_consumer,
            )
            contract.last_invoiced_month = ref_month
            created.append(invoice)
        except Exception as e:
            warnings.append({
                "child_id": str(contract.child_id),
                "reason": str(e),
            })

    await db.commit()
    return {
        "created": len(created),
        "warnings": warnings,
        "invoice_ids": [str(inv.id) for inv in created],
    }


# ═══════════════════════════════════════════════════════════════════════════════
# CREDIT NOTES (NC)
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/invoices/{invoice_id}/void")
async def void_invoice(
    invoice_id: uuid.UUID,
    body: dict,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    """Full-void an invoice by emitting a credit note for the entire amount."""
    reason = (body.get("reason") or "").strip()
    if not reason:
        raise HTTPException(status_code=422, detail="reason is required to void an invoice")

    emission = DocumentEmissionService(db, school_id)
    try:
        cn = await emission.emit_credit_note(
            invoice_id=invoice_id,
            reason=reason,
            lines=[],  # empty = full void
            issued_by=getattr(current_user, "employee_id", None),
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=getattr(current_user, "id", uuid.uuid4()),
        entity_type="invoice",
        entity_id=invoice_id,
        action="void",
        reason=reason,
    )
    db.add(audit)
    await db.commit()
    return {"message": "Invoice voided", "credit_note_id": str(cn.id)}


@router.post("/credit-notes", response_model=CreditNoteResponse, status_code=201)
async def create_credit_note(
    body: CreditNoteCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    emission = DocumentEmissionService(db, school_id)
    try:
        cn = await emission.emit_credit_note(
            invoice_id=body.invoice_id,
            reason=body.reason,
            lines=body.lines,
            issued_by=getattr(current_user, "employee_id", None),
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Audit
    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=getattr(current_user, "id", uuid.uuid4()),
        entity_type="credit_note",
        entity_id=cn.id,
        action="issue_nc",
        reason=body.reason,
    )
    db.add(audit)
    await db.commit()
    await db.refresh(cn)
    return cn


@router.get("/credit-notes", response_model=list[CreditNoteResponse])
async def list_credit_notes(
    skip: int = 0, limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(CreditNote).where(CreditNote.school_id == school_id)
        .order_by(CreditNote.system_entry_date.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.get("/credit-notes/{cn_id}", response_model=CreditNoteResponse)
async def get_credit_note(
    cn_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(CreditNote).where(CreditNote.id == cn_id, CreditNote.school_id == school_id)
    )
    cn = result.scalar_one_or_none()
    if cn is None:
        raise HTTPException(status_code=404, detail="Credit note not found")
    return cn


# ═══════════════════════════════════════════════════════════════════════════════
# PAYMENTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/payments", response_model=list[PaymentResponse])
async def list_payments(
    skip: int = 0, limit: int = 50,
    billing_guardian_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    status: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(Payment).where(Payment.school_id == school_id)
    if billing_guardian_id:
        query = query.where(Payment.billing_guardian_id == billing_guardian_id)
    if date_from:
        query = query.where(Payment.payment_date >= date_from)
    if date_to:
        query = query.where(Payment.payment_date <= date_to)
    if status:
        query = query.where(Payment.status == status)
    result = await db.execute(query.order_by(Payment.created_at.desc()).offset(skip).limit(limit))
    payments = result.scalars().all()

    output = []
    for p in payments:
        alloc_r = await db.execute(
            select(PaymentAllocation).where(PaymentAllocation.payment_id == p.id)
        )
        allocs = alloc_r.scalars().all()
        data = PaymentResponse.model_validate(p)
        data.allocated_invoices = [
            {"invoice_id": str(a.invoice_id), "amount_applied": float(a.amount_applied)}
            for a in allocs
        ]
        output.append(data)
    return output


@router.get("/payments/{payment_id}", response_model=PaymentResponse)
async def get_payment(
    payment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    p = result.scalar_one_or_none()
    if p is None:
        raise HTTPException(status_code=404, detail="Payment not found")
    alloc_r = await db.execute(
        select(PaymentAllocation).where(PaymentAllocation.payment_id == p.id)
    )
    allocs = alloc_r.scalars().all()
    data = PaymentResponse.model_validate(p)
    data.allocated_invoices = [
        {"invoice_id": str(a.invoice_id), "amount_applied": float(a.amount_applied)}
        for a in allocs
    ]
    return data


@router.post("/payments", response_model=PaymentResponse, status_code=201)
async def create_payment(
    body: PaymentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    intake = PaymentIntakeService(db, school_id)
    try:
        payment = await intake.intake(
            billing_guardian_id=body.billing_guardian_id,
            amount=body.amount,
            payment_method=body.payment_method,
            payment_date=body.payment_date or today_luanda(),
            target_invoice_ids=body.target_invoice_ids,
            payment_reference_id=body.payment_reference_id,
            received_by=body.received_by or getattr(current_user, "employee_id", None),
            idempotency_key=body.idempotency_key,
            notes=body.notes,
            receipt_proof_url=body.receipt_proof_url,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    await db.commit()
    await db.refresh(payment)

    alloc_r = await db.execute(
        select(PaymentAllocation).where(PaymentAllocation.payment_id == payment.id)
    )
    allocs = alloc_r.scalars().all()
    data = PaymentResponse.model_validate(payment)
    data.allocated_invoices = [
        {"invoice_id": str(a.invoice_id), "amount_applied": float(a.amount_applied)}
        for a in allocs
    ]
    return data


@router.post("/payments/{payment_id}/approve", response_model=PaymentResponse)
async def approve_payment(
    payment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Approve a parent-submitted payment proof: status -> normal, recalculate invoices."""
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment not found")
    if payment.status != "pending_review":
        raise HTTPException(status_code=400, detail="Payment is not pending review")

    payment.status = "normal"
    await db.flush()

    # Recalculate all invoices linked to this payment
    alloc_result = await db.execute(
        select(PaymentAllocation).where(PaymentAllocation.payment_id == payment_id)
    )
    for alloc in alloc_result.scalars().all():
        await recalculate_invoice_status(db, alloc.invoice_id)

    await db.commit()
    await db.refresh(payment)
    alloc_r = await db.execute(
        select(PaymentAllocation).where(PaymentAllocation.payment_id == payment.id)
    )
    allocs = alloc_r.scalars().all()
    data = PaymentResponse.model_validate(payment)
    data.allocated_invoices = [
        {"invoice_id": str(a.invoice_id), "amount_applied": float(a.amount_applied)}
        for a in allocs
    ]
    return data


@router.post("/payments/{payment_id}/reject")
async def reject_payment(
    payment_id: uuid.UUID,
    body: dict = {},
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Reject a parent-submitted payment proof."""
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment not found")
    if payment.status != "pending_review":
        raise HTTPException(status_code=400, detail="Payment is not pending review")

    payment.status = "rejected"
    if body.get("reason"):
        payment.notes = f"[REJEITADO] {body['reason']}"
    await db.commit()
    return {"message": "Comprovativo rejeitado"}


@router.post("/payments/{payment_id}/reverse", response_model=PaymentResponse)
async def reverse_payment_endpoint(
    payment_id: uuid.UUID,
    body: dict,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    reason = body.get("reason", "Reversed")
    actor_id = getattr(current_user, "id", uuid.uuid4())
    try:
        payment = await reverse_payment(db, school_id, payment_id, reason, actor_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    await db.commit()
    await db.refresh(payment)
    return PaymentResponse.model_validate(payment)


@router.delete("/payments/{payment_id}")
async def delete_payment(payment_id: uuid.UUID, _=Depends(require_school_admin)):
    raise HTTPException(status_code=405, detail="Use /reverse instead")


# ═══════════════════════════════════════════════════════════════════════════════
# RECEIPTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/receipts", response_model=list[ReceiptResponse])
async def list_receipts(
    skip: int = 0, limit: int = 50,
    payment_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(Receipt).where(Receipt.school_id == school_id)
    if payment_id:
        query = query.where(Receipt.payment_id == payment_id)
    result = await db.execute(query.order_by(Receipt.system_entry_date.desc()).offset(skip).limit(limit))
    return result.scalars().all()


# ═══════════════════════════════════════════════════════════════════════════════
# PAYMENT REFERENCES (20.11)
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/payment-references", response_model=list[PaymentReferenceResponse])
async def list_payment_references(
    status_filter: Optional[str] = None,
    billing_guardian_id: Optional[uuid.UUID] = None,
    invoice_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(PaymentReference).where(PaymentReference.school_id == school_id)
    if status_filter:
        query = query.where(PaymentReference.status == status_filter)
    if billing_guardian_id:
        query = query.where(PaymentReference.billing_guardian_id == billing_guardian_id)
    if invoice_id:
        query = query.where(PaymentReference.invoice_id == invoice_id)
    result = await db.execute(query.order_by(PaymentReference.created_at.desc()))
    return result.scalars().all()


@router.post("/payment-references", response_model=PaymentReferenceResponse, status_code=201)
async def create_payment_reference(
    body: PaymentReferenceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    # Check: at most one active reference per invoice
    if body.invoice_id:
        existing = await db.execute(
            select(PaymentReference).where(
                PaymentReference.invoice_id == body.invoice_id,
                PaymentReference.status == "active",
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="An active reference already exists for this invoice")

    ref = PaymentReference(
        school_id=school_id,
        created_by=getattr(current_user, "employee_id", None),
        **body.model_dump(),
    )
    db.add(ref)
    await db.commit()
    await db.refresh(ref)
    return ref


@router.post("/payment-references/{ref_id}/mark-paid", response_model=PaymentResponse)
async def mark_reference_paid(
    ref_id: uuid.UUID,
    body: PaymentReferenceMarkPaid,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    """Manual-mode intake: admin marks a reference as paid."""
    result = await db.execute(
        select(PaymentReference).where(PaymentReference.id == ref_id, PaymentReference.school_id == school_id)
    )
    ref = result.scalar_one_or_none()
    if ref is None:
        raise HTTPException(status_code=404, detail="Reference not found")

    intake = PaymentIntakeService(db, school_id)
    try:
        payment = await intake.intake(
            billing_guardian_id=ref.billing_guardian_id,
            amount=body.amount,
            payment_method=body.payment_method,
            payment_date=(body.paid_at or now_luanda()).date() if body.paid_at else today_luanda(),
            target_invoice_ids=[ref.invoice_id] if ref.invoice_id else None,
            payment_reference_id=ref.id,
            received_by=getattr(current_user, "employee_id", None),
            notes=body.notes,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    await db.commit()
    await db.refresh(payment)
    return PaymentResponse.model_validate(payment)


@router.post("/payment-references/{ref_id}/cancel")
async def cancel_payment_reference(
    ref_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(PaymentReference).where(PaymentReference.id == ref_id, PaymentReference.school_id == school_id)
    )
    ref = result.scalar_one_or_none()
    if ref is None:
        raise HTTPException(status_code=404, detail="Reference not found")
    if ref.status != "active":
        raise HTTPException(status_code=400, detail=f"Cannot cancel reference in status '{ref.status}'")
    ref.status = "cancelled"
    await db.commit()
    return {"message": "Reference cancelled"}


# ═══════════════════════════════════════════════════════════════════════════════
# CREDIT BALANCES (20.12)
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/credits", response_model=list[GuardianCreditSummary])
async def list_guardians_with_credit(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """List all guardians with a non-zero credit balance (UC-CB4)."""
    rows = await get_guardians_with_credit(db, school_id)
    return rows


@router.get("/credits/{guardian_id}")
async def get_guardian_credits(
    guardian_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    balance = await get_guardian_credit_balance(db, school_id, guardian_id)
    entries_result = await db.execute(
        select(CreditEntry).where(
            CreditEntry.school_id == school_id,
            CreditEntry.billing_guardian_id == guardian_id,
        ).order_by(CreditEntry.created_at.desc())
    )
    entries = entries_result.scalars().all()
    return {
        "balance": balance,
        "entries": [CreditEntryResponse.model_validate(e) for e in entries],
    }


@router.post("/credits/apply")
async def apply_credit(
    body: CreditApplyRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    # Determine guardian from invoice
    inv_result = await db.execute(select(Invoice).where(Invoice.id == body.invoice_id))
    inv = inv_result.scalar_one_or_none()
    if inv is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if not inv.billing_guardian_id:
        raise HTTPException(status_code=400, detail="Invoice has no billing guardian")

    try:
        payment = await apply_credit_to_invoice(
            db, school_id, inv.billing_guardian_id, body.invoice_id, body.amount,
            actor_id=getattr(current_user, "id", uuid.uuid4()),
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    await db.commit()
    return {"message": "Credit applied", "payment_id": str(payment.id)}


@router.post("/credits/{guardian_id}/refund")
async def refund_credit(
    guardian_id: uuid.UUID,
    body: CreditRefundRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    """Refund credit balance to guardian (spec UC-CB3)."""
    balance = await get_guardian_credit_balance(db, school_id, guardian_id)
    if body.amount > balance:
        raise HTTPException(status_code=400, detail=f"Insufficient credit balance: {balance} available")

    # Consume credit entries FIFO
    entries_result = await db.execute(
        select(CreditEntry).where(
            CreditEntry.school_id == school_id,
            CreditEntry.billing_guardian_id == guardian_id,
            CreditEntry.is_reversed == False,
            CreditEntry.amount_remaining > 0,
        ).order_by(CreditEntry.created_at.asc())
    )
    entries = entries_result.scalars().all()
    remaining = body.amount
    for entry in entries:
        if remaining <= 0:
            break
        consume = min(entry.amount_remaining, remaining)
        entry.amount_remaining -= consume
        remaining -= consume

    refund = CreditRefund(
        school_id=school_id,
        billing_guardian_id=guardian_id,
        amount=body.amount,
        method=body.method,
        reference=body.reference,
        authorised_by=getattr(current_user, "employee_id", current_user.id),
    )
    db.add(refund)

    # Audit
    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=getattr(current_user, "id", uuid.uuid4()),
        entity_type="credit_entry",
        entity_id=guardian_id,
        action="refund",
        after_snapshot={"amount": float(body.amount), "method": body.method},
    )
    db.add(audit)
    await db.commit()
    return {"message": "Credit refunded", "refund_id": str(refund.id)}


# ═══════════════════════════════════════════════════════════════════════════════
# CASH SESSIONS (20.14)
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/cash-sessions", response_model=list[CashSessionResponse])
async def list_cash_sessions(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(CashSession).where(CashSession.school_id == school_id)
        .order_by(CashSession.opened_at.desc()).limit(50)
    )
    return result.scalars().all()


@router.post("/cash-sessions/open", response_model=CashSessionResponse, status_code=201)
async def open_cash_session(
    body: CashSessionOpen,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    # Check no open session exists
    existing = await db.execute(
        select(CashSession).where(CashSession.school_id == school_id, CashSession.status == "open")
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="A cash session is already open")

    session = CashSession(
        school_id=school_id,
        opened_by=getattr(current_user, "employee_id", current_user.id),
        opened_at=now_luanda(),
        opening_float=body.opening_float,
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session


@router.post("/cash-sessions/{session_id}/close", response_model=CashSessionResponse)
async def close_cash_session(
    session_id: uuid.UUID,
    body: CashSessionClose,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    result = await db.execute(
        select(CashSession).where(CashSession.id == session_id, CashSession.school_id == school_id)
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=404, detail="Cash session not found")
    if session.status == "closed":
        raise HTTPException(status_code=400, detail="Session already closed")

    # Calculate expected amounts from payments in this session
    pay_result = await db.execute(
        select(Payment.payment_method, func.sum(Payment.amount))
        .where(Payment.cash_session_id == session_id, Payment.status == "normal")
        .group_by(Payment.payment_method)
    )
    expected = {row[0]: float(row[1]) for row in pay_result.all()}

    # Compute variance
    counted_total = sum(body.counted_by_method.values())
    expected_total = sum(expected.values()) + float(session.opening_float)
    variance = Decimal(str(counted_total)) - Decimal(str(expected_total))

    session.closed_by = getattr(current_user, "employee_id", current_user.id)
    session.closed_at = now_luanda()
    session.expected_by_method = expected
    session.counted_by_method = body.counted_by_method
    session.variance = variance
    session.variance_reason = body.variance_reason
    session.status = "closed"

    if variance != 0:
        audit = FinanceAuditEntry(
            school_id=school_id,
            actor_id=getattr(current_user, "id", uuid.uuid4()),
            entity_type="cash_session",
            entity_id=session_id,
            action="close_with_variance",
            reason=body.variance_reason,
            after_snapshot={
                "variance": float(variance),
                "counted": body.counted_by_method,
                "expected": expected,
            },
        )
        db.add(audit)

    await db.commit()
    await db.refresh(session)
    return session


@router.post("/cash-sessions/{session_id}/reopen", response_model=CashSessionResponse)
async def reopen_cash_session(
    session_id: uuid.UUID,
    body: dict,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    """Reopen a closed cash session (UC-CS5). school_admin only; mandatory reason."""
    reason = body.get("reason", "").strip()
    if not reason:
        raise HTTPException(status_code=422, detail="reason is required to reopen a cash session")

    result = await db.execute(
        select(CashSession).where(CashSession.id == session_id, CashSession.school_id == school_id)
    )
    session = result.scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=404, detail="Cash session not found")
    if session.status == "open":
        raise HTTPException(status_code=400, detail="Session is already open")

    # Ensure no other session is currently open
    other = await db.execute(
        select(CashSession.id).where(
            CashSession.school_id == school_id,
            CashSession.status == "open",
            CashSession.id != session_id,
        )
    )
    if other.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Another cash session is already open")

    session.status = "open"
    session.closed_at = None
    session.closed_by = None

    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=getattr(current_user, "id", uuid.uuid4()),
        entity_type="cash_session",
        entity_id=session_id,
        action="reopen",
        reason=reason,
    )
    db.add(audit)
    await db.commit()
    await db.refresh(session)
    return session


# ═══════════════════════════════════════════════════════════════════════════════
# PAYMENT PLANS (20.15)
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/payment-plans", response_model=list[PaymentPlanResponse])
async def list_payment_plans(
    status_filter: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(PaymentPlan).where(PaymentPlan.school_id == school_id)
    if status_filter:
        query = query.where(PaymentPlan.status == status_filter)
    result = await db.execute(query.order_by(PaymentPlan.created_at.desc()))
    plans = result.scalars().all()
    output = []
    for plan in plans:
        inst_r = await db.execute(
            select(PaymentPlanInstallment).where(PaymentPlanInstallment.plan_id == plan.id)
            .order_by(PaymentPlanInstallment.due_date)
        )
        installments = [
            {"id": str(i.id), "due_date": str(i.due_date), "amount": float(i.amount), "status": i.status}
            for i in inst_r.scalars().all()
        ]
        data = PaymentPlanResponse.model_validate(plan)
        data.installments = installments
        output.append(data)
    return output


@router.post("/payment-plans", response_model=PaymentPlanResponse, status_code=201)
async def create_payment_plan(
    body: PaymentPlanCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    # Validate installment totals equal covered invoice balances
    total_balance = Decimal("0")
    for inv_id in body.invoice_ids:
        bal = await get_invoice_balance(db, inv_id)
        total_balance += bal

    installment_total = sum(i.amount for i in body.installments)
    if abs(installment_total - total_balance) > Decimal("0.01"):
        raise HTTPException(
            status_code=422,
            detail=f"Installment total ({installment_total}) must equal invoice balance ({total_balance})"
        )

    plan = PaymentPlan(
        school_id=school_id,
        billing_guardian_id=body.billing_guardian_id,
        invoice_ids=[str(i) for i in body.invoice_ids],
        total_amount=total_balance,
        created_by=getattr(current_user, "employee_id", current_user.id),
        notes=body.notes,
    )
    db.add(plan)
    await db.flush()

    for inst in body.installments:
        db.add(PaymentPlanInstallment(
            plan_id=plan.id,
            due_date=inst.due_date,
            amount=inst.amount,
        ))

    await db.commit()
    await db.refresh(plan)
    return PaymentPlanResponse.model_validate(plan)


# ═══════════════════════════════════════════════════════════════════════════════
# DUNNING (20.16)
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/reminders", response_model=ReminderResponse, status_code=201)
async def create_reminder(
    body: ReminderCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_finance_access),
):
    reminder = ReminderLog(
        school_id=school_id,
        billing_guardian_id=body.billing_guardian_id,
        invoice_ids=[str(i) for i in body.invoice_ids],
        level=body.level,
        channel=body.channel,
        sent_by=getattr(current_user, "employee_id", current_user.id),
        sent_at=now_luanda(),
        message_snapshot=body.message_snapshot,
    )
    db.add(reminder)
    await db.commit()
    await db.refresh(reminder)
    return reminder


@router.get("/reminders", response_model=list[ReminderResponse])
async def list_reminders(
    billing_guardian_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    query = select(ReminderLog).where(ReminderLog.school_id == school_id)
    if billing_guardian_id:
        query = query.where(ReminderLog.billing_guardian_id == billing_guardian_id)
    result = await db.execute(query.order_by(ReminderLog.sent_at.desc()).limit(100))
    return result.scalars().all()


# ═══════════════════════════════════════════════════════════════════════════════
# PARENT PORTAL
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/parent/invoices", response_model=List[ParentInvoiceResponse])
async def list_parent_invoices(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="No guardian linked")

    # Collect all child IDs linked to this guardian so invoices created via
    # child selection (without explicit billing_guardian_id) are also visible.
    from app.models.person import ChildGuardian
    child_ids_r = await db.execute(
        select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
    )
    linked_child_ids = [row[0] for row in child_ids_r.all()]

    # Invoices where this guardian is the direct billing guardian OR where the
    # invoice belongs to one of the guardian's children (handles legacy/admin-created invoices).
    inv_filter = or_(
        Invoice.billing_guardian_id == guardian_id,
        Invoice.child_id.in_(linked_child_ids) if linked_child_ids else False,
    )
    inv_result = await db.execute(
        select(Invoice).where(inv_filter)
        .order_by(Invoice.invoice_date.desc())
    )
    invoices = inv_result.scalars().all()

    # Fetch active Multicaixa payment references for all these invoices in one query
    invoice_ids = [inv.id for inv in invoices]
    mcx_refs: dict[uuid.UUID, PaymentReference] = {}
    if invoice_ids:
        mcx_r = await db.execute(
            select(PaymentReference).where(
                PaymentReference.invoice_id.in_(invoice_ids),
                PaymentReference.status == "active",
            )
        )
        for ref in mcx_r.scalars().all():
            if ref.invoice_id not in mcx_refs:
                mcx_refs[ref.invoice_id] = ref

    # Fetch child names in bulk
    child_ids_needed = list({inv.child_id for inv in invoices if inv.child_id})
    child_name_map: dict[uuid.UUID, str] = {}
    if child_ids_needed:
        cn_r = await db.execute(
            select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids_needed))
        )
        child_name_map = {row[0]: f"{row[1]} {row[2]}" for row in cn_r.all()}

    output = []
    for inv in invoices:
        amount_paid = await get_invoice_amount_paid(db, inv.id)
        balance = await get_invoice_balance(db, inv.id)
        child_name = child_name_map.get(inv.child_id, "—") if inv.child_id else "—"
        ref = mcx_refs.get(inv.id)
        output.append(ParentInvoiceResponse(
            id=inv.id,
            child_id=inv.child_id,
            child_name=child_name,
            document_type=inv.document_type,
            full_document_number=inv.full_document_number,
            reference_month=inv.reference_month,
            gross_total=inv.gross_total,
            status=inv.status,
            due_date=inv.due_date,
            amount_paid=amount_paid,
            balance=balance,
            multicaixa_entity=ref.entity if ref else None,
            multicaixa_ref=ref.reference if ref else None,
        ))
    return output


@router.get("/parent/statement", response_model=AccountStatementResponse)
async def parent_account_statement(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="No guardian linked")
    school_id = getattr(current_user, "_school_id", None)
    if not school_id:
        raise HTTPException(status_code=403, detail="School context required")
    stmt = await get_account_statement(db, school_id, guardian_id)
    return stmt


@router.get("/parent/credits")
async def parent_credit_balance(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    """Parent views their own credit balance (spec UC-CB5)."""
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="No guardian linked")
    school_id = getattr(current_user, "_school_id", None)
    if not school_id:
        raise HTTPException(status_code=403, detail="School context required")
    balance = await get_guardian_credit_balance(db, school_id, guardian_id)
    entries_result = await db.execute(
        select(CreditEntry).where(
            CreditEntry.school_id == school_id,
            CreditEntry.billing_guardian_id == guardian_id,
        ).order_by(CreditEntry.created_at.desc())
    )
    entries = entries_result.scalars().all()
    return {
        "balance": balance,
        "entries": [CreditEntryResponse.model_validate(e) for e in entries],
    }


@router.get("/parent/payment-references", response_model=list[PaymentReferenceResponse])
async def parent_payment_references(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    """Parent views their active payment references (Multicaixa entities/refs)."""
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="No guardian linked")
    result = await db.execute(
        select(PaymentReference).where(
            PaymentReference.billing_guardian_id == guardian_id,
            PaymentReference.status == "active",
        ).order_by(PaymentReference.created_at.desc())
    )
    return result.scalars().all()


@router.post("/parent/submit-payment", status_code=201)
async def parent_submit_payment(
    body: dict,
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    """Parent submits proof of payment for review."""
    from app.models.person import ChildGuardian

    guardian_id = getattr(current_user, "guardian_id", None)
    if not guardian_id:
        raise HTTPException(status_code=403, detail="No guardian linked")

    invoice_id = body.get("invoice_id")
    if not invoice_id:
        raise HTTPException(status_code=422, detail="invoice_id required")

    receipt_proof_url = body.get("receipt_proof_url")

    # Verify invoice belongs to this guardian (direct billing or via child linkage)
    inv_result = await db.execute(
        select(Invoice).where(Invoice.id == uuid.UUID(invoice_id))
    )
    invoice = inv_result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")

    is_billing_guardian = invoice.billing_guardian_id and str(invoice.billing_guardian_id) == str(guardian_id)
    if not is_billing_guardian:
        # Check if invoice belongs to one of this guardian's children
        child_ids_r = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        linked_child_ids = [str(r[0]) for r in child_ids_r.all()]
        if not invoice.child_id or str(invoice.child_id) not in linked_child_ids:
            raise HTTPException(status_code=403, detail="Not your invoice")

    # Create a pending-review payment
    amount = Decimal(str(body.get("amount", invoice.gross_total)))
    payment = Payment(
        school_id=invoice.school_id,
        billing_guardian_id=guardian_id,
        payment_date=today_luanda(),
        amount=amount,
        payment_method=body.get("payment_method", "multicaixa"),
        receipt_proof_url=receipt_proof_url,
        notes=body.get("notes") or "Submetido pelo encarregado",
        status="pending_review",
    )
    db.add(payment)
    await db.flush()  # get payment.id before allocation

    # Link payment to the specific invoice via allocation so admin can match it
    allocation = PaymentAllocation(
        payment_id=payment.id,
        invoice_id=invoice.id,
        amount_applied=amount,
    )
    db.add(allocation)

    await db.commit()
    await db.refresh(payment)
    return {"message": "Comprovativo submetido com sucesso", "payment_id": str(payment.id)}


@router.post("/payment-proof")
async def upload_payment_proof(
    file: UploadFile = File(...),
    school_id: uuid.UUID = Depends(get_school_id),
    _=Depends(get_current_user),
):
    url = await save_upload(file, "payment-proofs", uuid.uuid4())
    return {"url": url}


# ═══════════════════════════════════════════════════════════════════════════════
# REPORTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/dashboard")
async def finance_dashboard(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    today = today_luanda()
    month_start = date(today.year, today.month, 1)

    revenue_r = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0))
        .where(Payment.school_id == school_id, Payment.status == "normal",
               Payment.payment_date >= month_start)
    )
    total_revenue = float(revenue_r.scalar())

    expense_r = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), 0))
        .where(Expense.school_id == school_id, Expense.is_voided == False,
               Expense.expense_date >= month_start)
    )
    total_expenses = float(expense_r.scalar())

    pending_r = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "pending")
    )
    overdue_r = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "overdue")
    )
    outstanding_r = await db.execute(
        select(func.coalesce(func.sum(Invoice.gross_total), 0))
        .where(Invoice.school_id == school_id, Invoice.status.in_(["pending", "overdue", "partially_paid"]))
    )

    # Credit balance total
    credit_r = await db.execute(
        select(func.coalesce(func.sum(CreditEntry.amount_remaining), 0))
        .where(CreditEntry.school_id == school_id, CreditEntry.is_reversed == False)
    )

    # Open cash session
    session_r = await db.execute(
        select(CashSession.id).where(CashSession.school_id == school_id, CashSession.status == "open")
    )

    # Invoices generated this month (count and amount)
    inv_gen_r = await db.execute(
        select(func.count(Invoice.id), func.coalesce(func.sum(Invoice.gross_total), 0))
        .where(
            Invoice.school_id == school_id,
            Invoice.invoice_date >= month_start,
            Invoice.is_void == False,
            Invoice.document_type.in_(["FT", "FR", "ND"]),
        )
    )
    inv_gen_row = inv_gen_r.first()
    invoices_generated_count = inv_gen_row[0] if inv_gen_row else 0
    invoices_generated_amount = float(inv_gen_row[1]) if inv_gen_row else 0.0
    collection_rate = round(
        (total_revenue / invoices_generated_amount * 100) if invoices_generated_amount > 0 else 0.0, 2
    )

    return {
        "total_revenue_month": total_revenue,
        "total_expenses_month": total_expenses,
        "pending_invoices_count": pending_r.scalar(),
        "overdue_invoices_count": overdue_r.scalar(),
        "total_outstanding": float(outstanding_r.scalar()),
        "total_credit_balance": float(credit_r.scalar()),
        "has_open_cash_session": session_r.scalar_one_or_none() is not None,
        "invoices_generated_count": invoices_generated_count,
        "invoices_generated_amount": invoices_generated_amount,
        "collection_rate": collection_rate,
    }


@router.get("/summary")
async def finance_summary(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    # Alias to dashboard for backward compat
    return await finance_dashboard(school_id=school_id, db=db, _=_)


@router.get("/reports/pl")
async def profit_and_loss(
    year: Optional[int] = None,
    month: Optional[int] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    effective_year = year or today_luanda().year
    if month:
        return await generate_monthly_pl(db, school_id, effective_year, month)
    return await generate_annual_pl(db, school_id, effective_year)


@router.get("/reports/outstanding", response_model=list[OutstandingInvoice])
async def outstanding_report(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    await mark_overdue_invoices(db, school_id)
    await db.flush()
    return await get_outstanding_invoices(db, school_id)


@router.get("/reports/delinquent")
async def delinquent_report(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    """Delinquency report grouped by guardian with aging buckets (0-30, 31-60, 61-90, 90+ days)."""
    today = today_luanda()
    await mark_overdue_invoices(db, school_id)

    result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["overdue", "partially_paid"]),
            Invoice.is_void == False,
            Invoice.due_date < today,
        ).order_by(Invoice.billing_guardian_id, Invoice.due_date.asc())
    )
    invoices = result.scalars().all()

    # Group by guardian
    from collections import defaultdict
    guardian_map: dict = defaultdict(lambda: {
        "guardian_id": None,
        "guardian_name": None,
        "bucket_0_30": Decimal("0"),
        "bucket_31_60": Decimal("0"),
        "bucket_61_90": Decimal("0"),
        "bucket_90_plus": Decimal("0"),
        "total_overdue": Decimal("0"),
        "invoice_count": 0,
    })

    for inv in invoices:
        days = (today - inv.due_date).days if inv.due_date else 0
        balance = await get_invoice_balance(db, inv.id)
        if balance <= 0:
            continue
        gid = str(inv.billing_guardian_id) if inv.billing_guardian_id else inv.customer_nif or "unknown"
        entry = guardian_map[gid]
        entry["guardian_id"] = str(inv.billing_guardian_id) if inv.billing_guardian_id else None
        entry["guardian_name"] = inv.customer_name
        entry["invoice_count"] += 1
        entry["total_overdue"] += balance
        if days <= 30:
            entry["bucket_0_30"] += balance
        elif days <= 60:
            entry["bucket_31_60"] += balance
        elif days <= 90:
            entry["bucket_61_90"] += balance
        else:
            entry["bucket_90_plus"] += balance

    output = sorted(
        [
            {**v, "total_overdue": float(v["total_overdue"]),
             "bucket_0_30": float(v["bucket_0_30"]),
             "bucket_31_60": float(v["bucket_31_60"]),
             "bucket_61_90": float(v["bucket_61_90"]),
             "bucket_90_plus": float(v["bucket_90_plus"])}
            for v in guardian_map.values()
            if v["total_overdue"] > 0
        ],
        key=lambda x: x["total_overdue"],
        reverse=True,
    )
    return output


@router.get("/reports/cash-flow", response_model=list[CashFlowMonth])
async def cash_flow_report(
    year: Optional[int] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    import calendar
    effective_year = year or today_luanda().year
    months = []
    for month in range(1, 13):
        start = date(effective_year, month, 1)
        end = date(effective_year, month, calendar.monthrange(effective_year, month)[1])
        inflow_r = await db.execute(
            select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
            .where(Payment.school_id == school_id, Payment.status == "normal",
                   Payment.payment_date >= start, Payment.payment_date <= end)
        )
        outflow_r = await db.execute(
            select(func.coalesce(func.sum(Expense.amount), Decimal("0")))
            .where(Expense.school_id == school_id, Expense.is_voided == False,
                   Expense.expense_date >= start, Expense.expense_date <= end)
        )
        inflows = inflow_r.scalar_one()
        outflows = outflow_r.scalar_one()
        months.append(CashFlowMonth(year=effective_year, month=month, inflows=inflows, outflows=outflows, net=inflows - outflows))
    return months


@router.get("/reports/statement/{guardian_id}", response_model=AccountStatementResponse)
async def account_statement(
    guardian_id: uuid.UUID,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    return await get_account_statement(db, school_id, guardian_id, from_date, to_date)


# ─── SAF-T Export ────────────────────────────────────────────────────────────

@router.get("/reports/saft")
async def saft_export(
    year: Optional[int] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.school import School
    from app.utils.agt import format_gross_total, signature_excerpt

    school_r = await db.execute(select(School).where(School.id == school_id))
    school = school_r.scalar_one_or_none()
    if not school:
        raise HTTPException(status_code=404, detail="School not found")

    today = today_luanda()
    if year:
        from_date = date(year, 1, 1)
        to_date = date(year, 12, 31)
    elif not from_date:
        from_date = date(today.year, 1, 1)
        to_date = date(today.year, 12, 31)

    company_nif = school.nif or "000000000"
    company_name = school.legal_name or school.name

    # Invoices (FT, FR, ND)
    inv_result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.invoice_date >= from_date,
            Invoice.invoice_date <= to_date,
        ).order_by(Invoice.system_entry_date.asc())
    )
    invoices = inv_result.scalars().all()

    # Credit notes (NC)
    cn_result = await db.execute(
        select(CreditNote).where(
            CreditNote.school_id == school_id,
            CreditNote.invoice_date >= from_date,
            CreditNote.invoice_date <= to_date,
        ).order_by(CreditNote.system_entry_date.asc())
    )
    credit_notes = cn_result.scalars().all()

    # Receipts (RC)
    rc_result = await db.execute(
        select(Receipt).where(
            Receipt.school_id == school_id,
            Receipt.invoice_date >= from_date,
            Receipt.invoice_date <= to_date,
        ).order_by(Receipt.system_entry_date.asc())
    )
    receipts = rc_result.scalars().all()

    # Build customers
    customers = {}
    for inv in invoices:
        nif = inv.customer_nif or "999999999"
        if nif not in customers:
            customers[nif] = inv.customer_name or "Consumidor Final"

    # Build products (BillingItems referenced in documents)
    billing_item_ids = set()
    for inv in invoices:
        lines_r = await db.execute(
            select(InvoiceLine.billing_item_id).where(InvoiceLine.invoice_id == inv.id)
        )
        for row in lines_r.all():
            if row[0]:
                billing_item_ids.add(row[0])

    products_xml = ""
    if billing_item_ids:
        bi_result = await db.execute(
            select(BillingItem).where(
                BillingItem.school_id == school_id,
                BillingItem.id.in_(billing_item_ids),
            )
        )
        for bi in bi_result.scalars().all():
            products_xml += f"""
      <Product>
        <ProductCode>{bi.code}</ProductCode>
        <ProductDescription>{bi.name}</ProductDescription>
        <ProductType>P</ProductType>
      </Product>"""

    customers_xml = ""
    for nif, name in customers.items():
        customers_xml += f"""
      <Customer>
        <CustomerID>{nif}</CustomerID>
        <CustomerTaxID>{nif}</CustomerTaxID>
        <CompanyName>{name}</CompanyName>
      </Customer>"""

    # Sales invoices (FT, FR, ND, NC)
    invoices_xml = ""
    for inv in invoices:
        inv_status = "A" if inv.status == "cancelled" or inv.is_void else "N"
        # Load lines
        lines_r = await db.execute(
            select(InvoiceLine).where(InvoiceLine.invoice_id == inv.id).order_by(InvoiceLine.line_number)
        )
        lines = lines_r.scalars().all()
        lines_xml = ""
        for line in lines:
            lines_xml += f"""
            <Line>
              <LineNumber>{line.line_number}</LineNumber>
              <Description>{line.description[:200]}</Description>
              <Quantity>{line.quantity}</Quantity>
              <UnitPrice>{format_gross_total(line.unit_price)}</UnitPrice>
              <TaxPercentage>{format_gross_total(line.iva_rate)}</TaxPercentage>
              <SettlementAmount>{format_gross_total(line.discount_amount + (line.unit_price * line.quantity * line.discount_percent / Decimal("100")).quantize(Decimal("0.01")))}</SettlementAmount>
              <CreditAmount>{format_gross_total(line.line_total)}</CreditAmount>
            </Line>"""

        invoices_xml += f"""
        <Invoice>
          <InvoiceNo>{inv.full_document_number}</InvoiceNo>
          <DocumentStatus>
            <InvoiceStatus>{inv_status}</InvoiceStatus>
          </DocumentStatus>
          <Hash>{inv.hash_code or ''}</Hash>
          <HashControl>{signature_excerpt(inv.hash_code) if inv.hash_code else ''}</HashControl>
          <InvoiceDate>{inv.invoice_date}</InvoiceDate>
          <InvoiceType>{inv.document_type}</InvoiceType>
          <SystemEntryDate>{inv.system_entry_date.strftime('%Y-%m-%dT%H:%M:%S')}</SystemEntryDate>
          <CustomerID>{inv.customer_nif or '999999999'}</CustomerID>{lines_xml}
          <DocumentTotals>
            <TaxPayable>{format_gross_total(inv.iva_total)}</TaxPayable>
            <NetTotal>{format_gross_total(inv.net_total)}</NetTotal>
            <GrossTotal>{format_gross_total(inv.gross_total)}</GrossTotal>
          </DocumentTotals>
        </Invoice>"""

    # NC as invoices
    for cn in credit_notes:
        invoices_xml += f"""
        <Invoice>
          <InvoiceNo>{cn.full_document_number}</InvoiceNo>
          <DocumentStatus><InvoiceStatus>N</InvoiceStatus></DocumentStatus>
          <Hash>{cn.hash_code or ''}</Hash>
          <InvoiceDate>{cn.invoice_date}</InvoiceDate>
          <InvoiceType>NC</InvoiceType>
          <SystemEntryDate>{cn.system_entry_date.strftime('%Y-%m-%dT%H:%M:%S')}</SystemEntryDate>
          <CustomerID>{cn.customer_nif or '999999999'}</CustomerID>
          <DocumentTotals>
            <TaxPayable>{format_gross_total(cn.iva_total)}</TaxPayable>
            <NetTotal>{format_gross_total(cn.net_total)}</NetTotal>
            <GrossTotal>{format_gross_total(cn.gross_total)}</GrossTotal>
          </DocumentTotals>
        </Invoice>"""

    # Payments section (RC)
    payments_xml = ""
    for rc in receipts:
        rc_status = rc.status  # N or A
        payments_xml += f"""
        <Payment>
          <PaymentRefNo>{rc.full_document_number}</PaymentRefNo>
          <TransactionDate>{rc.invoice_date}</TransactionDate>
          <PaymentType>RC</PaymentType>
          <DocumentStatus>
            <PaymentStatus>{rc_status}</PaymentStatus>
          </DocumentStatus>
          <Hash>{rc.hash_code or ''}</Hash>
          <SystemEntryDate>{rc.system_entry_date.strftime('%Y-%m-%dT%H:%M:%S')}</SystemEntryDate>
          <CustomerID>{rc.customer_nif or '999999999'}</CustomerID>
          <DocumentTotals>
            <GrossTotal>{format_gross_total(rc.gross_total)}</GrossTotal>
          </DocumentTotals>
        </Payment>"""

    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<AuditFile xmlns="urn:OECD:Standard:SAF-T:1.00:AO">
  <Header>
    <AuditFileVersion>1.0</AuditFileVersion>
    <CompanyID>{company_nif}</CompanyID>
    <TaxRegistrationNumber>{company_nif}</TaxRegistrationNumber>
    <CompanyName>{company_name}</CompanyName>
    <FiscalYear>{from_date.year}</FiscalYear>
    <StartDate>{from_date}</StartDate>
    <EndDate>{to_date}</EndDate>
    <CurrencyCode>AOA</CurrencyCode>
    <DateCreated>{today}</DateCreated>
    <SoftwareCertificateNumber>0000/AGT</SoftwareCertificateNumber>
    <ProductID>Cellen/1.0</ProductID>
  </Header>
  <MasterFiles>{customers_xml}{products_xml}
  </MasterFiles>
  <SourceDocuments>
    <SalesInvoices>
      <NumberOfEntries>{len(invoices) + len(credit_notes)}</NumberOfEntries>{invoices_xml}
    </SalesInvoices>
    <Payments>
      <NumberOfEntries>{len(receipts)}</NumberOfEntries>{payments_xml}
    </Payments>
  </SourceDocuments>
</AuditFile>"""

    # Audit log the export
    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=getattr(_, "id", uuid.uuid4()),
        entity_type="saft_export",
        entity_id=school_id,
        action="export",
        after_snapshot={"from_date": str(from_date), "to_date": str(to_date)},
    )
    db.add(audit)
    await db.commit()

    return Response(content=xml, media_type="application/xml")


# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENT SERIES
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/series", response_model=list[DocumentSeriesResponse])
async def list_document_series(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(DocumentSeries).where(DocumentSeries.school_id == school_id)
        .order_by(DocumentSeries.year.desc(), DocumentSeries.document_type)
    )
    return result.scalars().all()


# ═══════════════════════════════════════════════════════════════════════════════
# EXPENSES
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/expense-categories", response_model=list[ExpenseCategoryResponse])
async def list_expense_categories(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ExpenseCategory).where(ExpenseCategory.school_id == school_id)
    )
    return result.scalars().all()


@router.post("/expense-categories", response_model=ExpenseCategoryResponse, status_code=201)
async def create_expense_category(
    body: ExpenseCategoryCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    cat = ExpenseCategory(school_id=school_id, **body.model_dump())
    db.add(cat)
    await db.commit()
    await db.refresh(cat)
    return cat


@router.patch("/expense-categories/{cat_id}", response_model=ExpenseCategoryResponse)
async def update_expense_category(
    cat_id: uuid.UUID,
    body: ExpenseCategoryUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ExpenseCategory).where(ExpenseCategory.id == cat_id, ExpenseCategory.school_id == school_id)
    )
    cat = result.scalar_one_or_none()
    if cat is None:
        raise HTTPException(status_code=404, detail="Category not found")
    for f, v in body.model_dump(exclude_unset=True).items():
        setattr(cat, f, v)
    await db.commit()
    await db.refresh(cat)
    return cat


@router.get("/expenses", response_model=list[ExpenseResponse])
async def list_expenses(
    skip: int = 0, limit: int = 50,
    category_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Expense).where(Expense.school_id == school_id)
    if category_id:
        query = query.where(Expense.category_id == category_id)
    if date_from:
        query = query.where(Expense.expense_date >= date_from)
    if date_to:
        query = query.where(Expense.expense_date <= date_to)
    result = await db.execute(query.order_by(Expense.expense_date.desc()).offset(skip).limit(limit))
    expenses = result.scalars().all()

    cat_ids = list({e.category_id for e in expenses})
    cat_map: dict = {}
    if cat_ids:
        cr = await db.execute(select(ExpenseCategory.id, ExpenseCategory.name).where(ExpenseCategory.id.in_(cat_ids)))
        cat_map = {r[0]: r[1] for r in cr.all()}

    output = []
    for e in expenses:
        data = ExpenseResponse.model_validate(e)
        data.category_name = cat_map.get(e.category_id)
        output.append(data)
    return output


@router.post("/expenses", response_model=ExpenseResponse, status_code=201)
async def create_expense(
    body: ExpenseCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    expense = Expense(school_id=school_id, **body.model_dump())
    db.add(expense)
    await db.commit()
    await db.refresh(expense)
    return expense


@router.get("/expenses/{expense_id}", response_model=ExpenseResponse)
async def get_expense(
    expense_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_finance_access),
):
    result = await db.execute(
        select(Expense).where(Expense.id == expense_id, Expense.school_id == school_id)
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    return expense


@router.patch("/expenses/{expense_id}", response_model=ExpenseResponse)
async def update_expense(
    expense_id: uuid.UUID,
    body: ExpenseUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Expense).where(Expense.id == expense_id, Expense.school_id == school_id)
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    for f, v in body.model_dump(exclude_unset=True).items():
        setattr(expense, f, v)
    await db.commit()
    await db.refresh(expense)
    return expense


@router.post("/expenses/{expense_id}/void", response_model=ExpenseResponse)
async def void_expense(
    expense_id: uuid.UUID,
    body: dict,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Expense).where(Expense.id == expense_id, Expense.school_id == school_id)
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    if expense.is_voided:
        raise HTTPException(status_code=400, detail="Already voided")
    expense.is_voided = True
    expense.void_reason = body.get("reason", "Voided")
    await db.commit()
    await db.refresh(expense)
    return expense


@router.post("/expenses/{expense_id}/receipt")
async def upload_expense_receipt(
    expense_id: uuid.UUID,
    file: UploadFile = File(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Expense).where(Expense.id == expense_id, Expense.school_id == school_id)
    )
    expense = result.scalar_one_or_none()
    if expense is None:
        raise HTTPException(status_code=404, detail="Expense not found")
    url = await save_upload(file, "expenses", expense_id)
    expense.receipt_url = url
    await db.commit()
    return {"receipt_url": url}


# ═══════════════════════════════════════════════════════════════════════════════
# AUDIT LOG (20.19)
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/audit-log")
async def list_audit_log(
    entity_type: Optional[str] = None,
    action: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(FinanceAuditEntry).where(FinanceAuditEntry.school_id == school_id)
    if entity_type:
        query = query.where(FinanceAuditEntry.entity_type == entity_type)
    if action:
        query = query.where(FinanceAuditEntry.action == action)
    result = await db.execute(query.order_by(FinanceAuditEntry.timestamp.desc()).offset(skip).limit(limit))
    entries = result.scalars().all()
    return [
        {
            "id": str(e.id),
            "actor_id": str(e.actor_id),
            "timestamp": e.timestamp.isoformat() if e.timestamp else None,
            "entity_type": e.entity_type,
            "entity_id": str(e.entity_id),
            "action": e.action,
            "reason": e.reason,
        }
        for e in entries
    ]
