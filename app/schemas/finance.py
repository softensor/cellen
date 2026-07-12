import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Dict, List, Optional

from pydantic import BaseModel, ConfigDict

from app.schemas.base import DecimalFloat


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
    amount: DecimalFloat
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
    amount: Optional[DecimalFloat] = None
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
    category_name: Optional[str] = None


# Invoice
class InvoiceBase(BaseModel):
    child_id: uuid.UUID
    issued_by: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    invoice_date: Optional[date] = None
    reference_month: date
    description: Optional[str] = None
    tuition_amount: DecimalFloat = Decimal("0")
    other_fees: DecimalFloat = Decimal("0")
    due_date: Optional[date] = None
    notes: Optional[str] = None


class InvoiceCreate(InvoiceBase):
    pass


class InvoiceBulkCreate(BaseModel):
    school_year_id: uuid.UUID
    issued_by: uuid.UUID
    reference_month: date
    tuition_amount: DecimalFloat
    other_fees: DecimalFloat = Decimal("0")
    due_date: Optional[date] = None
    description: Optional[str] = None


class InvoiceUpdate(BaseModel):
    description: Optional[str] = None
    tuition_amount: Optional[DecimalFloat] = None
    other_fees: Optional[DecimalFloat] = None
    due_date: Optional[date] = None
    notes: Optional[str] = None


class InvoiceResponse(InvoiceBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    total_amount: DecimalFloat
    status: str
    amount_paid: DecimalFloat = Decimal("0")
    balance: DecimalFloat = Decimal("0")
    multicaixa_entity: Optional[str] = None
    multicaixa_ref: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class MulticaixaResponse(BaseModel):
    entidade: str
    referencia: str
    montante: str


class ParentInvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    child_id: uuid.UUID
    child_name: str
    reference_month: date
    total_amount: DecimalFloat
    status: str
    due_date: Optional[date] = None
    multicaixa_entity: Optional[str] = None
    multicaixa_ref: Optional[str] = None
    amount_paid: DecimalFloat = Decimal("0")
    balance: DecimalFloat = Decimal("0")


# Payment
class PaymentAllocation(BaseModel):
    invoice_id: uuid.UUID
    amount_applied: DecimalFloat


class PaymentBase(BaseModel):
    child_id: uuid.UUID
    received_by: uuid.UUID
    payment_date: Optional[date] = None
    receipt_number: Optional[str] = None
    amount: DecimalFloat
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
    amount_applied: DecimalFloat


# Finance Reports
class PLByCategory(BaseModel):
    category_id: uuid.UUID
    category_name: str
    total: DecimalFloat


class MonthlyPL(BaseModel):
    year: int
    month: int
    income: DecimalFloat
    expenses: DecimalFloat
    net: DecimalFloat
    by_category: List[PLByCategory] = []


class AnnualPL(BaseModel):
    year: int
    months: List[MonthlyPL]
    total_income: DecimalFloat
    total_expenses: DecimalFloat
    total_net: DecimalFloat


class OutstandingInvoice(BaseModel):
    invoice_id: uuid.UUID
    child_id: uuid.UUID
    child_name: str
    reference_month: date
    total_amount: DecimalFloat
    amount_paid: DecimalFloat
    balance: DecimalFloat
    due_date: Optional[date]
    days_overdue: int
    status: str


class CashFlowMonth(BaseModel):
    year: int
    month: int
    inflows: DecimalFloat
    outflows: DecimalFloat
    net: DecimalFloat


class RevenuByLevel(BaseModel):
    level: str
    total_invoiced: DecimalFloat
    total_paid: DecimalFloat
    outstanding: DecimalFloat
