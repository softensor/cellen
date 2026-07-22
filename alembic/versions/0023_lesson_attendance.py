"""lesson_attendance table for K-12 livro de ponto

Revision ID: 0023
Revises: 0022
Create Date: 2026-07-22
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "lesson_attendance",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", UUID(as_uuid=True), sa.ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("schedule_id", UUID(as_uuid=True), sa.ForeignKey("schedules.id", ondelete="CASCADE"), nullable=False),
        sa.Column("subject_id", UUID(as_uuid=True), sa.ForeignKey("subjects.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("employee_id", UUID(as_uuid=True), sa.ForeignKey("employees.id", ondelete="SET NULL"), nullable=True),
        sa.Column("date", sa.Date, nullable=False),
        sa.Column("period_id", UUID(as_uuid=True), sa.ForeignKey("timetable_periods.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("child_id", UUID(as_uuid=True), sa.ForeignKey("children.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="present"),
        sa.Column("notes", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint(
            "schedule_id", "subject_id", "date", "period_id", "child_id",
            name="uq_lesson_attendance_session_student",
        ),
    )
    op.create_index("ix_lesson_attendance_school_id", "lesson_attendance", ["school_id"])
    op.create_index("ix_lesson_attendance_schedule_date", "lesson_attendance", ["schedule_id", "date"])
    op.create_index("ix_lesson_attendance_child_id", "lesson_attendance", ["child_id"])


def downgrade() -> None:
    op.drop_index("ix_lesson_attendance_child_id", table_name="lesson_attendance")
    op.drop_index("ix_lesson_attendance_schedule_date", table_name="lesson_attendance")
    op.drop_index("ix_lesson_attendance_school_id", table_name="lesson_attendance")
    op.drop_table("lesson_attendance")
