"""Fee automation: policy, modalities, transport, student profiles, runs.

Revision ID: 0034
Revises: 0033
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "school_fee_policies",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("default_tuition_billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("default_enrollment_fee", sa.Numeric(12, 2), nullable=True),
        sa.Column("sibling_discount_pct", sa.Numeric(5, 2), nullable=False),
        sa.Column("sibling_discount_min_children", sa.Integer(), nullable=False),
        sa.Column("sibling_discount_scope", sa.String(30), nullable=False),
        sa.Column("due_days", sa.Integer(), nullable=False),
        sa.Column("billing_day", sa.Integer(), nullable=False),
        sa.Column("auto_generate", sa.Boolean(), nullable=False),
        sa.Column("proration_policy", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(
            ["default_tuition_billing_item_id"], ["billing_items.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("school_id", "school_year_id", name="uq_fee_policy_school_year"),
        sa.CheckConstraint(
            "sibling_discount_pct >= 0 AND sibling_discount_pct <= 100",
            name="ck_fee_policy_sibling_pct",
        ),
        sa.CheckConstraint(
            "sibling_discount_min_children >= 1", name="ck_fee_policy_sibling_min"
        ),
        sa.CheckConstraint(
            "sibling_discount_scope IN ('additional_children', 'all_children')",
            name="ck_fee_policy_sibling_scope",
        ),
        sa.CheckConstraint("billing_day >= 1 AND billing_day <= 31", name="ck_fee_policy_billing_day"),
        sa.CheckConstraint("due_days >= 0 AND due_days <= 365", name="ck_fee_policy_due_days"),
        sa.CheckConstraint(
            "proration_policy IN ('pro_rata_days', 'full_month', 'no_charge')",
            name="ck_fee_policy_proration",
        ),
    )
    op.create_index("ix_school_fee_policies_school_id", "school_fee_policies", ["school_id"])

    op.create_table(
        "extracurricular_modalities",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("inscription_fee", sa.Numeric(12, 2), nullable=False),
        sa.Column("monthly_fee", sa.Numeric(12, 2), nullable=False),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["billing_item_id"], ["billing_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("school_id", "name", name="uq_modality_school_name"),
        sa.CheckConstraint("inscription_fee >= 0", name="ck_modality_inscription_fee"),
        sa.CheckConstraint("monthly_fee >= 0", name="ck_modality_monthly_fee"),
    )
    op.create_index(
        "ix_extracurricular_modalities_school_id", "extracurricular_modalities", ["school_id"]
    )

    op.create_table(
        "student_modality_enrollments",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("modality_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("inscription_instruction_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("inscription_invoice_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["modality_id"], ["extracurricular_modalities.id"], ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["inscription_instruction_id"], ["finreg_billing_instructions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["inscription_invoice_id"], ["invoices.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "child_id", "modality_id", "start_date", name="uq_modality_enrollment_start"
        ),
        sa.CheckConstraint(
            "status IN ('active', 'ended', 'withdrawn')", name="ck_modality_enrollment_status"
        ),
    )
    op.create_index(
        "ix_modality_enrollments_school_child",
        "student_modality_enrollments",
        ["school_id", "child_id"],
    )

    op.create_table(
        "transport_routes",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("monthly_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["billing_item_id"], ["billing_items.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("school_id", "name", name="uq_transport_route_school_name"),
        sa.CheckConstraint("monthly_price >= 0", name="ck_transport_route_price"),
    )
    op.create_index("ix_transport_routes_school_id", "transport_routes", ["school_id"])

    op.create_table(
        "student_transport_assignments",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("route_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["route_id"], ["transport_routes.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("child_id", "start_date", name="uq_transport_assignment_start"),
        sa.CheckConstraint(
            "status IN ('active', 'ended', 'withdrawn')", name="ck_transport_assignment_status"
        ),
    )
    op.create_index(
        "ix_transport_assignments_school_child",
        "student_transport_assignments",
        ["school_id", "child_id"],
    )

    op.create_table(
        "student_finance_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("billing_guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("tuition_billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("tuition_override", sa.Numeric(12, 2), nullable=True),
        sa.Column("billing_day", sa.Integer(), nullable=True),
        sa.Column("plan_external_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("plan_revision", sa.String(32), nullable=True),
        sa.Column("plan_next_run_date", sa.Date(), nullable=True),
        sa.Column("plan_stale", sa.Boolean(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("starts_on", sa.Date(), nullable=True),
        sa.Column("ends_on", sa.Date(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["billing_guardian_id"], ["guardians.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(
            ["tuition_billing_item_id"], ["billing_items.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("child_id", "school_year_id", name="uq_student_finance_profile"),
        sa.UniqueConstraint(
            "school_id", "plan_external_id", name="uq_student_finance_plan_external"
        ),
        sa.CheckConstraint(
            "status IN ('active', 'paused', 'withdrawn')",
            name="ck_student_finance_profile_status",
        ),
        sa.CheckConstraint(
            "tuition_override IS NULL OR tuition_override >= 0",
            name="ck_student_finance_tuition_override",
        ),
        sa.CheckConstraint(
            "billing_day IS NULL OR (billing_day >= 1 AND billing_day <= 31)",
            name="ck_student_finance_billing_day",
        ),
    )
    op.create_index(
        "ix_student_finance_profiles_school_id", "student_finance_profiles", ["school_id"]
    )
    op.create_index(
        "ix_student_finance_profiles_guardian",
        "student_finance_profiles",
        ["school_id", "billing_guardian_id"],
    )

    op.create_table(
        "billing_runs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("billing_month", sa.String(7), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False),
        sa.Column("stats", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("requested_by", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["requested_by"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "school_id", "school_year_id", "billing_month", name="uq_billing_run_month"
        ),
        sa.CheckConstraint(
            "status IN ('preview', 'composing', 'running', 'completed', "
            "'partial_failed', 'failed')",
            name="ck_billing_run_status",
        ),
    )
    op.create_index("ix_billing_runs_school_month", "billing_runs", ["school_id", "billing_month"])


def downgrade() -> None:
    op.drop_index("ix_billing_runs_school_month", table_name="billing_runs")
    op.drop_table("billing_runs")
    op.drop_index(
        "ix_student_finance_profiles_guardian", table_name="student_finance_profiles"
    )
    op.drop_index(
        "ix_student_finance_profiles_school_id", table_name="student_finance_profiles"
    )
    op.drop_table("student_finance_profiles")
    op.drop_index(
        "ix_transport_assignments_school_child", table_name="student_transport_assignments"
    )
    op.drop_table("student_transport_assignments")
    op.drop_index("ix_transport_routes_school_id", table_name="transport_routes")
    op.drop_table("transport_routes")
    op.drop_index(
        "ix_modality_enrollments_school_child", table_name="student_modality_enrollments"
    )
    op.drop_table("student_modality_enrollments")
    op.drop_index(
        "ix_extracurricular_modalities_school_id", table_name="extracurricular_modalities"
    )
    op.drop_table("extracurricular_modalities")
    op.drop_index("ix_school_fee_policies_school_id", table_name="school_fee_policies")
    op.drop_table("school_fee_policies")
