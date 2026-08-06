"""merge_branches

Revision ID: 582e5711a4d5
Revises: 0019, d1d9d890e325
Create Date: 2026-07-21 21:06:57.978243

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '582e5711a4d5'
down_revision: Union[str, None] = ('0019', 'd1d9d890e325')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
