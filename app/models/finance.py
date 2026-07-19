# -*- coding: utf-8 -*-
"""
Finance models - AGT-compliant document chain, payments, credits, cash sessions.

All fiscal documents (FT, FR, NC, ND, RC) share a common base with hash chain fields.
The Invoice table holds FT, FR, ND documents. CreditNote holds NC. Receipt holds RC.
"""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Optional

from sqlalchemy import (
    Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer,
    Numeric, String, Text, UniqueConstraint, func
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


# ─── Document Series ─────────────────────────────────────────────────────────

class DocumentSeries(Base):
    """One series per document type per year per school. Serializes numbering."""
    __tablename__ = "document_series"
    __table_args__ = (
        UniqueConstraint("school_id", "document_type", "year", name="uq_document_series_school_type_year"),
        Index("ix_document_series_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    document_type: Mapped[str] = mapped_column(String(5), nullable=False)  # FT, FR, NC, ND, RC
    year: Mapped[int] = mapped_column(Integer, nullable=False)
    next_number: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    last_hash: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # hash_code of last doc in this series
    last_invoice_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    last_system_entry_date: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


# ─── Billing Items ───────────────────────────────────────────────────────────

class BillingItem(Base):
    """Service catalog — reusable items referenced by contracts and invoice lines."""
    __tablename__ = "billing_items"
    __table_args__ = (
        UniqueConstraint("school_id", "code", name="uq_billing_items_school_code"),
        Index("ix_billing_items_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    iva_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    iva_exemption_reason: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    iva_exemption_legend: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class BillingItemPrice(Base):
    """Price per billing item per school year (20.17)."""
    __tablename__ = "billing_item_prices"
    __table_args__ = (
        UniqueConstraint("billing_item_id", "school_year_id", name="uq_billing_item_price_item_year"),
        Index("ix_billing_item_prices_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_item_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="RESTRICT"), nullable=False
    )
    school_year_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="RESTRICT"), nullable=False
    )
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)


# ─── Contracts ───────────────────────────────────────────────────────────────

class Contract(Base):
    """Recurring billing contract for a child, billed to guardian."""
    __tablename__ = "contracts"
    __table_args__ = (
        Index("ix_contracts_school_id", "school_id"),
        Index("ix_contracts_child_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    guardian_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="SET NULL"), nullable=True
    )
    billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    school_year_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="SET NULL"), nullable=True
    )
    service_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    unit_price: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(8, 2), nullable=False, default=Decimal("1"))
    iva_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    discount_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    billing_cycle: Mapped[str] = mapped_column(String(20), nullable=False, default="monthly")
    day_of_month: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    auto_invoice: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_invoiced_month: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


# ─── Invoice (FT / FR / ND) ─────────────────────────────────────────────────

class Invoice(Base):
    """
    Fiscal document: FT (Factura), FR (Factura-Recibo), or ND (Nota de Débito).
    Immutable once signed (hash_code, series_number, system_entry_date, gross_total).
    """
    __tablename__ = "invoices"
    __table_args__ = (
        UniqueConstraint("school_id", "full_document_number", name="uq_invoices_school_doc_number"),
        Index("ix_invoices_school_id", "school_id"),
        Index("ix_invoices_billing_guardian_id", "billing_guardian_id"),
        Index("ix_invoices_status", "school_id", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    # Document identity
    document_type: Mapped[str] = mapped_column(String(5), nullable=False, default="FT")  # FT, FR, ND
    series_year: Mapped[int] = mapped_column(Integer, nullable=False)
    series_number: Mapped[int] = mapped_column(Integer, nullable=False)
    full_document_number: Mapped[str] = mapped_column(String(30), nullable=False)

    # Dates
    invoice_date: Mapped[date] = mapped_column(Date, nullable=False)
    system_entry_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    due_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)

    # Parties
    billing_guardian_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="SET NULL"), nullable=True
    )
    child_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL"), nullable=True
    )
    customer_nif: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    customer_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    is_final_consumer: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # Amounts (immutable after signing)
    gross_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    net_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    iva_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))

    # Hash chain (AGT requirement)
    hash_code: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # Base64 RSA-SHA1 signature
    previous_hash: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Status and lifecycle
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    # pending, partially_paid, paid, cancelled, overdue
    is_void: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    void_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # For NC/ND: reference to corrected document
    corrected_invoice_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True
    )
    correction_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Metadata
    issued_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )
    school_year_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="SET NULL"), nullable=True
    )
    reference_month: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # AGT transmission (20.20)
    transmission_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="not_required"
    )  # not_required, pending, transmitted, rejected
    transmission_response: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    lines = relationship("InvoiceLine", back_populates="invoice", cascade="all, delete-orphan",
                         order_by="InvoiceLine.line_number")
    payment_links = relationship("PaymentAllocation", back_populates="invoice")


