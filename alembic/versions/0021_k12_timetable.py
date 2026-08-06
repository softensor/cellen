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
    # Grade-domain tables were introduced with the K-12 models but were
    # accidentally omitted from the original migration. They must precede the
    # schedule_slots.subject_id FK and migration 0024's later extensions.
    op.create_table(
        'subjects',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('school_id', UUID(as_uuid=True), sa.ForeignKey('schools.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('name', sa.String(150), nullable=False),
        sa.Column('code', sa.String(20)), sa.Column('order', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('school_id', 'name', name='uq_subjects_school_name'),
    )
    op.create_index('ix_subjects_school_id', 'subjects', ['school_id'])
    op.create_table(
        'turma_subjects',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('school_id', UUID(as_uuid=True), sa.ForeignKey('schools.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('turma_id', UUID(as_uuid=True), sa.ForeignKey('turmas.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('subject_id', UUID(as_uuid=True), sa.ForeignKey('subjects.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('school_year_id', UUID(as_uuid=True), sa.ForeignKey('school_years.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('teacher_id', UUID(as_uuid=True), sa.ForeignKey('employees.id', ondelete='SET NULL')),
        sa.Column('is_locked', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('school_id', 'turma_id', 'subject_id', 'school_year_id', name='uq_turma_subject_year'),
    )
    op.create_index('ix_turma_subjects_school_id', 'turma_subjects', ['school_id'])
    op.create_index('ix_turma_subjects_turma_year', 'turma_subjects', ['turma_id', 'school_year_id'])
    op.create_table(
        'marks',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('school_id', UUID(as_uuid=True), sa.ForeignKey('schools.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('enrollment_id', UUID(as_uuid=True), sa.ForeignKey('enrollments.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('subject_id', UUID(as_uuid=True), sa.ForeignKey('subjects.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('trimester', sa.Integer(), nullable=False),
        sa.Column('mac_grade', sa.Numeric(4, 1)), sa.Column('exam_grade', sa.Numeric(4, 1)),
        sa.Column('final_grade', sa.Numeric(4, 1)), sa.Column('notes', sa.String(500)),
        sa.Column('recorded_by', UUID(as_uuid=True), sa.ForeignKey('employees.id', ondelete='SET NULL')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('enrollment_id', 'subject_id', 'trimester', name='uq_mark_enrollment_subject_trimester'),
        sa.CheckConstraint('trimester IN (1, 2, 3)', name='ck_marks_trimester'),
        sa.CheckConstraint('mac_grade IS NULL OR (mac_grade >= 0 AND mac_grade <= 20)', name='ck_marks_mac'),
        sa.CheckConstraint('exam_grade IS NULL OR (exam_grade >= 0 AND exam_grade <= 20)', name='ck_marks_exam'),
        sa.CheckConstraint('final_grade IS NULL OR (final_grade >= 0 AND final_grade <= 20)', name='ck_marks_final'),
    )
    op.create_index('ix_marks_school_id', 'marks', ['school_id'])
    op.create_index('ix_marks_enrollment_id', 'marks', ['enrollment_id'])
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
    op.drop_table('marks')
    op.drop_table('turma_subjects')
    op.drop_table('subjects')
