"""merge Finreg integration with production history

Revision ID: cf47f07b691e
Revises: 0025, 0a0c7aac8122
Create Date: 2026-08-06 19:18:08.494832

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cf47f07b691e'
down_revision: Union[str, None] = ('0025', '0a0c7aac8122')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
