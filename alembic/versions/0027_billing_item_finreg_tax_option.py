"""Persist the governed Finreg tax treatment selected for a school service.

Revision ID: 0027
Revises: 0026
"""

from alembic import op
import sqlalchemy as sa


revision = "0027"
down_revision = "0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "billing_items",
        sa.Column("finreg_tax_option_code", sa.String(20), nullable=True),
    )
    op.execute(
        """
        UPDATE billing_items
        SET finreg_tax_option_code = CASE
          WHEN iva_rate = 0 AND iva_exemption_reason IS NOT NULL THEN 'IVA_ISE'
          WHEN iva_rate = 14 THEN 'IVA_NOR'
          ELSE NULL
        END
        """
    )


def downgrade() -> None:
    op.drop_column("billing_items", "finreg_tax_option_code")
