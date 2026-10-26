"""Link an enrollment to its FinReg fee-billing instruction.

Revision ID: 0033
Revises: 0032
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0033"
down_revision = "0032"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "enrollments",
        sa.Column("fee_instruction_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_enrollments_fee_instruction",
        "enrollments",
        "finreg_billing_instructions",
        ["fee_instruction_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_enrollments_fee_instruction_id",
        "enrollments",
        ["fee_instruction_id"],
    )
    # 0027 backfilled the rows it saw; schools created between 0027 and the
    # seed fix still carry an ungoverned item, which 2.1a now refuses.
    op.execute(
        """
        UPDATE billing_items
        SET finreg_tax_option_code = CASE
          WHEN iva_rate = 0 AND iva_exemption_reason IS NOT NULL THEN 'IVA_ISE'
          WHEN iva_rate = 14 THEN 'IVA_NOR'
          ELSE NULL
        END
        WHERE finreg_tax_option_code IS NULL
        """
    )


def downgrade() -> None:
    op.drop_index("ix_enrollments_fee_instruction_id", table_name="enrollments")
    op.drop_constraint(
        "fk_enrollments_fee_instruction", "enrollments", type_="foreignkey"
    )
    op.drop_column("enrollments", "fee_instruction_id")
