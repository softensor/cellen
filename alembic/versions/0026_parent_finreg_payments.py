"""Link parent payment review records to Finreg documents.

Revision ID: 0026
Revises: cf47f07b691e
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0026"
down_revision = "cf47f07b691e"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "payments",
        sa.Column("finreg_document_external_reference", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "payments",
        sa.Column("finreg_payment_external_reference", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_index(
        "ix_payments_finreg_document_external_reference",
        "payments",
        ["finreg_document_external_reference"],
    )
    op.create_unique_constraint(
        "uq_payments_finreg_payment_external_reference",
        "payments",
        ["finreg_payment_external_reference"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_payments_finreg_payment_external_reference", "payments", type_="unique"
    )
    op.drop_index("ix_payments_finreg_document_external_reference", table_name="payments")
    op.drop_column("payments", "finreg_payment_external_reference")
    op.drop_column("payments", "finreg_document_external_reference")
