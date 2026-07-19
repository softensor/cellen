# -*- coding: utf-8 -*-
"""Finance Pydantic schemas for API request/response."""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, List, Optional

from pydantic import BaseModel, ConfigDict

from app.schemas.base import DecimalFloat


# ─── Billing Items ───────────────────────────────────────────────────────────

class BillingItemCreate(BaseModel):
    code: str
    name: str
    description: Optional[str] = None
    unit_price: DecimalFloat = Decimal("0")
    iva_rate: DecimalFloat = Decimal("0")
    iva_exemption_reason: Optional[str] = None
    iva_exemption_legend: Optional[str] = None
    category: Optional[str] = None


class BillingItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    unit_price: Optional[DecimalFloat] = None
    iva_rate: Optional[DecimalFloat] = None
    iva_exemption_reason: Optional[str] = None
    iva_exemption_legend: Optional[str] = None
    category: Optional[str] = None
    is_active: Optional[bool] = None


class BillingItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    code: str
    name: str
    description: Optional[str] = None
    unit_price: DecimalFloat
    iva_rate: DecimalFloat
    iva_exemption_reason: Optional[str] = None
    iva_exemption_legend: Optional[str] = None
    category: Optional[str] = None
    is_active: bool = True
    created_at: Optional[datetime] = None


# ─── Billing Item Prices (20.17) ─────────────────────────────────────────────

class BillingItemPriceCreate(BaseModel):
    billing_item_id: uuid.UUID
    school_year_id: uuid.UUID
    unit_price: DecimalFloat


class BillingItemPriceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    billing_item_id: uuid.UUID
    school_year_id: uuid.UUID
    unit_price: DecimalFloat


# ─── Contracts ───────────────────────────────────────────────────────────────

class ContractCreate(BaseModel):
    child_id: uuid.UUID
    guardian_id: Optional[uuid.UUID] = None
    billing_item_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None
    service_name: Optional[str] = None
    description: Optional[str] = None
    unit_price: Optional[DecimalFloat] = None
    quantity: DecimalFloat = Decimal("1")
    iva_rate: DecimalFloat = Decimal("0")
    discount_percent: DecimalFloat = Decimal("0")
    discount_amount: DecimalFloat = Decimal("0")
    billing_cycle: str = "monthly"
    day_of_month: int = 1
    start_date: date
    end_date: Optional[date] = None
    auto_invoice: bool = True
    notes: Optional[str] = None


class ContractUpdate(BaseModel):
    service_name: Optional[str] = None
    description: Optional[str] = None
    unit_price: Optional[DecimalFloat] = None
    quantity: Optional[DecimalFloat] = None
    iva_rate: Optional[DecimalFloat] = None
    discount_percent: Optional[DecimalFloat] = None
    discount_amount: Optional[DecimalFloat] = None
    billing_cycle: Optional[str] = None
    day_of_month: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    is_active: Optional[bool] = None
    status: Optional[str] = None
    auto_invoice: Optional[bool] = None
    notes: Optional[str] = None


class ContractResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    guardian_id: Optional[uuid.UUID] = None
    billing_item_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None
    service_name: Optional[str] = None
    description: Optional[str] = None
    unit_price: Optional[DecimalFloat] = None
    quantity: DecimalFloat = Decimal("1")
    iva_rate: DecimalFloat
    discount_percent: DecimalFloat = Decimal("0")
    discount_amount: DecimalFloat = Decimal("0")
    billing_cycle: str
    day_of_month: int
    start_date: date
    end_date: Optional[date] = None
    is_active: bool
    status: str = "active"
    auto_invoice: bool
    last_invoiced_month: Optional[date] = None
    notes: Optional[str] = None
    created_at: Optional[datetime] = None
    child_name: Optional[str] = None


# ─── Invoice Lines ───────────────────────────────────────────────────────────

class InvoiceLineInput(BaseModel):
    billing_item_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    quantity: DecimalFloat = Decimal("1")
    unit_price: DecimalFloat
    discount_percent: DecimalFloat = Decimal("0")
    discount_amount: DecimalFloat = Decimal("0")
    iva_rate: Optional[DecimalFloat] = None
    iva_exemption_reason: Optional[str] = None


class InvoiceLineResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    line_number: int
    billing_item_id: Optional[uuid.UUID] = None
    description: str
    quantity: DecimalFloat
    unit_price: DecimalFloat
    discount_percent: DecimalFloat = Decimal("0")
    discount_amount: DecimalFloat = Decimal("0")
    iva_rate: DecimalFloat
    iva_exemption_reason: Optional[str] = None
    line_net: DecimalFloat
    iva_amount: DecimalFloat
    line_total: DecimalFloat
    credited_amount: DecimalFloat = Decimal("0")


# ─── Invoices ────────────────────────────────────────────────────────────────

