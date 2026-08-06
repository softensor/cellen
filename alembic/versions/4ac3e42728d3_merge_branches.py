"""merge_branches

Revision ID: 4ac3e42728d3
Revises: 0023, bc8ced28c534
Create Date: 2026-07-22 12:03:37.752280

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4ac3e42728d3'
down_revision: Union[str, None] = ('0023', 'bc8ced28c534')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
