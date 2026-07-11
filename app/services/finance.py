from datetime import date
from decimal import Decimal
from typing import List
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finance import Invoice, Payment, PaymentInvoice, Expense, ExpenseCategory
from app.models.academic import Enrollment, Turma
from app.models.person import Child
from app.schemas.finance import PaymentAllocation


async def recalculate_invoice_status(db: AsyncSession, invoice_id: UUID) -> None:
    """Recalculate invoice status based on total payments applied."""
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id)
    )
    invoice = result.scalar_one_or_none()
    if invoice is None or invoice.status == "cancelled":
        return

    # Sum all applied payments
    paid_result = await db.execute(
        select(func.coalesce(func.sum(PaymentInvoice.amount_applied), Decimal("0")))
        .where(PaymentInvoice.invoice_id == invoice_id)
    )
    amount_paid = paid_result.scalar_one()

    if amount_paid >= invoice.total_amount:
        invoice.status = "paid"
    elif amount_paid > 0:
        invoice.status = "partially_paid"
    else:
        # Revert to pending or overdue
        if invoice.due_date and invoice.due_date < date.today():
            invoice.status = "overdue"
        else:
            invoice.status = "pending"

    await db.flush()


async def apply_payment_to_invoices(
    db: AsyncSession,
    school_id: UUID,
    payment_id: UUID,
    allocations: List[PaymentAllocation],
) -> None:
    """
    For each allocation:
    1. Create PaymentInvoice record
    2. Recalculate invoice status
    """
    for allocation in allocations:
        pi = PaymentInvoice(
            payment_id=payment_id,
            invoice_id=allocation.invoice_id,
            school_id=school_id,
            amount_applied=allocation.amount_applied,
        )
        db.add(pi)
    await db.flush()

    for allocation in allocations:
        await recalculate_invoice_status(db, allocation.invoice_id)


async def reverse_payment(db: AsyncSession, school_id: UUID, payment_id: UUID) -> None:
    """
    Delete all PaymentInvoice records for this payment.
    Recalculate each affected invoice status.
    """
    result = await db.execute(
        select(PaymentInvoice)
        .where(PaymentInvoice.payment_id == payment_id, PaymentInvoice.school_id == school_id)
    )
    links = result.scalars().all()
    affected_invoice_ids = [link.invoice_id for link in links]

    for link in links:
        await db.delete(link)
    await db.flush()

    for invoice_id in affected_invoice_ids:
        await recalculate_invoice_status(db, invoice_id)


async def get_outstanding_balance(
    db: AsyncSession, school_id: UUID, child_id: UUID
) -> Decimal:
    """Sum of (total_amount - amount_paid) for all non-cancelled invoices."""
    invoices_result = await db.execute(
        select(Invoice)
        .where(
            Invoice.school_id == school_id,
            Invoice.child_id == child_id,
            Invoice.status != "cancelled",
        )
    )
    invoices = invoices_result.scalars().all()

    total_balance = Decimal("0")
    for invoice in invoices:
        paid_result = await db.execute(
            select(func.coalesce(func.sum(PaymentInvoice.amount_applied), Decimal("0")))
            .where(PaymentInvoice.invoice_id == invoice.id)
        )
        amount_paid = paid_result.scalar_one()
        total_balance += invoice.total_amount - amount_paid

    return total_balance


async def get_invoice_amount_paid(db: AsyncSession, invoice_id: UUID) -> Decimal:
    """Get the total amount paid for a specific invoice."""
    result = await db.execute(
        select(func.coalesce(func.sum(PaymentInvoice.amount_applied), Decimal("0")))
        .where(PaymentInvoice.invoice_id == invoice_id)
    )
    return result.scalar_one()


async def generate_monthly_pl(
    db: AsyncSession, school_id: UUID, year: int, month: int
) -> dict:
    """
    income = SUM(payments.amount) WHERE payment_date in month
    expenses = SUM(expenses.amount) WHERE expense_date in month
    by_category = expenses grouped by category
    """
    from datetime import date
    import calendar

    start_date = date(year, month, 1)
    last_day = calendar.monthrange(year, month)[1]
    end_date = date(year, month, last_day)

    # Income from payments
    income_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
        .where(
            Payment.school_id == school_id,
            Payment.payment_date >= start_date,
            Payment.payment_date <= end_date,
        )
    )
    income = income_result.scalar_one()

    # Total expenses
    expense_result = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), Decimal("0")))
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
        )
    )
    total_expenses = expense_result.scalar_one()

    # Expenses by category
    by_cat_result = await db.execute(
        select(
            ExpenseCategory.id,
            ExpenseCategory.name,
            func.coalesce(func.sum(Expense.amount), Decimal("0")).label("total"),
        )
        .join(Expense, Expense.category_id == ExpenseCategory.id)
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
        )
        .group_by(ExpenseCategory.id, ExpenseCategory.name)
    )
    by_category = [
        {"category_id": row.id, "category_name": row.name, "total": row.total}
        for row in by_cat_result.all()
    ]

    return {
        "year": year,
        "month": month,
        "income": income,
        "expenses": total_expenses,
        "net": income - total_expenses,
        "by_category": by_category,
    }


