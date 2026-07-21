"""Add school segment and features columns

Revision ID: 0019
Revises: 0018

Adds:
- schools.segment VARCHAR(30) NOT NULL DEFAULT 'preschool'
- schools.features JSONB NULL
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision: str = '0019'
down_revision: str = '0018'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'schools',
        sa.Column(
            'segment',
            sa.String(30),
            nullable=False,
            server_default='preschool',
        ),
    )
    op.add_column(
        'schools',
        sa.Column('features', JSONB, nullable=True),
    )


def downgrade() -> None:
    op.drop_column('schools', 'features')
    op.drop_column('schools', 'segment')
