"""Finance spec alignment — add missing columns per spec 20.x

Revision ID: 0017
Revises: 0016

Adds:
- billing_items.category
- expense_categories.is_active
- expenses.vendor
- payment_plans.total_amount
- payment_plan_installments.paid_at
- contracts.school_year_id, quantity, status
- Changes invoices.transmission_response from Text to JSONB
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ─── Billing Items: add category ───────────────────────────────────────
    op.add_column(
        "billing_items",
        sa.Column("category", sa.String(50), nullable=True),
    )

    # ─── Expense Categories: add is_active ─────────────────────────────────
    op.add_column(
        "expense_categories",
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
    )

    # ─── Expenses: add vendor ──────────────────────────────────────────────
    op.add_column(
        "expenses",
        sa.Column("vendor", sa.String(200), nullable=True),
    )

    # ─── Payment Plans: add total_amount ───────────────────────────────────
    op.add_column(
        "payment_plans",
        sa.Column("total_amount", sa.Numeric(12, 2), nullable=True),
    )

    # ─── Payment Plan Installments: add paid_at ────────────────────────────
    op.add_column(
        "payment_plan_installments",
        sa.Column("paid_at", sa.Date(), nullable=True),
    )

    # ─── Contracts: add school_year_id, quantity, status ───────────────────
    op.add_column(
        "contracts",
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_contracts_school_year_id",
        "contracts",
        "school_years",
        ["school_year_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.add_column(
        "contracts",
        sa.Column("quantity", sa.Numeric(8, 2), nullable=False, server_default="1"),
    )
    op.add_column(
        "contracts",
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
    )

    # ─── Invoices: change transmission_response from Text to JSONB ─────────
    op.alter_column(
        "invoices",
        "transmission_response",
        existing_type=sa.Text(),
        type_=postgresql.JSONB(),
        existing_nullable=True,
        postgresql_using="transmission_response::jsonb",
    )


def downgrade() -> None:
    # ─── Invoices: revert transmission_response ────────────────────────────
    op.alter_column(
        "invoices",
        "transmission_response",
        existing_type=postgresql.JSONB(),
        type_=sa.Text(),
        existing_nullable=True,
    )

    # ─── Contracts: drop status, quantity, school_year_id ──────────────────
    op.drop_column("contracts", "status")
    op.drop_column("contracts", "quantity")
    op.drop_constraint("fk_contracts_school_year_id", "contracts", type_="foreignkey")
    op.drop_column("contracts", "school_year_id")

    # ─── Payment Plan Installments: drop paid_at ───────────────────────────
    op.drop_column("payment_plan_installments", "paid_at")

    # ─── Payment Plans: drop total_amount ──────────────────────────────────
    op.drop_column("payment_plans", "total_amount")

    # ─── Expenses: drop vendor ─────────────────────────────────────────────
    op.drop_column("expenses", "vendor")

    # ─── Expense Categories: drop is_active ────────────────────────────────
    op.drop_column("expense_categories", "is_active")

    # ─── Billing Items: drop category ──────────────────────────────────────
    op.drop_column("billing_items", "category")
