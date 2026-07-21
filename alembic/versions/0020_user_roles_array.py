"""Replace users.role (str) with users.roles (TEXT[] array)

Revision ID: 0020
Revises: 0019

Migrates single-role string column to a TEXT ARRAY, enabling multi-role users.
Existing rows are migrated: role -> ARRAY[role].
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = '0020'
down_revision: str = '0019'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add new roles array column (nullable first so we can populate)
    op.add_column(
        'users',
        sa.Column('roles', postgresql.ARRAY(sa.Text()), nullable=True),
    )
    # 2. Populate from existing role column
    op.execute("UPDATE users SET roles = ARRAY[role]::text[]")
    # 3. Set NOT NULL now that it's populated
    op.alter_column('users', 'roles', nullable=False)
    # 4. Drop old column
    op.drop_column('users', 'role')


def downgrade() -> None:
    op.add_column(
        'users',
        sa.Column('role', sa.String(50), nullable=True),
    )
    op.execute("UPDATE users SET role = roles[1]")
    op.alter_column('users', 'role', nullable=False)
    op.drop_column('users', 'roles')
