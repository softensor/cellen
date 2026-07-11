import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Dict, List, Optional

from pydantic import BaseModel, ConfigDict


# Expense Category
class ExpenseCategoryBase(BaseModel):
    name: str
    description: Optional[str] = None


class ExpenseCategoryCreate(ExpenseCategoryBase):
    pass


class ExpenseCategoryUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class ExpenseCategoryResponse(ExpenseCategoryBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID


# Expense
class ExpenseBase(BaseModel):
    category_id: uuid.UUID
    registered_by: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    description: str
    amount: Decimal
    expense_date: date
    payment_method: Optional[str] = None
    reference: Optional[str] = None
    receipt_url: Optional[str] = None
    notes: Optional[str] = None


class ExpenseCreate(ExpenseBase):
    pass


class ExpenseUpdate(BaseModel):
    category_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    amount: Optional[Decimal] = None
    expense_date: Optional[date] = None
    payment_method: Optional[str] = None
    reference: Optional[str] = None
    receipt_url: Optional[str] = None
    notes: Optional[str] = None


class ExpenseResponse(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


# Invoice
class InvoiceBase(BaseModel):
    child_id: uuid.UUID
    issued_by: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    invoice_date: Optional[date] = None
    reference_month: date
    description: Optional[str] = None
    tuition_amount: Decimal = Decimal("0")
    other_fees: Decimal = Decimal("0")
    due_date: Optional[date] = None
    notes: Optional[str] = None


class InvoiceCreate(InvoiceBase):
    pass


class InvoiceBulkCreate(BaseModel):
    school_year_id: uuid.UUID
    issued_by: uuid.UUID
    reference_month: date
    tuition_amount: Decimal
    other_fees: Decimal = Decimal("0")
    due_date: Optional[date] = None
    description: Optional[str] = None


class InvoiceUpdate(BaseModel):
    description: Optional[str] = None
    tuition_amount: Optional[Decimal] = None
    other_fees: Optional[Decimal] = None
    due_date: Optional[date] = None
    notes: Optional[str] = None


class InvoiceResponse(InvoiceBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    total_amount: Decimal
    status: str
    amount_paid: Decimal = Decimal("0")
    balance: Decimal = Decimal("0")
    created_at: datetime
    updated_at: datetime


# Payment
class PaymentAllocation(BaseModel):
    invoice_id: uuid.UUID
    amount_applied: Decimal


class PaymentBase(BaseModel):
    child_id: uuid.UUID
    received_by: uuid.UUID
    payment_date: Optional[date] = None
    receipt_number: Optional[str] = None
    amount: Decimal
    payment_method: Optional[str] = None
    notes: Optional[str] = None


class PaymentCreate(PaymentBase):
    invoice_allocations: List[PaymentAllocation] = []


class PaymentResponse(PaymentBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    settled_invoice_ids: List[uuid.UUID] = []
    created_at: datetime


class PaymentInvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    payment_id: uuid.UUID
    invoice_id: uuid.UUID
    amount_applied: Decimal


# Finance Reports
class PLByCategory(BaseModel):
    category_id: uuid.UUID
    category_name: str
    total: Decimal


class MonthlyPL(BaseModel):
    year: int
    month: int
    income: Decimal
    expenses: Decimal
    net: Decimal
    by_category: List[PLByCategory] = []


class AnnualPL(BaseModel):
    year: int
    months: List[MonthlyPL]
    total_income: Decimal
    total_expenses: Decimal
    total_net: Decimal


class OutstandingInvoice(BaseModel):
    invoice_id: uuid.UUID
    child_id: uuid.UUID
    child_name: str
    reference_month: date
    total_amount: Decimal
    amount_paid: Decimal
    balance: Decimal
    due_date: Optional[date]
    days_overdue: int
    status: str


class CashFlowMonth(BaseModel):
    year: int
    month: int
    inflows: Decimal
    outflows: Decimal
    net: Decimal


class RevenuByLevel(BaseModel):
    level: str
    total_invoiced: Decimal
    total_paid: Decimal
    outstanding: Decimal
