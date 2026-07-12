"""Add pickup_authorizations and meal_orders tables

Revision ID: 0006
Revises: 0005
Create Date: 2026-07-12 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "pickup_authorizations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("authorized_name", sa.VARCHAR(255), nullable=False),
        sa.Column("relationship", sa.VARCHAR(100), nullable=True),
        sa.Column("phone", sa.VARCHAR(50), nullable=True),
        sa.Column("id_card_number", sa.VARCHAR(100), nullable=True),
        sa.Column("notes", sa.TEXT, nullable=True),
        sa.Column("is_active", sa.BOOLEAN, nullable=False, server_default=sa.text("true")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
    )
    op.create_index("ix_pickup_authorizations_school_id", "pickup_authorizations", ["school_id"])
    op.create_index("ix_pickup_authorizations_child_id", "pickup_authorizations", ["child_id"])

    op.create_table(
        "meal_orders",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("order_date", sa.DATE, nullable=False),
        sa.Column("meal_type", sa.VARCHAR(50), nullable=False, server_default="lunch"),
        sa.Column("ordered", sa.BOOLEAN, nullable=False, server_default=sa.text("true")),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("school_id", "child_id", "order_date", "meal_type",
                            name="uq_meal_order_child_date_type"),
    )
    op.create_index("ix_meal_orders_school_id", "meal_orders", ["school_id"])
    op.create_index("ix_meal_orders_order_date", "meal_orders", ["order_date"])


def downgrade() -> None:
    op.drop_table("meal_orders")
    op.drop_table("pickup_authorizations")
