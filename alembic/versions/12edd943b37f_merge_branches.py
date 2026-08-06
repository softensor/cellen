"""merge_branches

Revision ID: 12edd943b37f
Revises: 0021, 582e5711a4d5
Create Date: 2026-07-21 22:36:50.441446

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '12edd943b37f'
down_revision: Union[str, None] = ('0021', '582e5711a4d5')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
