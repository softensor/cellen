import uuid
from datetime import date
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_parent, require_school_admin
from app.models.finance import Expense, ExpenseCategory, Invoice, Payment, PaymentInvoice
from app.models.person import Child, Guardian
from app.schemas.finance import (
    ExpenseCategoryCreate, ExpenseCategoryResponse, ExpenseCategoryUpdate,
    ExpenseCreate, ExpenseResponse, ExpenseUpdate,
    InvoiceBulkCreate, InvoiceCreate, InvoiceResponse, InvoiceUpdate,
    MulticaixaResponse, ParentInvoiceResponse,
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


# ─── Multicaixa Reference Generation ─────────────────────────────────────────

@router.post("/invoices/{invoice_id}/multicaixa", response_model=MulticaixaResponse)
async def generate_multicaixa_reference(
    invoice_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.school import School

    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")

    # Return existing reference if already generated
    if invoice.multicaixa_ref and invoice.multicaixa_entity:
        return MulticaixaResponse(
            entidade=invoice.multicaixa_entity,
            referencia=invoice.multicaixa_ref,
            montante=str(invoice.total_amount),
        )

    # Determine entidade from school NIF (last 5 digits) or fallback
    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    nif = (school.nif or "") if school else ""
    # Strip non-digits and take last 5, fallback to "11111"
    nif_digits = "".join(c for c in nif if c.isdigit())
    entidade = nif_digits[-5:] if len(nif_digits) >= 5 else "11111"

    # Generate sequential reference: count of all invoices for this school up to and including this one
    count_result = await db.execute(
        select(func.count(Invoice.id)).where(
            Invoice.school_id == school_id,
            Invoice.created_at <= invoice.created_at,
        )
    )
    seq_num = count_result.scalar() or 1
    referencia = str(seq_num).zfill(9)

    invoice.multicaixa_entity = entidade
    invoice.multicaixa_ref = referencia
    await db.commit()
    await db.refresh(invoice)

    return MulticaixaResponse(
        entidade=entidade,
        referencia=referencia,
        montante=str(invoice.total_amount),
    )


# ─── Parent Invoice Portal ────────────────────────────────────────────────────

@router.get("/parent/invoices", response_model=List[ParentInvoiceResponse])
async def list_parent_invoices(
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    from app.models.person import ChildGuardian

    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No guardian record linked to this user account",
        )

    # Get all child_ids linked to this guardian
    cg_result = await db.execute(
        select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
    )
    child_ids = [row[0] for row in cg_result.all()]

    if not child_ids:
        return []

    # Fetch all invoices for those children
    inv_result = await db.execute(
        select(Invoice)
        .where(Invoice.child_id.in_(child_ids))
        .order_by(Invoice.reference_month.desc())
    )
    invoices = inv_result.scalars().all()

    # Build child name map
    child_result = await db.execute(
        select(Child.id, Child.first_name, Child.last_name)
        .where(Child.id.in_(child_ids))
    )
    child_name_map = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    output: List[ParentInvoiceResponse] = []
    for inv in invoices:
        amount_paid = await get_invoice_amount_paid(db, inv.id)
        output.append(
            ParentInvoiceResponse(
                id=inv.id,
                child_id=inv.child_id,
                child_name=child_name_map.get(inv.child_id, "Desconhecido"),
                reference_month=inv.reference_month,
                total_amount=inv.total_amount,
                status=inv.status,
                due_date=inv.due_date,
                multicaixa_entity=inv.multicaixa_entity,
                multicaixa_ref=inv.multicaixa_ref,
                amount_paid=amount_paid,
                balance=inv.total_amount - amount_paid,
            )
        )
    return output


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


# ─── Dashboard / Summary ──────────────────────────────────────────────────────

@router.get("/dashboard")
async def finance_dashboard(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    today = date.today()
    month_start = date(today.year, today.month, 1)

    # Total revenue this month (paid invoices)
    revenue_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.total_amount), 0))
        .where(
            Invoice.school_id == school_id,
            Invoice.status == "paid",
            Invoice.invoice_date >= month_start,
        )
    )
    total_revenue_month = float(revenue_result.scalar())

    # Total expenses this month
    expenses_result = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), 0))
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= month_start,
        )
    )
    total_expenses_month = float(expenses_result.scalar())

    # Pending invoices count
    pending_result = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "pending")
    )
    pending_invoices_count = pending_result.scalar()

    # Overdue invoices count
    overdue_result = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "overdue")
    )
    overdue_invoices_count = overdue_result.scalar()

    # Total outstanding (pending + overdue invoices total_amount)
    outstanding_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.total_amount), 0))
        .where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "overdue", "partially_paid"]),
        )
    )
    total_outstanding = float(outstanding_result.scalar())

    return {
        "total_revenue_month": total_revenue_month,
        "total_expenses_month": total_expenses_month,
        "pending_invoices_count": pending_invoices_count,
        "overdue_invoices_count": overdue_invoices_count,
        "total_outstanding": total_outstanding,
    }


