import uuid
from datetime import date
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin
from app.models.finance import Expense, ExpenseCategory, Invoice, Payment, PaymentInvoice
from app.models.person import Child
from app.schemas.finance import (
    ExpenseCategoryCreate, ExpenseCategoryResponse, ExpenseCategoryUpdate,
    ExpenseCreate, ExpenseResponse, ExpenseUpdate,
    InvoiceBulkCreate, InvoiceCreate, InvoiceResponse, InvoiceUpdate,
    PaymentCreate, PaymentResponse,
    MonthlyPL, AnnualPL, OutstandingInvoice, CashFlowMonth, RevenuByLevel,
)
from app.services.finance import (
    apply_payment_to_invoices,
    get_invoice_amount_paid,
    generate_monthly_pl,
    generate_annual_pl,
    get_outstanding_invoices,
    get_cash_flow,
    get_revenue_by_level,
    mark_overdue_invoices,
    reverse_payment,
)
from app.services.storage import save_upload

router = APIRouter(prefix="/finance", tags=["Finance"])


# ─── Expense Categories ───────────────────────────────────────────────────────

@router.get("/expense-categories", response_model=list[ExpenseCategoryResponse])
async def list_expense_categories(
    skip: int = 0,
    limit: int = 100,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ExpenseCategory).where(ExpenseCategory.school_id == school_id).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/expense-categories", response_model=ExpenseCategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_expense_category(
    body: ExpenseCategoryCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    category = ExpenseCategory(school_id=school_id, **body.model_dump())
    db.add(category)
    await db.commit()
    await db.refresh(category)
    return category