class InvoiceLine(Base):
    """Individual line item on an invoice."""
    __tablename__ = "invoice_lines"
    __table_args__ = (
        Index("ix_invoice_lines_invoice_id", "invoice_id"),
        CheckConstraint(
            "NOT (discount_percent > 0 AND discount_amount > 0)",
            name="ck_invoice_lines_discount_exclusive"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="CASCADE"), nullable=False
    )
    line_number: Mapped[int] = mapped_column(Integer, nullable=False)
    billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False, default=Decimal("1"))
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    discount_percent: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    discount_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    iva_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, default=Decimal("0"))
    iva_exemption_reason: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    iva_exemption_legend: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Computed (stored for immutability)
    line_net: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    iva_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    line_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    # For partial credit notes: track how much has been credited
    credited_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))

    invoice = relationship("Invoice", back_populates="lines")


# ─── Credit Note (NC) ────────────────────────────────────────────────────────

class CreditNote(Base):
    """NC — Nota de Crédito. Corrects an FT/FR downward."""
    __tablename__ = "credit_notes"
    __table_args__ = (
        UniqueConstraint("school_id", "full_document_number", name="uq_credit_notes_school_doc_number"),
        Index("ix_credit_notes_school_id", "school_id"),
        Index("ix_credit_notes_invoice_id", "invoice_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="RESTRICT"), nullable=False
    )
    issued_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )

    # Document identity
    series_year: Mapped[int] = mapped_column(Integer, nullable=False)
    series_number: Mapped[int] = mapped_column(Integer, nullable=False)
    full_document_number: Mapped[str] = mapped_column(String(30), nullable=False)
    invoice_date: Mapped[date] = mapped_column(Date, nullable=False)
    system_entry_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    # Customer
    customer_nif: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    customer_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    # Amounts
    net_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    iva_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    gross_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    # Content
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    lines: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)  # credited line details

    # Hash chain
    hash_code: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    previous_hash: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # AGT transmission
    transmission_status: Mapped[str] = mapped_column(String(20), nullable=False, default="not_required")
    transmission_response: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Receipt (RC) ────────────────────────────────────────────────────────────

class Receipt(Base):
    """RC — Recibo. Settles one or more FT documents."""
    __tablename__ = "receipts"
    __table_args__ = (
        UniqueConstraint("school_id", "full_document_number", name="uq_receipts_school_doc_number"),
        Index("ix_receipts_school_id", "school_id"),
        Index("ix_receipts_payment_id", "payment_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    payment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payments.id", ondelete="RESTRICT"), nullable=False
    )

    # Document identity
    series_year: Mapped[int] = mapped_column(Integer, nullable=False)
    series_number: Mapped[int] = mapped_column(Integer, nullable=False)
    full_document_number: Mapped[str] = mapped_column(String(30), nullable=False)
    invoice_date: Mapped[date] = mapped_column(Date, nullable=False)
    system_entry_date: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    # Customer
    customer_nif: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    customer_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    # Amount
    gross_total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    # Settled invoices (JSON array of {invoice_id, document_number, amount_applied})
    settled_documents: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)

    # Hash chain
    hash_code: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    previous_hash: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Status: normal or A (Anulado) for reversed payments
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="N")  # N=Normal, A=Anulado
    reversal_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    reversal_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    issued_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )

    # AGT transmission
    transmission_status: Mapped[str] = mapped_column(String(20), nullable=False, default="not_required")

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Payments ────────────────────────────────────────────────────────────────