@router.get("/summary")
async def finance_summary(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    today = date.today()
    month_start = date(today.year, today.month, 1)

    # Total revenue this month (paid invoices)
    revenue_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.total_amount), 0))
        .where(
            Invoice.school_id == school_id,
            Invoice.status == "paid",
            Invoice.invoice_date >= month_start,
        )
    )
    total_revenue_month = float(revenue_result.scalar())

    # Total expenses this month
    expenses_result = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), 0))
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= month_start,
        )
    )
    total_expenses_month = float(expenses_result.scalar())

    # Pending invoices count
    pending_result = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "pending")
    )
    pending_invoices_count = pending_result.scalar()

    # Overdue invoices count
    overdue_result = await db.execute(
        select(func.count(Invoice.id))
        .where(Invoice.school_id == school_id, Invoice.status == "overdue")
    )
    overdue_invoices_count = overdue_result.scalar()

    # Total outstanding (pending + overdue + partially_paid invoices total_amount)
    outstanding_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.total_amount), 0))
        .where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "overdue", "partially_paid"]),
        )
    )
    total_outstanding = float(outstanding_result.scalar())

    # Paid invoices count this month
    paid_result = await db.execute(
        select(func.count(Invoice.id))
        .where(
            Invoice.school_id == school_id,
            Invoice.status == "paid",
            Invoice.invoice_date >= month_start,
        )
    )
    paid_invoices_count = paid_result.scalar()

    # Total children invoiced this month (distinct child_ids)
    children_invoiced_result = await db.execute(
        select(func.count(func.distinct(Invoice.child_id)))
        .where(
            Invoice.school_id == school_id,
            Invoice.invoice_date >= month_start,
        )
    )
    total_children_invoiced = children_invoiced_result.scalar()

    return {
        "total_revenue_month": total_revenue_month,
        "total_expenses_month": total_expenses_month,
        "pending_invoices_count": pending_invoices_count,
        "overdue_invoices_count": overdue_invoices_count,
        "total_outstanding": total_outstanding,
        "paid_invoices_count": paid_invoices_count,
        "total_children_invoiced": total_children_invoiced,
    }


# ─── AGT Document Series ──────────────────────────────────────────────────────

class DocumentSeriesResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    document_type: str
    year: int
    next_number: int


class DocumentSeriesCreate(BaseModel):
    document_type: str
    year: int


