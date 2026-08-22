"""Align required workflow columns with the application models.

Revision ID: 0029
Revises: 0028
"""

from alembic import op


revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None


TIMESTAMP_COLUMNS = {
    "lesson_attendance": ("created_at", "updated_at"),
    "timetable_requirements": ("created_at", "updated_at"),
    "website_media": ("created_at",),
    "website_pages": ("created_at", "updated_at"),
    "website_sections": ("created_at", "updated_at"),
    "website_settings": ("updated_at",),
}


def upgrade() -> None:
    for table, columns in TIMESTAMP_COLUMNS.items():
        for column in columns:
            op.execute(
                f'UPDATE "{table}" SET "{column}" = now() '
                f'WHERE "{column}" IS NULL'
            )
            op.execute(
                f'ALTER TABLE "{table}" ALTER COLUMN "{column}" SET NOT NULL'
            )
    op.execute(
        "UPDATE website_pages SET is_published = false "
        "WHERE is_published IS NULL"
    )
    op.execute(
        "ALTER TABLE website_pages ALTER COLUMN is_published SET NOT NULL"
    )
    op.execute(
        "UPDATE website_sections SET sort_order = 0 WHERE sort_order IS NULL"
    )
    op.execute(
        "ALTER TABLE website_sections ALTER COLUMN sort_order SET NOT NULL"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE website_sections ALTER COLUMN sort_order DROP NOT NULL"
    )
    op.execute(
        "ALTER TABLE website_pages ALTER COLUMN is_published DROP NOT NULL"
    )
    for table, columns in reversed(tuple(TIMESTAMP_COLUMNS.items())):
        for column in reversed(columns):
            op.execute(
                f'ALTER TABLE "{table}" ALTER COLUMN "{column}" DROP NOT NULL'
            )
