"""Cellen's local read model of FinReg fiscal documents.

Revision ID: 0038
Revises: 0037

Cellen's admin finance screens list and search FinReg documents natively
instead of launching FinReg's own UI. Every value in this table was returned
by FinReg; Cellen never computes a number, total or status of its own.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "finreg_documents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id"), nullable=False),
        sa.Column("finreg_document_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reference", sa.String(255), nullable=False),
        sa.Column(
            "instruction_id", postgresql.UUID(as_uuid=True),
            sa.ForeignKey("finreg_billing_instructions.id", ondelete="SET NULL"),
        ),
        sa.Column("kind", sa.String(20), nullable=False, server_default="invoice"),
        sa.Column("document_type", sa.String(40)),
        sa.Column("full_document_number", sa.String(80)),
        sa.Column("document_status", sa.String(20), nullable=False, server_default="draft"),
        sa.Column("agt_status", sa.String(40)),
        sa.Column("agt_message", sa.Text()),
        sa.Column("currency_code", sa.String(3), nullable=False, server_default="AOA"),
        sa.Column("net_total", sa.Numeric(18, 2)),
        sa.Column("tax_total", sa.Numeric(18, 2)),
        sa.Column("gross_total", sa.Numeric(18, 2)),
        sa.Column("document_date", sa.Date()),
        sa.Column("due_date", sa.Date()),
        sa.Column("customer_name", sa.String(255)),
        sa.Column("customer_tax_id", sa.String(40)),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True)),
        sa.Column("pupil_id", postgresql.UUID(as_uuid=True)),
        sa.Column("billing_period", sa.String(7)),
        sa.Column("corrects_document_id", postgresql.UUID(as_uuid=True)),
        sa.Column("corrected_by_document_id", postgresql.UUID(as_uuid=True)),
        sa.Column("snapshot", postgresql.JSONB()),
        sa.Column("needs_refresh", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("refresh_attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("refreshed_at", sa.DateTime(timezone=True)),
        sa.Column("last_error_code", sa.String(80)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "finreg_document_id", name="uq_finreg_document_school"),
    )
    op.create_index("ix_finreg_document_listing", "finreg_documents", ["school_id", "document_date"])
    op.create_index("ix_finreg_document_refresh", "finreg_documents", ["needs_refresh", "refreshed_at"])


def downgrade() -> None:
    op.drop_index("ix_finreg_document_refresh", table_name="finreg_documents")
    op.drop_index("ix_finreg_document_listing", table_name="finreg_documents")
    op.drop_table("finreg_documents")
