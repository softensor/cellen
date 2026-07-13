import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional

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
    is_voided: bool = False
    void_reason: Optional[str] = None


# Invoice line item
class InvoiceLineCreate(BaseModel):
    billing_item_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    quantity: int = 1
    unit_price: DecimalFloat
    iva_rate: Optional[DecimalFloat] = None
    iva_exemption_reason: Optional[str] = None


class InvoiceLineResponse(BaseModel):
    billing_item_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    quantity: int = 1
    unit_price: DecimalFloat
    iva_rate: DecimalFloat = Decimal("0")
    iva_exemption_reason: Optional[str] = None
    line_total: DecimalFloat = Decimal("0")


# Invoice
class InvoiceBase(BaseModel):
    child_id: uuid.UUID
    issued_by: Optional[uuid.UUID] = None
    billing_guardian_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None
    invoice_date: Optional[date] = None
    reference_month: date
    description: Optional[str] = None
    tuition_amount: DecimalFloat = Decimal("0")
    other_fees: DecimalFloat = Decimal("0")
    due_date: Optional[date] = None
    notes: Optional[str] = None


class InvoiceCreate(InvoiceBase):
    lines: List[InvoiceLineCreate] = []


class InvoiceBulkCreate(BaseModel):
    school_year_id: Optional[uuid.UUID] = None
    issued_by: Optional[uuid.UUID] = None
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
    child_name: Optional[str] = None
    amount_paid: DecimalFloat = Decimal("0")
    balance: DecimalFloat = Decimal("0")
    multicaixa_entity: Optional[str] = None
    multicaixa_ref: Optional[str] = None
    full_document_number: Optional[str] = None
    series_number: Optional[int] = None
    hash_code: Optional[str] = None
    lines: Optional[List[Any]] = None
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
    invoice_ids: Optional[List[uuid.UUID]] = None  # explicit targeting (bypasses oldest-first)


class PaymentResponse(PaymentBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    settled_invoice_ids: List[uuid.UUID] = []
    status: str = "normal"
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