class Payment(Base):
    """Payment record — linked to invoices via PaymentAllocation."""
    __tablename__ = "payments"
    __table_args__ = (
        CheckConstraint("amount >= 0", name="ck_payments_amount_positive"),
        UniqueConstraint("school_id", "idempotency_key", name="uq_payments_idempotency_key"),
        Index("ix_payments_school_id", "school_id"),
        Index("ix_payments_billing_guardian_id", "billing_guardian_id"),
        Index("ix_payments_payment_date", "payment_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    received_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )

    payment_date: Mapped[date] = mapped_column(Date, nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    payment_method: Mapped[str] = mapped_column(String(50), nullable=False)
    # cash, transfer, check, card, multicaixa, credit
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    receipt_proof_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    # Status
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="normal")
    # normal, reversed, pending_review
    reverse_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    reversed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    # Idempotency & references
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    payment_reference_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payment_references.id", ondelete="SET NULL"),
        nullable=True, unique=True
    )
    cash_session_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("cash_sessions.id", ondelete="SET NULL"), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    allocations = relationship("PaymentAllocation", back_populates="payment", cascade="all, delete-orphan")


class PaymentAllocation(Base):
    """Links a payment to invoices it settles (partial or full)."""
    __tablename__ = "payment_allocations"
    __table_args__ = (
        Index("ix_payment_allocations_invoice_id", "invoice_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    payment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payments.id", ondelete="CASCADE"), nullable=False
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="RESTRICT"), nullable=False
    )
    amount_applied: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)

    payment = relationship("Payment", back_populates="allocations")
    invoice = relationship("Invoice", back_populates="payment_links")


# ─── Payment References (Multicaixa) ────────────────────────────────────────

class PaymentReference(Base):
    """Multicaixa payment reference (20.11)."""
    __tablename__ = "payment_references"
    __table_args__ = (
        UniqueConstraint("provider", "external_id", name="uq_payment_refs_provider_external"),
        Index("ix_payment_references_school_id", "school_id"),
        Index("ix_payment_references_invoice_id", "invoice_id"),
        Index("ix_payment_references_status", "school_id", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    invoice_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )

    entity: Mapped[str] = mapped_column(String(10), nullable=False)  # 5-digit Multicaixa entity
    reference: Mapped[str] = mapped_column(String(20), nullable=False)  # 9-digit reference
    amount: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True)  # null = open amount
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    # active, paid, expired, cancelled
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    provider: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")
    # manual, proxypay, appypay, emis_gpo
    external_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)


# ─── Credit Balances (20.12) ─────────────────────────────────────────────────

class CreditEntry(Base):
    """Ledger entry for guardian credit balance."""
    __tablename__ = "credit_entries"
    __table_args__ = (
        Index("ix_credit_entries_guardian_id", "billing_guardian_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    source: Mapped[str] = mapped_column(String(30), nullable=False)
    # payment_surplus, refund_reversal, manual_adjustment
    source_payment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payments.id", ondelete="SET NULL"), nullable=True
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    amount_remaining: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    is_reversed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CreditRefund(Base):
    """Records a refund of credit balance to guardian."""
    __tablename__ = "credit_refunds"
    __table_args__ = (
        Index("ix_credit_refunds_guardian_id", "billing_guardian_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    method: Mapped[str] = mapped_column(String(50), nullable=False)
    reference: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    authorised_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Cash Sessions (20.14) ───────────────────────────────────────────────────

class CashSession(Base):
    """Daily cash register session."""
    __tablename__ = "cash_sessions"
    __table_args__ = (
        Index("ix_cash_sessions_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    opened_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    opening_float: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, default=Decimal("0"))
    closed_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="SET NULL"), nullable=True
    )
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    expected_by_method: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)
    counted_by_method: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)
    variance: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True)
    variance_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="open")  # open, closed


