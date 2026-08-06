"""merge_branches

Revision ID: 0a0c7aac8122
Revises: 1fa0081bfea6
Create Date: 2026-07-23 09:44:44.997366

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0a0c7aac8122'
down_revision: Union[str, None] = '1fa0081bfea6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
