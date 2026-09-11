"""Separate Finreg selection and repair attendance auditing.

Revision ID: 0031
Revises: 0030
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Carry the old switch value to the explicit Finreg selector, then keep the
    # common payment area enabled so it can host either mutually exclusive mode.
    op.execute("""
        UPDATE schools
        SET features = jsonb_set(
            jsonb_set(
                COALESCE(features, '{}'::jsonb),
                '{finreg}',
                COALESCE(features->'finance', 'true'::jsonb),
                true
            ),
            '{finance}',
            'true'::jsonb,
            true
        )
    """)

    for table in ("attendance", "attendance_logs", "attendance_day_statuses"):
        op.alter_column(
            table,
            "recorded_by",
            existing_type=postgresql.UUID(as_uuid=True),
            nullable=True,
        )
        op.add_column(
            table,
            sa.Column("recorded_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        )
        op.create_foreign_key(
            f"fk_{table}_recorded_by_user_id_users",
            table,
            "users",
            ["recorded_by_user_id"],
            ["id"],
            ondelete="SET NULL",
        )
        op.execute(f"""
            UPDATE {table} AS attendance_row
            SET recorded_by_user_id = users.id
            FROM users
            WHERE users.employee_id = attendance_row.recorded_by
              AND users.school_id = attendance_row.school_id
        """)


def downgrade() -> None:
    for table in ("attendance_day_statuses", "attendance_logs", "attendance"):
        op.drop_constraint(
            f"fk_{table}_recorded_by_user_id_users", table, type_="foreignkey"
        )
        op.drop_column(table, "recorded_by_user_id")
        # Keep recorded_by nullable so rollback never destroys attendance rows
        # created by administrators without employee profiles.

    op.execute("""
        UPDATE schools
        SET features = (COALESCE(features, '{}'::jsonb) - 'finreg') ||
                       jsonb_build_object(
                           'finance', COALESCE(features->'finreg', 'true'::jsonb)
                       )
    """)