async def generate_annual_pl(db: AsyncSession, school_id: UUID, year: int) -> dict:
    """Annual P&L: monthly breakdown."""
    months = []
    total_income = Decimal("0")
    total_expenses = Decimal("0")

    for month in range(1, 13):
        monthly = await generate_monthly_pl(db, school_id, year, month)
        months.append(monthly)
        total_income += monthly["income"]
        total_expenses += monthly["expenses"]

    return {
        "year": year,
        "months": months,
        "total_income": total_income,
        "total_expenses": total_expenses,
        "total_net": total_income - total_expenses,
    }


async def mark_overdue_invoices(db: AsyncSession, school_id: UUID) -> int:
    """
    Update status='overdue' for invoices WHERE:
    status IN ('pending','partially_paid') AND due_date < today
    Returns count of updated invoices.
    """
    today = date.today()
    result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "partially_paid"]),
            Invoice.due_date < today,
        )
    )
    invoices = result.scalars().all()
    count = 0
    for invoice in invoices:
        invoice.status = "overdue"
        count += 1
    if count:
        await db.flush()
    return count


async def get_outstanding_invoices(db: AsyncSession, school_id: UUID) -> list:
    """Get all unpaid/overdue invoices with child info and days overdue."""
    today = date.today()

    result = await db.execute(
        select(Invoice, Child)
        .join(Child, Child.id == Invoice.child_id)
        .where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "partially_paid", "overdue"]),
        )
        .order_by(Invoice.due_date.asc().nullslast())
    )
    rows = result.all()

    outstanding = []
    for invoice, child in rows:
        amount_paid = await get_invoice_amount_paid(db, invoice.id)
        balance = invoice.total_amount - amount_paid
        if invoice.due_date:
            days_overdue = max(0, (today - invoice.due_date).days)
        else:
            days_overdue = 0

        outstanding.append(
            {
                "invoice_id": invoice.id,
                "child_id": child.id,
                "child_name": f"{child.first_name} {child.last_name}",
                "reference_month": invoice.reference_month,
                "total_amount": invoice.total_amount,
                "amount_paid": amount_paid,
                "balance": balance,
                "due_date": invoice.due_date,
                "days_overdue": days_overdue,
                "status": invoice.status,
            }
        )
    return outstanding


async def get_cash_flow(db: AsyncSession, school_id: UUID, year: int) -> list:
    """Monthly cash inflows vs outflows for the year."""
    import calendar

    months = []
    for month in range(1, 13):
        start_date = date(year, month, 1)
        last_day = calendar.monthrange(year, month)[1]
        end_date = date(year, month, last_day)

        inflow_result = await db.execute(
            select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
            .where(
                Payment.school_id == school_id,
                Payment.payment_date >= start_date,
                Payment.payment_date <= end_date,
            )
        )
        inflows = inflow_result.scalar_one()

        outflow_result = await db.execute(
            select(func.coalesce(func.sum(Expense.amount), Decimal("0")))
            .where(
                Expense.school_id == school_id,
                Expense.expense_date >= start_date,
                Expense.expense_date <= end_date,
            )
        )
        outflows = outflow_result.scalar_one()

        months.append(
            {
                "year": year,
                "month": month,
                "inflows": inflows,
                "outflows": outflows,
                "net": inflows - outflows,
            }
        )
    return months


async def get_revenue_by_level(db: AsyncSession, school_id: UUID) -> list:
    """Revenue breakdown by class level (via enrollments -> turmas)."""
    # Get all turmas
    turmas_result = await db.execute(
        select(Turma).where(Turma.school_id == school_id)
    )
    turmas = turmas_result.scalars().all()

    result = []
    for turma in turmas:
        # Get child_ids enrolled in this turma via schedules
        from app.models.academic import Schedule
        child_ids_result = await db.execute(
            select(Enrollment.child_id)
            .join(Schedule, Schedule.id == Enrollment.schedule_id)
            .where(
                Enrollment.school_id == school_id,
                Schedule.turma_id == turma.id,
            )
        )
        child_ids = [row[0] for row in child_ids_result.all()]

        if not child_ids:
            result.append(
                {
                    "level": turma.level,
                    "total_invoiced": Decimal("0"),
                    "total_paid": Decimal("0"),
                    "outstanding": Decimal("0"),
                }
            )
            continue

        invoiced_result = await db.execute(
            select(func.coalesce(func.sum(Invoice.total_amount), Decimal("0")))
            .where(
                Invoice.school_id == school_id,
                Invoice.child_id.in_(child_ids),
                Invoice.status != "cancelled",
            )
        )
        total_invoiced = invoiced_result.scalar_one()

        paid_result = await db.execute(
            select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
            .where(
                Payment.school_id == school_id,
                Payment.child_id.in_(child_ids),
            )
        )
        total_paid = paid_result.scalar_one()

        result.append(
            {
                "level": turma.level,
                "total_invoiced": total_invoiced,
                "total_paid": total_paid,
                "outstanding": total_invoiced - total_paid,
            }
        )

    return result