# ─── Payment Plans (20.15) ───────────────────────────────────────────────────

class PaymentPlan(Base):
    """Payment arrangement covering overdue invoices."""
    __tablename__ = "payment_plans"
    __table_args__ = (
        Index("ix_payment_plans_school_id", "school_id"),
        Index("ix_payment_plans_guardian_id", "billing_guardian_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    invoice_ids: Mapped[Any] = mapped_column(JSONB, nullable=False)  # list of invoice UUIDs
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    # active, completed, breached, cancelled
    total_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    installments = relationship("PaymentPlanInstallment", back_populates="plan",
                                cascade="all, delete-orphan", order_by="PaymentPlanInstallment.due_date")


class PaymentPlanInstallment(Base):
    __tablename__ = "payment_plan_installments"
    __table_args__ = (
        Index("ix_pp_installments_plan_id", "plan_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    plan_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("payment_plans.id", ondelete="CASCADE"), nullable=False
    )
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    # pending, met, missed
    paid_at: Mapped[Optional[date]] = mapped_column(Date, nullable=True)

    plan = relationship("PaymentPlan", back_populates="installments")


# ─── Dunning / Reminders (20.16) ─────────────────────────────────────────────

class ReminderLog(Base):
    __tablename__ = "reminder_logs"
    __table_args__ = (
        Index("ix_reminder_logs_school_id", "school_id"),
        Index("ix_reminder_logs_guardian_id", "billing_guardian_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    invoice_ids: Mapped[Any] = mapped_column(JSONB, nullable=False)
    level: Mapped[int] = mapped_column(Integer, nullable=False)  # 1, 2, 3
    channel: Mapped[str] = mapped_column(String(20), nullable=False)
    # whatsapp, email, sms, letter, verbal
    sent_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    message_snapshot: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


# ─── Finance Audit Log (20.19) ───────────────────────────────────────────────

class FinanceAuditEntry(Base):
    """Immutable, append-only audit log for sensitive finance actions."""
    __tablename__ = "finance_audit_entries"
    __table_args__ = (
        Index("ix_finance_audit_school_id", "school_id"),
        Index("ix_finance_audit_entity", "entity_type", "entity_id"),
        Index("ix_finance_audit_timestamp", "timestamp"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    actor_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    action: Mapped[str] = mapped_column(String(50), nullable=False)
    before_snapshot: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)
    after_snapshot: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)
    reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


# ─── Expenses (unchanged from original, kept here for completeness) ──────────

class ExpenseCategory(Base):
    __tablename__ = "expense_categories"
    __table_args__ = (
        UniqueConstraint("school_id", "name", name="uq_expense_category_school_name"),
        Index("ix_expense_categories_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class Expense(Base):
    __tablename__ = "expenses"
    __table_args__ = (
        CheckConstraint("amount >= 0", name="ck_expenses_amount_positive"),
        Index("ix_expenses_school_id", "school_id"),
        Index("ix_expenses_expense_date", "expense_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    category_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("expense_categories.id", ondelete="RESTRICT"), nullable=False
    )
    registered_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    school_year_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="SET NULL"), nullable=True
    )
    description: Mapped[str] = mapped_column(String(500), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    expense_date: Mapped[date] = mapped_column(Date, nullable=False)
    vendor: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    payment_method: Mapped[Optional[str]] = mapped_column(String(50))
    reference: Mapped[Optional[str]] = mapped_column(String(255))
    receipt_url: Mapped[Optional[str]] = mapped_column(String(500))
    notes: Mapped[Optional[str]] = mapped_column(Text)
    is_voided: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    void_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    category = relationship("ExpenseCategory")
