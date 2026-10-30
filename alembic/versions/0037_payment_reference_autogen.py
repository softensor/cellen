"""Auto-issue a principia-pay reference when a monthly bill is emitted.

Revision ID: 0037
Revises: 0036

A confirmed ``billing_run`` instruction is one finalized FinReg document.
For schools whose rail connection is active, the dispatcher now opens one
reference per open document so the family can pay without an admin having
to press "Gerar referência". These columns record that attempt on the
instruction itself: the rail is an external system, so the pass must retry a
temporary failure, never retry a settled debt, and never repeat a create
that already succeeded.

The reference id is a foreign key so deleting a reference cannot leave a
dangling id behind.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "finreg_billing_instructions",
        sa.Column("payment_reference_status", sa.String(20), nullable=True),
    )
    op.add_column(
        "finreg_billing_instructions",
        sa.Column("payment_reference_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "finreg_billing_instructions",
        sa.Column("payment_reference_error", sa.String(300), nullable=True),
    )
    op.add_column(
        "finreg_billing_instructions",
        sa.Column(
            "payment_reference_attempts",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )
    op.add_column(
        "finreg_billing_instructions",
        sa.Column(
            "payment_reference_next_attempt_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "fk_finreg_instruction_payment_reference",
        "finreg_billing_instructions",
        "payment_references",
        ["payment_reference_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_finreg_instruction_reference",
        "finreg_billing_instructions",
        ["school_id", "payment_reference_status", "payment_reference_next_attempt_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_finreg_instruction_reference", table_name="finreg_billing_instructions")
    op.drop_constraint(
        "fk_finreg_instruction_payment_reference",
        "finreg_billing_instructions",
        type_="foreignkey",
    )
    op.drop_column("finreg_billing_instructions", "payment_reference_next_attempt_at")
    op.drop_column("finreg_billing_instructions", "payment_reference_attempts")
    op.drop_column("finreg_billing_instructions", "payment_reference_error")
    op.drop_column("finreg_billing_instructions", "payment_reference_id")
    op.drop_column("finreg_billing_instructions", "payment_reference_status")