class InvoiceCreate(BaseModel):
    document_type: str = "FT"  # FT, FR, ND
    child_id: Optional[uuid.UUID] = None
    billing_guardian_id: Optional[uuid.UUID] = None
    invoice_date: Optional[date] = None
    due_date: Optional[date] = None
    school_year_id: Optional[uuid.UUID] = None
    reference_month: Optional[date] = None
    description: Optional[str] = None
    notes: Optional[str] = None
    lines: List[InvoiceLineInput] = []
    # For FR: payment info
    payment_method: Optional[str] = None
    # For ND: correction reference
    corrected_invoice_id: Optional[uuid.UUID] = None
    correction_reason: Optional[str] = None


class InvoiceBulkCreate(BaseModel):
    school_year_id: Optional[uuid.UUID] = None
    reference_month: date
    due_date: Optional[date] = None
    description: Optional[str] = None


class InvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    document_type: str
    series_year: int
    series_number: int
    full_document_number: str
    invoice_date: date
    system_entry_date: datetime
    due_date: Optional[date] = None
    billing_guardian_id: Optional[uuid.UUID] = None
    child_id: Optional[uuid.UUID] = None
    customer_nif: Optional[str] = None
    customer_name: Optional[str] = None
    is_final_consumer: bool = False
    gross_total: DecimalFloat
    net_total: DecimalFloat
    iva_total: DecimalFloat
    hash_code: Optional[str] = None
    status: str
    is_void: bool = False
    description: Optional[str] = None
    reference_month: Optional[date] = None
    corrected_invoice_id: Optional[uuid.UUID] = None
    correction_reason: Optional[str] = None
    created_at: datetime
    # Enriched fields
    lines: List[InvoiceLineResponse] = []
    amount_paid: DecimalFloat = Decimal("0")
    balance: DecimalFloat = Decimal("0")
    child_name: Optional[str] = None
    signature_excerpt: Optional[str] = None


class ParentInvoiceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    child_id: Optional[uuid.UUID] = None
    child_name: str
    document_type: str
    full_document_number: str
    reference_month: Optional[date] = None
    gross_total: DecimalFloat
    status: str
    due_date: Optional[date] = None
    amount_paid: DecimalFloat = Decimal("0")
    balance: DecimalFloat = Decimal("0")


# ─── Credit Notes ────────────────────────────────────────────────────────────

class CreditNoteCreate(BaseModel):
    invoice_id: uuid.UUID
    reason: str
    lines: List[dict] = []  # [{line_id, amount}] for partial; empty = full void


class CreditNoteResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    invoice_id: uuid.UUID
    full_document_number: str
    invoice_date: date
    system_entry_date: datetime
    customer_nif: Optional[str] = None
    customer_name: Optional[str] = None
    reason: str
    net_total: DecimalFloat
    iva_total: DecimalFloat
    gross_total: DecimalFloat
    hash_code: Optional[str] = None
    lines: Optional[List[Any]] = None
    created_at: Optional[datetime] = None


# ─── Payments ────────────────────────────────────────────────────────────────

class PaymentCreate(BaseModel):
    billing_guardian_id: uuid.UUID
    amount: DecimalFloat
    payment_method: str  # cash, transfer, check, card, multicaixa
    payment_date: Optional[date] = None
    target_invoice_ids: Optional[List[uuid.UUID]] = None
    payment_reference_id: Optional[uuid.UUID] = None
    received_by: Optional[uuid.UUID] = None
    idempotency_key: Optional[str] = None
    notes: Optional[str] = None
    receipt_proof_url: Optional[str] = None


class PaymentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    billing_guardian_id: uuid.UUID
    amount: DecimalFloat
    payment_method: str
    payment_date: date
    status: str
    notes: Optional[str] = None
    receipt_proof_url: Optional[str] = None
    received_by: Optional[uuid.UUID] = None
    idempotency_key: Optional[str] = None
    payment_reference_id: Optional[uuid.UUID] = None
    created_at: datetime
    allocated_invoices: List[dict] = []


# ─── Payment References (20.11) ──────────────────────────────────────────────

class PaymentReferenceCreate(BaseModel):
    invoice_id: Optional[uuid.UUID] = None
    billing_guardian_id: uuid.UUID
    entity: str
    reference: str
    amount: Optional[DecimalFloat] = None
    expires_at: Optional[datetime] = None
    provider: str = "manual"
    external_id: Optional[str] = None


class PaymentReferenceMarkPaid(BaseModel):
    paid_at: Optional[datetime] = None
    amount: DecimalFloat
    payment_method: str = "multicaixa"
    notes: Optional[str] = None


class PaymentReferenceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    invoice_id: Optional[uuid.UUID] = None
    billing_guardian_id: uuid.UUID
    entity: str
    reference: str
    amount: Optional[DecimalFloat] = None
    status: str
    expires_at: Optional[datetime] = None
    provider: str
    external_id: Optional[str] = None
    created_at: datetime
    paid_at: Optional[datetime] = None


# ─── Credit Balance (20.12) ──────────────────────────────────────────────────

class CreditApplyRequest(BaseModel):
    invoice_id: uuid.UUID
    amount: DecimalFloat


class CreditRefundRequest(BaseModel):
    amount: DecimalFloat
    method: str
    reference: Optional[str] = None


class CreditEntryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    billing_guardian_id: uuid.UUID
    source: str
    amount: DecimalFloat
    amount_remaining: DecimalFloat
    is_reversed: bool
    notes: Optional[str] = None
    created_at: datetime


# ─── Cash Sessions (20.14) ───────────────────────────────────────────────────

class CashSessionOpen(BaseModel):
    opening_float: DecimalFloat = Decimal("0")


class CashSessionClose(BaseModel):
    counted_by_method: dict  # {"cash": 1000.00, "check": 500.00}
    variance_reason: Optional[str] = None


class CashSessionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    opened_by: uuid.UUID
    opened_at: datetime
    opening_float: DecimalFloat
    closed_by: Optional[uuid.UUID] = None
    closed_at: Optional[datetime] = None
    expected_by_method: Optional[dict] = None
    counted_by_method: Optional[dict] = None
    variance: Optional[DecimalFloat] = None
    variance_reason: Optional[str] = None
    status: str


# ─── Receipts ────────────────────────────────────────────────────────────────

class ReceiptResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    payment_id: uuid.UUID
    full_document_number: str
    invoice_date: date
    system_entry_date: datetime
    customer_nif: Optional[str] = None
    customer_name: Optional[str] = None
    gross_total: DecimalFloat
    settled_documents: Optional[List[Any]] = None
    hash_code: Optional[str] = None
    status: str
    issued_by: Optional[uuid.UUID] = None
    created_at: Optional[datetime] = None


# ─── Expenses ────────────────────────────────────────────────────────────────

class ExpenseCategoryCreate(BaseModel):
    name: str
    description: Optional[str] = None


class ExpenseCategoryUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class ExpenseCategoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    name: str
    description: Optional[str] = None
    is_active: bool = True


class ExpenseCreate(BaseModel):
    category_id: uuid.UUID
    registered_by: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    description: str
    amount: DecimalFloat
    expense_date: date
    vendor: Optional[str] = None
    payment_method: Optional[str] = None
    reference: Optional[str] = None
    notes: Optional[str] = None


class ExpenseUpdate(BaseModel):
    category_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    amount: Optional[DecimalFloat] = None
    expense_date: Optional[date] = None
    vendor: Optional[str] = None
    payment_method: Optional[str] = None
    reference: Optional[str] = None
    notes: Optional[str] = None


class ExpenseResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    category_id: uuid.UUID
    registered_by: uuid.UUID
    description: str
    amount: DecimalFloat
    expense_date: date
    vendor: Optional[str] = None
    payment_method: Optional[str] = None
    reference: Optional[str] = None
    receipt_url: Optional[str] = None
    notes: Optional[str] = None
    is_voided: bool = False
    void_reason: Optional[str] = None
    created_at: datetime
    category_name: Optional[str] = None


# ─── Reports ─────────────────────────────────────────────────────────────────

class OutstandingInvoice(BaseModel):
    invoice_id: uuid.UUID
    document_number: Optional[str] = None
    child_name: Optional[str] = None
    guardian_name: Optional[str] = None
    gross_total: DecimalFloat
    amount_paid: DecimalFloat
    balance: DecimalFloat
    due_date: Optional[date] = None
    days_overdue: int = 0
    status: str


class CashFlowMonth(BaseModel):
    year: int
    month: int
    inflows: DecimalFloat
    outflows: DecimalFloat
    net: DecimalFloat


class AccountStatementResponse(BaseModel):
    guardian_id: uuid.UUID
    total_invoiced: DecimalFloat
    total_settled: DecimalFloat
    current_balance: DecimalFloat
    credit_balance: DecimalFloat
    movements: List[dict] = []


# ─── Payment Plans (20.15) ───────────────────────────────────────────────────

class PaymentPlanInstallmentInput(BaseModel):
    due_date: date
    amount: DecimalFloat


class PaymentPlanCreate(BaseModel):
    billing_guardian_id: uuid.UUID
    invoice_ids: List[uuid.UUID]
    installments: List[PaymentPlanInstallmentInput]
    notes: Optional[str] = None


class PaymentPlanResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    billing_guardian_id: uuid.UUID
    invoice_ids: List[Any]
    total_amount: DecimalFloat = Decimal("0")
    status: str
    notes: Optional[str] = None
    created_at: datetime
    installments: List[dict] = []


# ─── Dunning (20.16) ─────────────────────────────────────────────────────────

class ReminderCreate(BaseModel):
    billing_guardian_id: uuid.UUID
    invoice_ids: List[uuid.UUID]
    level: int
    channel: str  # whatsapp, email, sms, letter, verbal
    message_snapshot: Optional[str] = None


class ReminderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    billing_guardian_id: uuid.UUID
    invoice_ids: List[Any]
    level: int
    channel: str
    sent_by: uuid.UUID
    sent_at: datetime
    message_snapshot: Optional[str] = None


# ─── Document Series ─────────────────────────────────────────────────────────

class DocumentSeriesResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    document_type: str
    year: int
    next_number: int