@router.get("/series", response_model=list[DocumentSeriesResponse])
async def list_document_series(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import DocumentSeries
    result = await db.execute(
        select(DocumentSeries).where(DocumentSeries.school_id == school_id).order_by(
            DocumentSeries.year.desc(), DocumentSeries.document_type
        )
    )
    return result.scalars().all()


@router.post("/series", response_model=DocumentSeriesResponse, status_code=status.HTTP_201_CREATED)
async def create_or_get_series(
    body: DocumentSeriesCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import DocumentSeries
    result = await db.execute(
        select(DocumentSeries).where(
            DocumentSeries.school_id == school_id,
            DocumentSeries.document_type == body.document_type,
            DocumentSeries.year == body.year,
        )
    )
    series = result.scalar_one_or_none()
    if series is None:
        series = DocumentSeries(
            school_id=school_id,
            document_type=body.document_type,
            year=body.year,
            next_number=1,
        )
        db.add(series)
        await db.commit()
        await db.refresh(series)
    return series


# ─── AGT Invoice Void ─────────────────────────────────────────────────────────

class VoidInvoiceBody(BaseModel):
    reason: str


class CreditNoteResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    invoice_id: uuid.UUID
    issued_by: uuid.UUID
    series_year: int
    series_number: int
    full_document_number: str
    nif_cliente: Optional[str] = None
    reason: str
    taxable_base: Decimal
    iva_rate: Decimal
    iva_amount: Decimal
    total_amount: Decimal
    hash_code: Optional[str] = None
    created_at: Optional[date] = None


@router.post("/invoices/{invoice_id}/void", response_model=CreditNoteResponse)
async def void_invoice(
    invoice_id: uuid.UUID,
    body: VoidInvoiceBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    from app.models.modern import CreditNote
    from app.models.school import School
    from app.utils.agt import compute_hash, generate_document_number, get_last_document_hash, get_next_series_number

    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == school_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found")
    if invoice.is_void:
        raise HTTPException(status_code=400, detail="Invoice is already void")
    if invoice.status == "paid":
        raise HTTPException(status_code=400, detail="Cannot void a paid invoice")

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    nif_emitter = (school.nif or "") if school else ""

    today = date.today()
    nc_number = await get_next_series_number(db, school_id, "NC", today.year)
    nc_doc_number = generate_document_number("NC", today.year, nc_number)

    taxable_base = invoice.taxable_base if invoice.taxable_base else invoice.total_amount
    iva_rate = invoice.iva_rate if invoice.iva_rate else Decimal("0")
    iva_amount = invoice.iva_amount if invoice.iva_amount else Decimal("0")
    total_amount = taxable_base + iva_amount

    prev_hash = await get_last_document_hash(db, school_id, CreditNote)
    nc_hash = compute_hash(
        nc_doc_number, today, nif_emitter,
        invoice.nif_cliente or "Consumidor Final",
        float(total_amount), prev_hash
    )

    credit_note = CreditNote(
        school_id=school_id,
        invoice_id=invoice_id,
        issued_by=employee_id,
        series_year=today.year,
        series_number=nc_number,
        full_document_number=nc_doc_number,
        nif_cliente=invoice.nif_cliente,
        reason=body.reason,
        taxable_base=taxable_base,
        iva_rate=iva_rate,
        iva_amount=iva_amount,
        total_amount=total_amount,
        hash_code=nc_hash,
    )
    db.add(credit_note)

    invoice.is_void = True
    invoice.void_reason = body.reason
    invoice.status = "cancelled"

    await db.commit()
    await db.refresh(credit_note)
    return credit_note


# ─── Receipts ─────────────────────────────────────────────────────────────────

class ReceiptCreate(BaseModel):
    payment_id: uuid.UUID
    invoice_id: Optional[uuid.UUID] = None
    nif_cliente: Optional[str] = None


class ReceiptResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    payment_id: uuid.UUID
    invoice_id: Optional[uuid.UUID] = None
    series_year: int
    series_number: int
    full_document_number: str
    nif_cliente: Optional[str] = None
    amount: Decimal
    hash_code: Optional[str] = None
    issued_by: uuid.UUID
    issued_at: Optional[date] = None
    created_at: Optional[date] = None


@router.get("/receipts", response_model=list[ReceiptResponse])
async def list_receipts(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Receipt
    result = await db.execute(
        select(Receipt).where(Receipt.school_id == school_id)
        .order_by(Receipt.issued_at.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/receipts", response_model=ReceiptResponse, status_code=status.HTTP_201_CREATED)
async def create_receipt(
    body: ReceiptCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    from app.models.modern import Receipt
    from app.models.school import School
    from app.utils.agt import compute_hash, generate_document_number, get_last_document_hash, get_next_series_number

    # Verify payment belongs to school
    pay_result = await db.execute(
        select(Payment).where(Payment.id == body.payment_id, Payment.school_id == school_id)
    )
    payment = pay_result.scalar_one_or_none()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment not found")

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    nif_emitter = (school.nif or "") if school else ""

    today = date.today()
    rc_number = await get_next_series_number(db, school_id, "RC", today.year)
    rc_doc_number = generate_document_number("RC", today.year, rc_number)

    prev_hash = await get_last_document_hash(db, school_id, Receipt)
    rc_hash = compute_hash(
        rc_doc_number, today, nif_emitter,
        body.nif_cliente or "Consumidor Final",
        float(payment.amount), prev_hash
    )

    receipt = Receipt(
        school_id=school_id,
        payment_id=body.payment_id,
        invoice_id=body.invoice_id,
        series_year=today.year,
        series_number=rc_number,
        full_document_number=rc_doc_number,
        nif_cliente=body.nif_cliente,
        amount=payment.amount,
        hash_code=rc_hash,
        issued_by=employee_id,
    )
    db.add(receipt)
    await db.commit()
    await db.refresh(receipt)
    return receipt


# ─── Credit Notes ─────────────────────────────────────────────────────────────

@router.get("/credit-notes", response_model=list[CreditNoteResponse])
async def list_credit_notes(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import CreditNote
    result = await db.execute(
        select(CreditNote).where(CreditNote.school_id == school_id)
        .order_by(CreditNote.created_at.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.get("/credit-notes/{credit_note_id}", response_model=CreditNoteResponse)
async def get_credit_note(
    credit_note_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import CreditNote
    result = await db.execute(
        select(CreditNote).where(CreditNote.id == credit_note_id, CreditNote.school_id == school_id)
    )
    cn = result.scalar_one_or_none()
    if cn is None:
        raise HTTPException(status_code=404, detail="Credit note not found")
    return cn


# ─── Contracts ────────────────────────────────────────────────────────────────

class ContractCreate(BaseModel):
    child_id: uuid.UUID
    guardian_id: Optional[uuid.UUID] = None
    service_name: str
    description: Optional[str] = None
    amount: Decimal
    iva_rate: Decimal = Decimal("14.00")
    billing_cycle: str = "monthly"
    day_of_month: int = 1
    start_date: date
    end_date: Optional[date] = None
    auto_invoice: bool = True
    notes: Optional[str] = None


class ContractUpdate(BaseModel):
    service_name: Optional[str] = None
    description: Optional[str] = None
    amount: Optional[Decimal] = None
    iva_rate: Optional[Decimal] = None
    billing_cycle: Optional[str] = None
    day_of_month: Optional[int] = None
    end_date: Optional[date] = None
    is_active: Optional[bool] = None
    auto_invoice: Optional[bool] = None
    notes: Optional[str] = None


class ContractResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    guardian_id: Optional[uuid.UUID] = None
    service_name: str
    description: Optional[str] = None
    amount: Decimal
    iva_rate: Decimal
    billing_cycle: str
    day_of_month: int
    start_date: date
    end_date: Optional[date] = None
    is_active: bool
    auto_invoice: bool
    last_invoiced_month: Optional[date] = None
    notes: Optional[str] = None
    created_at: Optional[date] = None
    updated_at: Optional[date] = None
    child_name: Optional[str] = None


@router.post("/contracts", response_model=ContractResponse, status_code=status.HTTP_201_CREATED)
async def create_contract(
    body: ContractCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Contract
    contract = Contract(school_id=school_id, **body.model_dump())
    db.add(contract)
    await db.commit()
    await db.refresh(contract)
    return contract


@router.get("/contracts", response_model=list[ContractResponse])
async def list_contracts(
    child_id: Optional[uuid.UUID] = None,
    is_active: Optional[bool] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Contract
    query = select(Contract).where(Contract.school_id == school_id)
    if child_id:
        query = query.where(Contract.child_id == child_id)
    if is_active is not None:
        query = query.where(Contract.is_active == is_active)
    result = await db.execute(query.order_by(Contract.created_at.desc()).offset(skip).limit(limit))
    contracts = result.scalars().all()

    # Bulk fetch child names
    child_ids = list({c.child_id for c in contracts})
    child_name_map: dict = {}
    if child_ids:
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name)
            .where(Child.id.in_(child_ids))
        )
        child_name_map = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    return [
        {**c.__dict__, "child_name": child_name_map.get(c.child_id)}
        for c in contracts
    ]


@router.patch("/contracts/{contract_id}", response_model=ContractResponse)
async def update_contract(
    contract_id: uuid.UUID,
    body: ContractUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Contract
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(contract, field, value)
    await db.commit()
    await db.refresh(contract)
    return contract


@router.delete("/contracts/{contract_id}")
async def deactivate_contract(
    contract_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Contract
    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    contract.is_active = False
    await db.commit()
    return {"message": "Contract deactivated", "id": str(contract_id)}


@router.post("/contracts/{contract_id}/generate-invoice", response_model=InvoiceResponse)
async def generate_invoice_for_contract(
    contract_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    from app.models.modern import Contract
    from app.models.school import School
    from app.utils.agt import compute_hash, generate_document_number, get_last_document_hash, get_next_series_number

    result = await db.execute(
        select(Contract).where(Contract.id == contract_id, Contract.school_id == school_id)
    )
    contract = result.scalar_one_or_none()
    if contract is None:
        raise HTTPException(status_code=404, detail="Contract not found")
    if not contract.is_active:
        raise HTTPException(status_code=400, detail="Contract is not active")

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    nif_emitter = (school.nif or "") if school else ""

    today = date.today()
    ref_month = date(today.year, today.month, 1)

    taxable_base = contract.amount
    iva_rate = contract.iva_rate
    iva_amount = (taxable_base * iva_rate / Decimal("100")).quantize(Decimal("0.01"))
    total_amount = taxable_base + iva_amount

    ft_number = await get_next_series_number(db, school_id, "FT", today.year)
    ft_doc_number = generate_document_number("FT", today.year, ft_number)
    ft_hash = compute_hash(ft_doc_number, today, nif_emitter, "Consumidor Final", float(total_amount), await get_last_document_hash(db, school_id, Invoice))

    invoice = Invoice(
        school_id=school_id,
        child_id=contract.child_id,
        issued_by=employee_id,
        reference_month=ref_month,
        tuition_amount=taxable_base,
        other_fees=Decimal("0"),
        total_amount=total_amount,
        description=contract.service_name,
        document_type="FT",
        series_year=today.year,
        series_number=ft_number,
        full_document_number=ft_doc_number,
        taxable_base=taxable_base,
        iva_rate=iva_rate,
        iva_amount=iva_amount,
        hash_code=ft_hash,
    )
    db.add(invoice)

    contract.last_invoiced_month = ref_month

    await db.commit()
    await db.refresh(invoice)
    return await _enrich_invoice(db, invoice)


# ─── Auto-Generate Invoices From Contracts ────────────────────────────────────

class AutoGenerateContractsResponse(BaseModel):
    generated: int
    skipped: int
    errors: int


@router.post("/invoices/auto-generate-contracts", response_model=AutoGenerateContractsResponse)
async def auto_generate_contract_invoices(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    from app.models.modern import Contract
    from app.models.school import School
    from app.utils.agt import compute_hash, generate_document_number, get_last_document_hash, get_next_series_number

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    today = date.today()
    current_month = date(today.year, today.month, 1)

    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    nif_emitter = (school.nif or "") if school else ""

    contracts_result = await db.execute(
        select(Contract).where(
            Contract.school_id == school_id,
            Contract.is_active == True,
            Contract.auto_invoice == True,
            Contract.day_of_month <= today.day,
            Contract.start_date <= today,
        )
    )
    contracts = contracts_result.scalars().all()

    generated = 0
    skipped = 0
    errors = 0

    for contract in contracts:
        try:
            # Skip if already invoiced this month
            if contract.last_invoiced_month and contract.last_invoiced_month >= current_month:
                skipped += 1
                continue

            # Check end date
            if contract.end_date and contract.end_date < today:
                skipped += 1
                continue

            taxable_base = contract.amount
            iva_rate = contract.iva_rate
            iva_amount = (taxable_base * iva_rate / Decimal("100")).quantize(Decimal("0.01"))
            total_amount = taxable_base + iva_amount

            ft_number = await get_next_series_number(db, school_id, "FT", today.year)
            ft_doc_number = generate_document_number("FT", today.year, ft_number)
            ft_hash = compute_hash(
                ft_doc_number, today, nif_emitter, "Consumidor Final", float(total_amount),
                await get_last_document_hash(db, school_id, Invoice)
            )

            invoice = Invoice(
                school_id=school_id,
                child_id=contract.child_id,
                issued_by=employee_id,
                reference_month=current_month,
                tuition_amount=taxable_base,
                other_fees=Decimal("0"),
                total_amount=total_amount,
                description=contract.service_name,
                document_type="FT",
                series_year=today.year,
                series_number=ft_number,
                full_document_number=ft_doc_number,
                taxable_base=taxable_base,
                iva_rate=iva_rate,
                iva_amount=iva_amount,
                hash_code=ft_hash,
            )
            db.add(invoice)
            contract.last_invoiced_month = current_month
            generated += 1
        except Exception:
            errors += 1

    await db.commit()
    return AutoGenerateContractsResponse(generated=generated, skipped=skipped, errors=errors)


# ─── Delinquency Report ───────────────────────────────────────────────────────

@router.get("/reports/delinquent")
async def delinquent_report(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.person import ChildGuardian

    today = date.today()

    overdue_result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["overdue", "pending"]),
            Invoice.due_date < today,
            Invoice.is_void == False,
        ).order_by(Invoice.due_date.asc())
    )
    invoices = overdue_result.scalars().all()

    output = []
    for inv in invoices:
        child_result = await db.execute(select(Child).where(Child.id == inv.child_id))
        child = child_result.scalar_one_or_none()
        child_name = f"{child.first_name} {child.last_name}" if child else "Unknown"

        guardian_name = None
        guardian_mobile = None
        if child:
            link_result = await db.execute(
                select(ChildGuardian).where(
                    ChildGuardian.child_id == child.id,
                    ChildGuardian.is_primary_contact == True,
                )
            )
            link = link_result.scalar_one_or_none()
            if link:
                g_result = await db.execute(select(Guardian).where(Guardian.id == link.guardian_id))
                guardian = g_result.scalar_one_or_none()
                if guardian:
                    guardian_name = f"{guardian.first_name} {guardian.last_name}"
                    guardian_mobile = guardian.mobile_first

        days_overdue = (today - inv.due_date).days if inv.due_date else None

        output.append({
            "child_name": child_name,
            "guardian_name": guardian_name,
            "guardian_mobile": guardian_mobile,
            "invoice_number": inv.full_document_number or str(inv.id),
            "amount": float(inv.total_amount),
            "due_date": str(inv.due_date) if inv.due_date else None,
            "days_overdue": days_overdue,
            "status": inv.status,
        })

    return output


# ─── SAF-T XML Export ─────────────────────────────────────────────────────────

@router.get("/reports/saft")
async def saft_export(
    from_date: date,
    to_date: date,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import CreditNote
    from app.models.school import School

    school_result = await db.execute(select(School).where(School.id == school_id))  # type: ignore[arg-type]
    school = school_result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    company_nif = school.nif or "000000000"
    company_name = school.legal_name or school.name
    fiscal_year = from_date.year
    today = date.today()

    # Get invoices in period
    invoices_result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.invoice_date >= from_date,
            Invoice.invoice_date <= to_date,
        ).order_by(Invoice.invoice_date.asc())
    )
    invoices = invoices_result.scalars().all()

    # Get credit notes in period
    cn_result = await db.execute(
        select(CreditNote).where(
            CreditNote.school_id == school_id,
            CreditNote.created_at >= from_date,  # type: ignore[arg-type]
            CreditNote.created_at <= to_date,  # type: ignore[arg-type]
        ).order_by(CreditNote.created_at.asc())
    )
    credit_notes = cn_result.scalars().all()

    # Collect unique customer NIFs from invoices
    customer_nifs = {}
    for inv in invoices:
        nif = inv.nif_cliente
        if nif and nif not in customer_nifs:
            # Try to find guardian name
            customer_nifs[nif] = nif
    for cn in credit_notes:
        nif = cn.nif_cliente
        if nif and nif not in customer_nifs:
            customer_nifs[nif] = nif

    # Build customer XML
    customers_xml = ""
    for nif, name in customer_nifs.items():
        customers_xml += f"""
      <Customer>
        <CustomerID>{nif}</CustomerID>
        <CustomerTaxID>{nif}</CustomerTaxID>
        <CompanyName>{name}</CompanyName>
      </Customer>"""

    # Build invoice XML lines
    invoice_lines_xml = ""
    for inv in invoices:
        taxable = float(inv.taxable_base or inv.total_amount)
        iva_rate = float(inv.iva_rate or 0)
        iva_amount = float(inv.iva_amount or 0)
        total = float(inv.total_amount)
        customer_id = inv.nif_cliente or "Consumidor Final"
        doc_number = inv.full_document_number or str(inv.id)
        description = inv.description or inv.document_type or "Serviço"
        invoice_lines_xml += f"""
        <Invoice>
          <InvoiceNo>{doc_number}</InvoiceNo>
          <InvoiceType>{inv.document_type}</InvoiceType>
          <InvoiceDate>{inv.invoice_date}</InvoiceDate>
          <CustomerID>{customer_id}</CustomerID>
          <Line>
            <Description>{description}</Description>
            <Quantity>1</Quantity>
            <UnitPrice>{taxable:.2f}</UnitPrice>
            <TaxBase>{taxable:.2f}</TaxBase>
            <TaxPercentage>{iva_rate:.2f}</TaxPercentage>
            <TaxAmount>{iva_amount:.2f}</TaxAmount>
          </Line>
          <DocumentTotals>
            <TaxPayable>{iva_amount:.2f}</TaxPayable>
            <NetTotal>{taxable:.2f}</NetTotal>
            <GrossTotal>{total:.2f}</GrossTotal>
          </DocumentTotals>
          <Hash>{inv.hash_code or ''}</Hash>
        </Invoice>"""

    # Add credit notes
    for cn in credit_notes:
        taxable = float(cn.taxable_base)
        iva_rate = float(cn.iva_rate)
        iva_amount = float(cn.iva_amount)
        total = float(cn.total_amount)
        customer_id = cn.nif_cliente or "Consumidor Final"
        invoice_lines_xml += f"""
        <Invoice>
          <InvoiceNo>{cn.full_document_number}</InvoiceNo>
          <InvoiceType>NC</InvoiceType>
          <InvoiceDate>{cn.created_at.date() if cn.created_at else today}</InvoiceDate>
          <CustomerID>{customer_id}</CustomerID>
          <Line>
            <Description>{cn.reason[:200]}</Description>
            <Quantity>1</Quantity>
            <UnitPrice>{taxable:.2f}</UnitPrice>
            <TaxBase>{taxable:.2f}</TaxBase>
            <TaxPercentage>{iva_rate:.2f}</TaxPercentage>
            <TaxAmount>{iva_amount:.2f}</TaxAmount>
          </Line>
          <DocumentTotals>
            <TaxPayable>{iva_amount:.2f}</TaxPayable>
            <NetTotal>{taxable:.2f}</NetTotal>
            <GrossTotal>{total:.2f}</GrossTotal>
          </DocumentTotals>
          <Hash>{cn.hash_code or ''}</Hash>
        </Invoice>"""

    xml_string = f"""<?xml version="1.0" encoding="UTF-8"?>
<AuditFile xmlns="urn:OECD:Standard:SAF-T:1.00:AO">
  <Header>
    <AuditFileVersion>1.0</AuditFileVersion>
    <CompanyID>{company_nif}</CompanyID>
    <CompanyName>{company_name}</CompanyName>
    <FiscalYear>{fiscal_year}</FiscalYear>
    <StartDate>{from_date}</StartDate>
    <EndDate>{to_date}</EndDate>
    <CurrencyCode>AOA</CurrencyCode>
    <DateCreated>{today}</DateCreated>
    <SoftwareCertificateNumber>CE-001</SoftwareCertificateNumber>
  </Header>
  <MasterFiles>{customers_xml}
  </MasterFiles>
  <SourceDocuments>
    <SalesInvoices>{invoice_lines_xml}
    </SalesInvoices>
  </SourceDocuments>
</AuditFile>"""

    return Response(content=xml_string, media_type="application/xml")
