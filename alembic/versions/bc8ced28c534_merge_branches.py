"""merge_branches

Revision ID: bc8ced28c534
Revises: 0022, 12edd943b37f
Create Date: 2026-07-22 08:56:40.768371

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'bc8ced28c534'
down_revision: Union[str, None] = ('0022', '12edd943b37f')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