@router.patch("/expense-categories/{category_id}", response_model=ExpenseCategoryResponse)
async def update_expense_category(
    category_id: uuid.UUID,
    body: ExpenseCategoryUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ExpenseCategory).where(
            ExpenseCategory.id == category_id, ExpenseCategory.school_id == school_id
        )
    )
    category = result.scalar_one_or_none()
    if category is None:
        raise HTTPException(status_code=404, detail="Expense category not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(category, field, value)
    await db.commit()
    await db.refresh(category)
    return category


# ─── Expenses ─────────────────────────────────────────────────────────────────

@router.get("/expenses", response_model=list[ExpenseResponse])
async def list_expenses(
    skip: int = 0,
    limit: int = 50,
    category_id: Optional[uuid.UUID] = None,
    school_year_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Expense).where(Expense.school_id == school_id)
    if category_id:
        query = query.where(Expense.category_id == category_id)
    if school_year_id:
        query = query.where(Expense.school_year_id == school_year_id)
    if date_from:
        query = query.where(Expense.expense_date >= date_from)
    if date_to:
        query = query.where(Expense.expense_date <= date_to)
    result = await db.execute(query.order_by(Expense.expense_date.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.post("/expenses", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
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
    _=Depends(require_school_admin),
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
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(expense, field, value)
    await db.commit()
    await db.refresh(expense)
    return expense


@router.delete("/expenses/{expense_id}")
async def delete_expense(
    expense_id: uuid.UUID,
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
    await db.delete(expense)
    await db.commit()
    return {"message": "Expense deleted"}


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


# ─── Invoices ─────────────────────────────────────────────────────────────────

async def _enrich_invoice(db: AsyncSession, invoice: Invoice) -> InvoiceResponse:
    amount_paid = await get_invoice_amount_paid(db, invoice.id)
    data = InvoiceResponse.model_validate(invoice)
    data.amount_paid = amount_paid
    data.balance = invoice.total_amount - amount_paid
    return data


@router.get("/invoices", response_model=list[InvoiceResponse])
async def list_invoices(
    skip: int = 0,
    limit: int = 50,
    child_id: Optional[uuid.UUID] = None,
    invoice_status: Optional[str] = None,
    reference_month: Optional[date] = None,
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Invoice).where(Invoice.school_id == school_id)
    if child_id:
        query = query.where(Invoice.child_id == child_id)
    if invoice_status:
        query = query.where(Invoice.status == invoice_status)
    if reference_month:
        query = query.where(Invoice.reference_month == reference_month)
    if school_year_id:
        query = query.where(Invoice.school_year_id == school_year_id)
    result = await db.execute(query.order_by(Invoice.reference_month.desc()).offset(skip).limit(limit))
    invoices = result.scalars().all()
    return [await _enrich_invoice(db, inv) for inv in invoices]


@router.post("/invoices", response_model=InvoiceResponse, status_code=status.HTTP_201_CREATED)
async def create_invoice(
    body: InvoiceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    data = body.model_dump()
    total = (data.get("tuition_amount") or Decimal("0")) + (data.get("other_fees") or Decimal("0"))
    invoice = Invoice(school_id=school_id, total_amount=total, **data)
    db.add(invoice)
    await db.commit()
    await db.refresh(invoice)
    return await _enrich_invoice(db, invoice)


@router.post("/invoices/bulk", response_model=list[InvoiceResponse], status_code=status.HTTP_201_CREATED)
async def bulk_create_invoices(
    body: InvoiceBulkCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.academic import Enrollment

    # Get all active children in this school year
    children_result = await db.execute(
        select(Child.id).join(
            Enrollment, Enrollment.child_id == Child.id
        ).where(
            Child.school_id == school_id,
            Child.is_active == True,
            Enrollment.school_id == school_id,
            Enrollment.school_year_id == body.school_year_id,
            Enrollment.status == "active",
        ).distinct()
    )
    child_ids = [row[0] for row in children_result.all()]

    total_amount = body.tuition_amount + body.other_fees
    invoices = []
    for child_id in child_ids:
        # Check if invoice already exists for this child/month
        existing = await db.execute(
            select(Invoice).where(
                Invoice.school_id == school_id,
                Invoice.child_id == child_id,
                Invoice.reference_month == body.reference_month,
            )
        )
        if existing.scalar_one_or_none():
            continue  # Skip, already has an invoice for this month

        invoice = Invoice(
            school_id=school_id,
            child_id=child_id,
            issued_by=body.issued_by,
            school_year_id=body.school_year_id,
            reference_month=body.reference_month,
            tuition_amount=body.tuition_amount,
            other_fees=body.other_fees,
            total_amount=total_amount,
            due_date=body.due_date,
            description=body.description,
        )
        db.add(invoice)
        invoices.append(invoice)

    await db.commit()
    for inv in invoices:
        await db.refresh(inv)

    return [await _enrich_invoice(db, inv) for inv in invoices]


@router.get("/invoices/{invoice_id}", response_model=InvoiceResponse)
async def get_invoice(
    invoice_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    return await _enrich_invoice(db, invoice)


@router.patch("/invoices/{invoice_id}", response_model=InvoiceResponse)
async def update_invoice(
    invoice_id: uuid.UUID,
    body: InvoiceUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if invoice.status == "paid":
        raise HTTPException(status_code=400, detail="Cannot update a paid invoice")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(invoice, field, value)

    # Recalculate total
    invoice.total_amount = invoice.tuition_amount + invoice.other_fees
    await db.commit()
    await db.refresh(invoice)
    return await _enrich_invoice(db, invoice)


@router.post("/invoices/{invoice_id}/cancel")
async def cancel_invoice(
    invoice_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if invoice.status == "paid":
        raise HTTPException(status_code=400, detail="Cannot cancel a paid invoice")
    invoice.status = "cancelled"
    await db.commit()
    return {"message": "Invoice cancelled", "id": str(invoice_id)}


# ─── Payments ─────────────────────────────────────────────────────────────────

@router.get("/payments", response_model=list[PaymentResponse])
async def list_payments(
    skip: int = 0,
    limit: int = 50,
    child_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Payment).where(Payment.school_id == school_id)
    if child_id:
        query = query.where(Payment.child_id == child_id)
    if date_from:
        query = query.where(Payment.payment_date >= date_from)
    if date_to:
        query = query.where(Payment.payment_date <= date_to)
    result = await db.execute(query.order_by(Payment.payment_date.desc()).offset(skip).limit(limit))
    payments = result.scalars().all()
    output = []
    for payment in payments:
        pi_result = await db.execute(
            select(PaymentInvoice.invoice_id).where(PaymentInvoice.payment_id == payment.id)
        )
        invoice_ids = [row[0] for row in pi_result.all()]
        data = PaymentResponse.model_validate(payment)
        data.settled_invoice_ids = invoice_ids
        output.append(data)
    return output


@router.post("/payments", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED)
async def create_payment(
    body: PaymentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Validate: total == sum of allocations
    if body.invoice_allocations:
        total_allocated = sum(a.amount_applied for a in body.invoice_allocations)
        if total_allocated != body.amount:
            raise HTTPException(
                status_code=400,
                detail=f"Payment amount ({body.amount}) must equal sum of allocations ({total_allocated})",
            )

    allocations = body.invoice_allocations
    payment_data = body.model_dump(exclude={"invoice_allocations"})
    payment_data.setdefault("payment_date", date.today())

    payment = Payment(school_id=school_id, **payment_data)
    db.add(payment)
    await db.flush()

    if allocations:
        await apply_payment_to_invoices(db, school_id, payment.id, allocations)

    await db.commit()
    await db.refresh(payment)

    data = PaymentResponse.model_validate(payment)
    data.settled_invoice_ids = [a.invoice_id for a in allocations]
    return data


@router.get("/payments/{payment_id}", response_model=PaymentResponse)
async def get_payment(
    payment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment not found")

    pi_result = await db.execute(
        select(PaymentInvoice.invoice_id).where(PaymentInvoice.payment_id == payment.id)
    )
    invoice_ids = [row[0] for row in pi_result.all()]
    data = PaymentResponse.model_validate(payment)
    data.settled_invoice_ids = invoice_ids
    return data


@router.delete("/payments/{payment_id}")
async def delete_payment(
    payment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment not found")

    # Reverse all invoice allocations first
    await reverse_payment(db, school_id, payment_id)
    await db.delete(payment)
    await db.commit()
    return {"message": "Payment reversed and deleted"}


# ─── Reports ──────────────────────────────────────────────────────────────────

@router.get("/reports/pl")
async def profit_and_loss(
    year: int,
    month: Optional[int] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    if month:
        return await generate_monthly_pl(db, school_id, year, month)
    else:
        return await generate_annual_pl(db, school_id, year)


@router.get("/reports/outstanding", response_model=list[OutstandingInvoice])
async def outstanding_invoices(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # First mark any new overdue ones
    await mark_overdue_invoices(db, school_id)
    await db.commit()
    data = await get_outstanding_invoices(db, school_id)
    return data


@router.get("/reports/cash-flow", response_model=list[CashFlowMonth])
async def cash_flow(
    year: int,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    return await get_cash_flow(db, school_id, year)


@router.get("/reports/revenue-by-level", response_model=list[RevenuByLevel])
async def revenue_by_level(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    return await get_revenue_by_level(db, school_id)


# ─── Bulk Generate Invoices ───────────────────────────────────────────────────

class BulkGenerateBody(BaseModel):
    reference_month: str  # YYYY-MM
    tuition_amount: float
    due_date: Optional[str] = None  # YYYY-MM-DD
    description: Optional[str] = None


class BulkGenerateResponse(BaseModel):
    created: int
    skipped: int
    total: int


@router.post("/invoices/bulk-generate", response_model=BulkGenerateResponse)
async def bulk_generate_invoices(
    body: BulkGenerateBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    from datetime import date as _date
    from decimal import Decimal as _Decimal

    # Parse reference_month (YYYY-MM) to a date (first of month)
    try:
        year, month = int(body.reference_month[:4]), int(body.reference_month[5:7])
        reference_month_date = _date(year, month, 1)
    except (ValueError, IndexError):
        from fastapi import HTTPException as _HTTPException
        raise _HTTPException(status_code=400, detail="reference_month must be in YYYY-MM format")

    due_date_parsed: Optional[_date] = None
    if body.due_date:
        try:
            due_date_parsed = _date.fromisoformat(body.due_date)
        except ValueError:
            from fastapi import HTTPException as _HTTPException
            raise _HTTPException(status_code=400, detail="due_date must be in YYYY-MM-DD format")

    # Get current user's employee_id for issued_by
    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        from fastapi import HTTPException as _HTTPException
        raise _HTTPException(status_code=400, detail="Current user has no associated employee record")

    # Get all active children in this school
    children_result = await db.execute(
        select(Child).where(Child.school_id == school_id, Child.is_active == True)
    )
    children = children_result.scalars().all()

    tuition = _Decimal(str(body.tuition_amount))
    created_count = 0
    skipped_count = 0

    for child in children:
        existing_result = await db.execute(
            select(Invoice).where(
                Invoice.school_id == school_id,
                Invoice.child_id == child.id,
                Invoice.reference_month == reference_month_date,
            )
        )
        if existing_result.scalar_one_or_none() is not None:
            skipped_count += 1
            continue

        invoice = Invoice(
            school_id=school_id,
            child_id=child.id,
            issued_by=employee_id,
            reference_month=reference_month_date,
            tuition_amount=tuition,
            other_fees=_Decimal("0"),
            total_amount=tuition,
            due_date=due_date_parsed,
            description=body.description,
        )
        db.add(invoice)
        created_count += 1

    await db.commit()
    total = created_count + skipped_count
    return BulkGenerateResponse(created=created_count, skipped=skipped_count, total=total)
