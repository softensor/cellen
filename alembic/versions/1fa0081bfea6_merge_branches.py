"""merge_branches

Revision ID: 1fa0081bfea6
Revises: 0024, 4ac3e42728d3
Create Date: 2026-07-23 09:40:58.556311

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1fa0081bfea6'
down_revision: Union[str, None] = ('0024', '4ac3e42728d3')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
