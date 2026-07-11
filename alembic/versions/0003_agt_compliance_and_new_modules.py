"""AGT compliance and new modules: document series, receipts, credit notes, contracts,
announcements, documents library, appointments, child evaluations, health events

Revision ID: 0003
Revises: 0002
Create Date: 2025-01-03 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # ALTER TABLE: schools — add AGT fields
    # -------------------------------------------------------------------------
    op.add_column("schools", sa.Column("nif", sa.String(30), nullable=True))
    op.add_column("schools", sa.Column("legal_name", sa.String(255), nullable=True))
    op.add_column("schools", sa.Column("agt_series_prefix", sa.String(10), nullable=True, server_default="CE"))

    # address may already exist — use try/except
    try:
        op.add_column("schools", sa.Column("address", sa.String(500), nullable=True))
    except Exception:
        pass

    # -------------------------------------------------------------------------
    # ALTER TABLE: guardians — add NIF
    # -------------------------------------------------------------------------
    op.add_column("guardians", sa.Column("nif", sa.String(30), nullable=True))

    # -------------------------------------------------------------------------
    # ALTER TABLE: invoices — add AGT fields
    # -------------------------------------------------------------------------
    op.add_column("invoices", sa.Column("document_type", sa.String(5), nullable=False, server_default="FT"))
    op.add_column("invoices", sa.Column("series_year", sa.Integer(), nullable=True))
    op.add_column("invoices", sa.Column("series_number", sa.Integer(), nullable=True))
    op.add_column("invoices", sa.Column("full_document_number", sa.String(30), nullable=True))
    op.add_column("invoices", sa.Column("nif_cliente", sa.String(30), nullable=True))
    op.add_column("invoices", sa.Column("taxable_base", sa.Numeric(10, 2), nullable=False, server_default="0"))
    op.add_column("invoices", sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="14.00"))
    op.add_column("invoices", sa.Column("iva_amount", sa.Numeric(10, 2), nullable=False, server_default="0"))
    op.add_column("invoices", sa.Column("hash_code", sa.String(64), nullable=True))
    op.add_column("invoices", sa.Column("previous_hash", sa.String(64), nullable=True))
    op.add_column("invoices", sa.Column("is_void", sa.Boolean(), nullable=False, server_default=sa.text("false")))
    op.add_column("invoices", sa.Column("void_reason", sa.Text(), nullable=True))

    # -------------------------------------------------------------------------
    # NEW TABLE: document_series
    # -------------------------------------------------------------------------
    op.create_table(
        "document_series",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("document_type", sa.String(5), nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("next_number", sa.Integer(), nullable=False, server_default="1"),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "document_type", "year", name="uq_document_series_school_type_year"),
    )
    op.create_index("ix_document_series_school_id", "document_series", ["school_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: receipts
    # -------------------------------------------------------------------------
    op.create_table(
        "receipts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("series_year", sa.Integer(), nullable=False),
        sa.Column("series_number", sa.Integer(), nullable=False),
        sa.Column("full_document_number", sa.String(30), nullable=False),
        sa.Column("nif_cliente", sa.String(30), nullable=True),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("hash_code", sa.String(64), nullable=True),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["issued_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "full_document_number", name="uq_receipts_school_doc_number"),
    )
    op.create_index("ix_receipts_school_id", "receipts", ["school_id"])
    op.create_index("ix_receipts_payment_id", "receipts", ["payment_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: credit_notes
    # -------------------------------------------------------------------------
    op.create_table(
        "credit_notes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("series_year", sa.Integer(), nullable=False),
        sa.Column("series_number", sa.Integer(), nullable=False),
        sa.Column("full_document_number", sa.String(30), nullable=False),
        sa.Column("nif_cliente", sa.String(30), nullable=True),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("taxable_base", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="14.00"),
        sa.Column("iva_amount", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("total_amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("hash_code", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["issued_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "full_document_number", name="uq_credit_notes_school_doc_number"),
    )
    op.create_index("ix_credit_notes_school_id", "credit_notes", ["school_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: contracts
    # -------------------------------------------------------------------------
    op.create_table(
        "contracts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("service_name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("iva_rate", sa.Numeric(5, 2), nullable=False, server_default="14.00"),
        sa.Column("billing_cycle", sa.String(20), nullable=False, server_default="monthly"),
        sa.Column("day_of_month", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("auto_invoice", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("last_invoiced_month", sa.Date(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["guardian_id"], ["guardians.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_contracts_school_id", "contracts", ["school_id"])
    op.create_index("ix_contracts_child_id", "contracts", ["child_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: announcements
    # -------------------------------------------------------------------------
    op.create_table(
        "announcements",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("attachment_url", sa.String(500), nullable=True),
        sa.Column("attachment_name", sa.String(255), nullable=True),
        sa.Column("target", sa.String(20), nullable=False, server_default="all"),
        sa.Column("pinned", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["created_by"], ["employees.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_announcements_school_id", "announcements", ["school_id"])
    op.create_index("ix_announcements_created_at", "announcements", ["created_at"])

    # -------------------------------------------------------------------------
    # NEW TABLE: documents_library
    # -------------------------------------------------------------------------
    op.create_table(
        "documents_library",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("uploaded_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("file_url", sa.String(500), nullable=False),
        sa.Column("file_name", sa.String(255), nullable=False),
        sa.Column("file_type", sa.String(50), nullable=True),
        sa.Column("category", sa.String(100), nullable=True),
        sa.Column("target", sa.String(20), nullable=False, server_default="all"),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["uploaded_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_documents_library_school_id", "documents_library", ["school_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: appointments
    # -------------------------------------------------------------------------
    op.create_table(
        "appointments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("requested_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("proposed_date", sa.Date(), nullable=False),
        sa.Column("proposed_time", sa.Time(), nullable=True),
        sa.Column("confirmed_date", sa.Date(), nullable=True),
        sa.Column("confirmed_time", sa.Time(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("response_notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["requested_by"], ["users.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["employee_id"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_appointments_school_id", "appointments", ["school_id"])
    op.create_index("ix_appointments_employee_id", "appointments", ["employee_id"])
    op.create_index("ix_appointments_requested_by", "appointments", ["requested_by"])

    # -------------------------------------------------------------------------
    # NEW TABLE: child_evaluations
    # -------------------------------------------------------------------------
    op.create_table(
        "child_evaluations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("evaluated_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("evaluation_period", sa.String(50), nullable=False),
        sa.Column("evaluation_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("cognitive", sa.Integer(), nullable=True),
        sa.Column("motor", sa.Integer(), nullable=True),
        sa.Column("language", sa.Integer(), nullable=True),
        sa.Column("social_emotional", sa.Integer(), nullable=True),
        sa.Column("creativity", sa.Integer(), nullable=True),
        sa.Column("autonomy", sa.Integer(), nullable=True),
        sa.Column("overall_rating", sa.String(20), nullable=True),
        sa.Column("observations", sa.Text(), nullable=True),
        sa.Column("areas_to_improve", sa.Text(), nullable=True),
        sa.Column("objectives_next_period", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["evaluated_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="SET NULL"),
        sa.UniqueConstraint(
            "school_id", "child_id", "evaluation_period", "school_year_id",
            name="uq_child_evaluation_period"
        ),
    )
    op.create_index("ix_child_evaluations_school_id", "child_evaluations", ["school_id"])
    op.create_index("ix_child_evaluations_child_id", "child_evaluations", ["child_id"])

    # -------------------------------------------------------------------------
    # NEW TABLE: health_events
    # -------------------------------------------------------------------------
    op.create_table(
        "health_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("recorded_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("event_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("event_time", sa.Time(), nullable=True),
        sa.Column("event_type", sa.String(50), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("temperature", sa.Numeric(4, 1), nullable=True),
        sa.Column("medication_given", sa.String(255), nullable=True),
        sa.Column("parent_notified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("parent_notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("action_taken", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["recorded_by"], ["employees.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_health_events_school_id", "health_events", ["school_id"])
    op.create_index("ix_health_events_child_id", "health_events", ["child_id"])
    op.create_index("ix_health_events_event_date", "health_events", ["event_date"])

    # -------------------------------------------------------------------------
    # ALTER TABLE: cadernetas — add new fields
    # -------------------------------------------------------------------------
    op.add_column("cadernetas", sa.Column("behavior", sa.String(50), nullable=True))
    op.add_column("cadernetas", sa.Column("activities", sa.Text(), nullable=True))
    op.add_column("cadernetas", sa.Column("health_observations", sa.Text(), nullable=True))


def downgrade() -> None:
    # Remove caderneta columns
    op.drop_column("cadernetas", "health_observations")
    op.drop_column("cadernetas", "activities")
    op.drop_column("cadernetas", "behavior")

    # Drop new tables
    op.drop_table("health_events")
    op.drop_table("child_evaluations")
    op.drop_table("appointments")
    op.drop_table("documents_library")
    op.drop_table("announcements")
    op.drop_table("contracts")
    op.drop_table("credit_notes")
    op.drop_table("receipts")
    op.drop_table("document_series")

    # Remove invoice columns
    op.drop_column("invoices", "void_reason")
    op.drop_column("invoices", "is_void")
    op.drop_column("invoices", "previous_hash")
    op.drop_column("invoices", "hash_code")
    op.drop_column("invoices", "iva_amount")
    op.drop_column("invoices", "iva_rate")
    op.drop_column("invoices", "taxable_base")
    op.drop_column("invoices", "nif_cliente")
    op.drop_column("invoices", "full_document_number")
    op.drop_column("invoices", "series_number")
    op.drop_column("invoices", "series_year")
    op.drop_column("invoices", "document_type")

    # Remove guardian columns
    op.drop_column("guardians", "nif")

    # Remove school columns
    op.drop_column("schools", "agt_series_prefix")
    op.drop_column("schools", "legal_name")
    op.drop_column("schools", "nif")
