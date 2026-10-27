"""Platform settings: the owner console's principia-pay activation.

Revision ID: 0036
Revises: 0035

The rail was env-only: turning it on (and rotating its product token) meant
an SSH edit and a restart. This table is the single row the owner console's
Pagamentos screen writes instead. Absence of the row means "never configured
from the console", so the environment token keeps working as a startup
fallback until the first activation.

The token is stored encrypted; only its identifying prefix is a column.
"""

import sqlalchemy as sa

from alembic import op

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "platform_settings",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column(
            "principia_pay_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("principia_pay_token_ciphertext", sa.Text(), nullable=True),
        sa.Column("principia_pay_token_prefix", sa.String(12), nullable=True),
        sa.Column(
            "principia_pay_status",
            sa.String(20),
            nullable=False,
            server_default="not_configured",
        ),
        sa.Column("principia_pay_last_error", sa.String(1000), nullable=True),
        sa.Column(
            "principia_pay_last_checked_at", sa.DateTime(timezone=True), nullable=True
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("platform_settings")
