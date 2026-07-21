"""Add K-12 timetable: timetable_periods table + K-12 fields on schedule_slots

Revision ID: 0021
Revises: 0020

- New table: timetable_periods (school period templates: number, name, start/end time, is_break)
- New columns on schedule_slots: subject_id, employee_id, room, period_id
  (preschool continues to use activity_id; K-12 uses these new columns)
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = '0021'
down_revision: str = '0020'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. timetable_periods ─────────────────────────────────────────────────
    op.create_table(
        'timetable_periods',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('school_id', UUID(as_uuid=True), sa.ForeignKey('schools.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('period_number', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(50), nullable=False),
        sa.Column('start_time', sa.Time(), nullable=False),
        sa.Column('end_time', sa.Time(), nullable=False),
        sa.Column('is_break', sa.Boolean(), nullable=False, server_default='false'),
    )
    op.create_unique_constraint(
        'uq_timetable_periods_school_num',
        'timetable_periods',
        ['school_id', 'period_number'],
    )
    op.create_index('ix_timetable_periods_school_id', 'timetable_periods', ['school_id'])

    # ── 2. schedule_slots: K-12 columns ─────────────────────────────────────
    op.add_column(
        'schedule_slots',
        sa.Column('subject_id', UUID(as_uuid=True),
                  sa.ForeignKey('subjects.id', ondelete='RESTRICT'), nullable=True),
    )
    op.add_column(
        'schedule_slots',
        sa.Column('employee_id', UUID(as_uuid=True),
                  sa.ForeignKey('employees.id', ondelete='SET NULL'), nullable=True),
    )
    op.add_column(
        'schedule_slots',
        sa.Column('room', sa.String(50), nullable=True),
    )
    op.add_column(
        'schedule_slots',
        sa.Column('period_id', UUID(as_uuid=True),
                  sa.ForeignKey('timetable_periods.id', ondelete='SET NULL'), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('schedule_slots', 'period_id')
    op.drop_column('schedule_slots', 'room')
    op.drop_column('schedule_slots', 'employee_id')
    op.drop_column('schedule_slots', 'subject_id')

    op.drop_index('ix_timetable_periods_school_id', table_name='timetable_periods')
    op.drop_constraint('uq_timetable_periods_school_num', 'timetable_periods', type_='unique')
    op.drop_table('timetable_periods')
