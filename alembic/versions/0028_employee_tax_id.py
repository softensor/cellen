"""Add the employee tax identifier required by payroll reporting.

Revision ID: 0028
Revises: 0027
"""

from alembic import op
import sqlalchemy as sa


revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("employees", sa.Column("tax_id", sa.String(length=30), nullable=True))
    op.create_unique_constraint(
        "uq_employees_school_tax_id", "employees", ["school_id", "tax_id"]
    )


def downgrade() -> None:
    op.drop_constraint("uq_employees_school_tax_id", "employees", type_="unique")
    op.drop_column("employees", "tax_id")
