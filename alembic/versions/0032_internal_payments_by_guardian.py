"""Index internal payment controls by their paying guardian.

Revision ID: 0032
Revises: 0031
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "internal_payment_controls",
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_internal_payments_billing_guardian_guardians",
        "internal_payment_controls",
        "guardians",
        ["billing_guardian_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index(
        "ix_internal_payments_school_guardian",
        "internal_payment_controls",
        ["school_id", "billing_guardian_id"],
    )
    # Existing charges were attached to pupils. Preserve them and identify the
    # payer from the primary guardian, falling back to the oldest valid link.
    op.execute("""
        UPDATE internal_payment_controls AS payment
        SET billing_guardian_id = (
            SELECT link.guardian_id
            FROM child_guardians AS link
            WHERE link.school_id = payment.school_id
              AND link.child_id = payment.child_id
            ORDER BY link.is_primary_contact DESC, link.id ASC
            LIMIT 1
        )
        WHERE payment.billing_guardian_id IS NULL
          AND payment.child_id IS NOT NULL
    """)


def downgrade() -> None:
    op.drop_index(
        "ix_internal_payments_school_guardian",
        table_name="internal_payment_controls",
    )
    op.drop_constraint(
        "fk_internal_payments_billing_guardian_guardians",
        "internal_payment_controls",
        type_="foreignkey",
    )
    op.drop_column("internal_payment_controls", "billing_guardian_id")
