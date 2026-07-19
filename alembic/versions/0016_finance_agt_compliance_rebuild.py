"""Finance AGT compliance rebuild — new schema per spec 20.x

Revision ID: 0016
Revises: 0015
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ─── Drop old tables that are being replaced ──────────────────────────────
    # Drop in correct FK order
    op.drop_table("payment_invoices") if _table_exists("payment_invoices") else None
    op.drop_table("receipts") if _table_exists("receipts") else None
    op.drop_table("credit_notes") if _table_exists("credit_notes") else None
    op.drop_table("payments") if _table_exists("payments") else None
    op.drop_table("invoices") if _table_exists("invoices") else None
    op.drop_table("contracts") if _table_exists("contracts") else None
    op.drop_table("billing_items") if _table_exists("billing_items") else None
    op.drop_table("document_series") if _table_exists("document_series") else None

    # ─── Document Series ──────────────────────────────────────────────────────
    op.create_table(
        "document_series",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("document_type", sa.String(5), nullable=False),
        sa.Column("year", sa.Integer, nullable=False),
        sa.Column("next_number", sa.Integer, nullable=False, server_default="1"),
        sa.Column("last_hash", sa.Text, nullable=True),
        sa.Column("last_invoice_date", sa.Date, nullable=True),
        sa.Column("last_system_entry_date", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("school_id", "document_type", "year", name="uq_document_series_school_type_year"),
    )
    op.create_index("ix_document_series_school_id", "document_series", ["school_id"])

    # ─── Billing Items ────────────────────────────────────────────────────────
    op.create_table(
        "billing_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("code", sa.String(50), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("unit_price", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("iva_exemption_reason", sa.String(10), nullable=True),
        sa.Column("iva_exemption_legend", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "code", name="uq_billing_items_school_code"),
    )
    op.create_index("ix_billing_items_school_id", "billing_items", ["school_id"])

    # ─── Billing Item Prices ──────────────────────────────────────────────────
    op.create_table(
        "billing_item_prices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("billing_items.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("school_years.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("unit_price", sa.Numeric(12, 2), nullable=False),
        sa.UniqueConstraint("billing_item_id", "school_year_id", name="uq_billing_item_price_item_year"),
    )
    op.create_index("ix_billing_item_prices_school_id", "billing_item_prices", ["school_id"])

    # ─── Contracts ────────────────────────────────────────────────────────────
    op.create_table(
        "contracts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("children.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="SET NULL"), nullable=True),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True),
        sa.Column("service_name", sa.String(255), nullable=True),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("unit_price", sa.Numeric(12, 2), nullable=True),
        sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("discount_percent", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("discount_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("billing_cycle", sa.String(20), nullable=False, server_default="monthly"),
        sa.Column("day_of_month", sa.Integer, nullable=False, server_default="1"),
        sa.Column("start_date", sa.Date, nullable=False),
        sa.Column("end_date", sa.Date, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("auto_invoice", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("last_invoiced_month", sa.Date, nullable=True),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_contracts_school_id", "contracts", ["school_id"])
    op.create_index("ix_contracts_child_id", "contracts", ["child_id"])

    # ─── Cash Sessions ────────────────────────────────────────────────────────
    op.create_table(
        "cash_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("opened_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("opening_float", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("closed_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expected_by_method", postgresql.JSONB, nullable=True),
        sa.Column("counted_by_method", postgresql.JSONB, nullable=True),
        sa.Column("variance", sa.Numeric(12, 2), nullable=True),
        sa.Column("variance_reason", sa.Text, nullable=True),
        sa.Column("status", sa.String(10), nullable=False, server_default="open"),
    )
    op.create_index("ix_cash_sessions_school_id", "cash_sessions", ["school_id"])

    # ─── Invoices ─────────────────────────────────────────────────────────────
    op.create_table(
        "invoices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("document_type", sa.String(5), nullable=False, server_default="FT"),
        sa.Column("series_year", sa.Integer, nullable=False),
        sa.Column("series_number", sa.Integer, nullable=False),
        sa.Column("full_document_number", sa.String(30), nullable=False),
        sa.Column("invoice_date", sa.Date, nullable=False),
        sa.Column("system_entry_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("due_date", sa.Date, nullable=True),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="SET NULL"), nullable=True),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("children.id", ondelete="SET NULL"), nullable=True),
        sa.Column("customer_nif", sa.String(30), nullable=True),
        sa.Column("customer_name", sa.String(255), nullable=True),
        sa.Column("is_final_consumer", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("gross_total", sa.Numeric(12, 2), nullable=False),
        sa.Column("net_total", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("iva_total", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("hash_code", sa.Text, nullable=True),
        sa.Column("previous_hash", sa.Text, nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("is_void", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("void_reason", sa.Text, nullable=True),
        sa.Column("corrected_invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True),
        sa.Column("correction_reason", sa.Text, nullable=True),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("school_years.id", ondelete="SET NULL"), nullable=True),
        sa.Column("reference_month", sa.Date, nullable=True),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("transmission_status", sa.String(20), nullable=False, server_default="not_required"),
        sa.Column("transmission_response", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "full_document_number", name="uq_invoices_school_doc_number"),
    )
    op.create_index("ix_invoices_school_id", "invoices", ["school_id"])
    op.create_index("ix_invoices_billing_guardian_id", "invoices", ["billing_guardian_id"])
    op.create_index("ix_invoices_status", "invoices", ["school_id", "status"])

    # ─── Invoice Lines ────────────────────────────────────────────────────────
    op.create_table(
        "invoice_lines",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="CASCADE"), nullable=False),
        sa.Column("line_number", sa.Integer, nullable=False),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True),
        sa.Column("description", sa.String(500), nullable=False),
        sa.Column("quantity", sa.Numeric(10, 3), nullable=False, server_default="1"),
        sa.Column("unit_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("discount_percent", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("discount_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("iva_exemption_reason", sa.String(10), nullable=True),
        sa.Column("iva_exemption_legend", sa.Text, nullable=True),
        sa.Column("line_net", sa.Numeric(12, 2), nullable=False),
        sa.Column("iva_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("line_total", sa.Numeric(12, 2), nullable=False),
        sa.Column("credited_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.CheckConstraint("NOT (discount_percent > 0 AND discount_amount > 0)", name="ck_invoice_lines_discount_exclusive"),
    )
    op.create_index("ix_invoice_lines_invoice_id", "invoice_lines", ["invoice_id"])

    # ─── Credit Notes ─────────────────────────────────────────────────────────
    op.create_table(
        "credit_notes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("series_year", sa.Integer, nullable=False),
        sa.Column("series_number", sa.Integer, nullable=False),
        sa.Column("full_document_number", sa.String(30), nullable=False),
        sa.Column("invoice_date", sa.Date, nullable=False),
        sa.Column("system_entry_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("customer_nif", sa.String(30), nullable=True),
        sa.Column("customer_name", sa.String(255), nullable=True),
        sa.Column("net_total", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("iva_total", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("gross_total", sa.Numeric(12, 2), nullable=False),
        sa.Column("reason", sa.Text, nullable=False),
        sa.Column("lines", postgresql.JSONB, nullable=True),
        sa.Column("hash_code", sa.Text, nullable=True),
        sa.Column("previous_hash", sa.Text, nullable=True),
        sa.Column("transmission_status", sa.String(20), nullable=False, server_default="not_required"),
        sa.Column("transmission_response", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "full_document_number", name="uq_credit_notes_school_doc_number"),
    )
    op.create_index("ix_credit_notes_school_id", "credit_notes", ["school_id"])
    op.create_index("ix_credit_notes_invoice_id", "credit_notes", ["invoice_id"])

    # ─── Payment References ───────────────────────────────────────────────────
    op.create_table(
        "payment_references",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("entity", sa.String(10), nullable=False),
        sa.Column("reference", sa.String(20), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("provider", sa.String(20), nullable=False, server_default="manual"),
        sa.Column("external_id", sa.String(255), nullable=True),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("provider", "external_id", name="uq_payment_refs_provider_external"),
    )
    op.create_index("ix_payment_references_school_id", "payment_references", ["school_id"])
    op.create_index("ix_payment_references_invoice_id", "payment_references", ["invoice_id"])
    op.create_index("ix_payment_references_status", "payment_references", ["school_id", "status"])

    # ─── Payments ─────────────────────────────────────────────────────────────
    op.create_table(
        "payments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("received_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("payment_date", sa.Date, nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("payment_method", sa.String(50), nullable=False),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("receipt_proof_url", sa.String(500), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="normal"),
        sa.Column("reverse_reason", sa.Text, nullable=True),
        sa.Column("reversed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("idempotency_key", sa.String(255), nullable=True),
        sa.Column("payment_reference_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("payment_references.id", ondelete="SET NULL"), nullable=True, unique=True),
        sa.Column("cash_session_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("cash_sessions.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("amount >= 0", name="ck_payments_amount_positive"),
        sa.UniqueConstraint("school_id", "idempotency_key", name="uq_payments_idempotency_key"),
    )
    op.create_index("ix_payments_school_id", "payments", ["school_id"])
    op.create_index("ix_payments_billing_guardian_id", "payments", ["billing_guardian_id"])
    op.create_index("ix_payments_payment_date", "payments", ["payment_date"])

    # ─── Payment Allocations ──────────────────────────────────────────────────
    op.create_table(
        "payment_allocations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("payments.id", ondelete="CASCADE"), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("amount_applied", sa.Numeric(12, 2), nullable=False),
    )
    op.create_index("ix_payment_allocations_invoice_id", "payment_allocations", ["invoice_id"])

    # ─── Receipts ─────────────────────────────────────────────────────────────
    op.create_table(
        "receipts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("payments.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("series_year", sa.Integer, nullable=False),
        sa.Column("series_number", sa.Integer, nullable=False),
        sa.Column("full_document_number", sa.String(30), nullable=False),
        sa.Column("invoice_date", sa.Date, nullable=False),
        sa.Column("system_entry_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("customer_nif", sa.String(30), nullable=True),
        sa.Column("customer_name", sa.String(255), nullable=True),
        sa.Column("gross_total", sa.Numeric(12, 2), nullable=False),
        sa.Column("settled_documents", postgresql.JSONB, nullable=True),
        sa.Column("hash_code", sa.Text, nullable=True),
        sa.Column("previous_hash", sa.Text, nullable=True),
        sa.Column("status", sa.String(10), nullable=False, server_default="N"),
        sa.Column("reversal_date", sa.Date, nullable=True),
        sa.Column("reversal_reason", sa.Text, nullable=True),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("transmission_status", sa.String(20), nullable=False, server_default="not_required"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "full_document_number", name="uq_receipts_school_doc_number"),
    )
    op.create_index("ix_receipts_school_id", "receipts", ["school_id"])
    op.create_index("ix_receipts_payment_id", "receipts", ["payment_id"])

    # ─── Credit Entries ───────────────────────────────────────────────────────
    op.create_table(
        "credit_entries",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("source", sa.String(30), nullable=False),
        sa.Column("source_payment_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("payments.id", ondelete="SET NULL"), nullable=True),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("amount_remaining", sa.Numeric(12, 2), nullable=False),
        sa.Column("is_reversed", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_credit_entries_guardian_id", "credit_entries", ["billing_guardian_id"])

    # ─── Credit Refunds ───────────────────────────────────────────────────────
    op.create_table(
        "credit_refunds",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("method", sa.String(50), nullable=False),
        sa.Column("reference", sa.String(255), nullable=True),
        sa.Column("authorised_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_credit_refunds_guardian_id", "credit_refunds", ["billing_guardian_id"])

    # ─── Payment Plans ────────────────────────────────────────────────────────
    op.create_table(
        "payment_plans",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("invoice_ids", postgresql.JSONB, nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_payment_plans_school_id", "payment_plans", ["school_id"])
    op.create_index("ix_payment_plans_guardian_id", "payment_plans", ["billing_guardian_id"])

    op.create_table(
        "payment_plan_installments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("plan_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("payment_plans.id", ondelete="CASCADE"), nullable=False),
        sa.Column("due_date", sa.Date, nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
    )
    op.create_index("ix_pp_installments_plan_id", "payment_plan_installments", ["plan_id"])

    # ─── Reminder Logs ────────────────────────────────────────────────────────
    op.create_table(
        "reminder_logs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("invoice_ids", postgresql.JSONB, nullable=False),
        sa.Column("level", sa.Integer, nullable=False),
        sa.Column("channel", sa.String(20), nullable=False),
        sa.Column("sent_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("message_snapshot", sa.Text, nullable=True),
    )
    op.create_index("ix_reminder_logs_school_id", "reminder_logs", ["school_id"])
    op.create_index("ix_reminder_logs_guardian_id", "reminder_logs", ["billing_guardian_id"])

    # ─── Finance Audit Log ────────────────────────────────────────────────────
    op.create_table(
        "finance_audit_entries",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("entity_type", sa.String(50), nullable=False),
        sa.Column("entity_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("action", sa.String(50), nullable=False),
        sa.Column("before_snapshot", postgresql.JSONB, nullable=True),
        sa.Column("after_snapshot", postgresql.JSONB, nullable=True),
        sa.Column("reason", sa.Text, nullable=True),
    )
    op.create_index("ix_finance_audit_school_id", "finance_audit_entries", ["school_id"])
    op.create_index("ix_finance_audit_entity", "finance_audit_entries", ["entity_type", "entity_id"])
    op.create_index("ix_finance_audit_timestamp", "finance_audit_entries", ["timestamp"])


def downgrade() -> None:
    # Drop all new tables in reverse order
    op.drop_table("finance_audit_entries")
    op.drop_table("reminder_logs")
    op.drop_table("payment_plan_installments")
    op.drop_table("payment_plans")
    op.drop_table("credit_refunds")
    op.drop_table("credit_entries")
    op.drop_table("receipts")
    op.drop_table("payment_allocations")
    op.drop_table("payments")
    op.drop_table("payment_references")
    op.drop_table("credit_notes")
    op.drop_table("invoice_lines")
    op.drop_table("invoices")
    op.drop_table("cash_sessions")
    op.drop_table("contracts")
    op.drop_table("billing_item_prices")
    op.drop_table("billing_items")
    op.drop_table("document_series")


def _table_exists(table_name: str) -> bool:
    """Check if table exists (for safe drops)."""
    from sqlalchemy import inspect
    conn = op.get_bind()
    insp = inspect(conn)
    return table_name in insp.get_table_names()
