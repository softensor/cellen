"""Add non-fiscal internal payment controls.

Revision ID: 0030
Revises: 0029
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0030"
down_revision = "0029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "internal_payment_controls",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("enrollment_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("category", sa.String(length=40), nullable=False),
        sa.Column("description", sa.String(length=255), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("payment_method", sa.String(length=30), nullable=True),
        sa.Column("payment_date", sa.Date(), nullable=True),
        sa.Column("proof_url", sa.String(length=500), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("review_note", sa.Text(), nullable=True),
        sa.Column("reviewed_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["enrollment_id"], ["enrollments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["billing_item_id"], ["billing_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("enrollment_id", name="uq_internal_payment_enrollment"),
        sa.CheckConstraint("amount > 0", name="ck_internal_payment_amount_positive"),
        sa.CheckConstraint(
            "status IN ('pending', 'proof_submitted', 'paid', 'rejected')",
            name="ck_internal_payment_status",
        ),
    )
    op.create_index(
        "ix_internal_payments_school_status",
        "internal_payment_controls",
        ["school_id", "status"],
    )
    op.execute("""
        INSERT INTO internal_payment_controls
            (id, school_id, enrollment_id, child_id, category, description,
             amount, status, created_at, updated_at)
        SELECT gen_random_uuid(), school_id, id, child_id, 'enrollment',
               'Taxa de Matrícula', enrollment_fee, 'pending', now(), now()
        FROM enrollments
        WHERE enrollment_fee > 0 AND fee_invoice_id IS NULL
        ON CONFLICT (enrollment_id) DO NOTHING
    """)


def downgrade() -> None:
    op.drop_index("ix_internal_payments_school_status", table_name="internal_payment_controls")
    op.drop_table("internal_payment_controls")
