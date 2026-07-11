"""initial schema

Revision ID: 0001
Revises:
Create Date: 2025-01-01 00:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable pgcrypto for gen_random_uuid() — safe to run even if already enabled
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # -------------------------------------------------------------------------
    # PLATFORM LEVEL
    # -------------------------------------------------------------------------

    op.create_table(
        "schools",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("slug", sa.String(100), nullable=False),
        sa.Column("address", sa.String(500), nullable=True),
        sa.Column("city", sa.String(100), nullable=True),
        sa.Column("country", sa.String(10), nullable=False, server_default="CV"),
        sa.Column("phone", sa.String(50), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("logo_url", sa.String(500), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("subscription_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("subscription_notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("slug", name="uq_schools_slug"),
    )

    op.create_table(
        "platform_users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("email", name="uq_platform_users_email"),
    )

    # -------------------------------------------------------------------------
    # EMPLOYEES  (before users — users FK to employees)
    # -------------------------------------------------------------------------

    op.create_table(
        "employees",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("first_name", sa.String(100), nullable=False),
        sa.Column("middle_name", sa.String(100), nullable=True),
        sa.Column("last_name", sa.String(100), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column("place_of_birth", sa.String(255), nullable=True),
        sa.Column("sex", sa.String(1), nullable=True),
        sa.Column("civil_state", sa.String(50), nullable=True),
        sa.Column("nationality", sa.String(100), nullable=True),
        sa.Column("naturality", sa.String(100), nullable=True),
        sa.Column("height", sa.Numeric(5, 2), nullable=True),
        sa.Column("profession", sa.String(255), nullable=True),
        sa.Column("qualifications", sa.String(255), nullable=True),
        sa.Column("id_card_number", sa.String(100), nullable=True),
        sa.Column("photo_url", sa.String(500), nullable=True),
        sa.Column("street", sa.String(255), nullable=True),
        sa.Column("house_number", sa.String(50), nullable=True),
        sa.Column("building_number", sa.String(50), nullable=True),
        sa.Column("apt_number", sa.String(50), nullable=True),
        sa.Column("city", sa.String(100), nullable=True),
        sa.Column("municipio", sa.String(100), nullable=True),
        sa.Column("bairro", sa.String(100), nullable=True),
        sa.Column("mobile_first", sa.String(50), nullable=True),
        sa.Column("mobile_second", sa.String(50), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("employee_type", sa.String(50), nullable=False),
        sa.Column("position", sa.String(255), nullable=True),
        sa.Column("title_academic", sa.String(255), nullable=True),
        sa.Column("social_security", sa.String(100), nullable=True),
        sa.Column("contract_type", sa.String(50), nullable=True),
        sa.Column("hire_date", sa.Date(), nullable=True),
        sa.Column("salary", sa.Numeric(10, 2), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("privilege", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "id_card_number", name="uq_employees_school_idcard"),
    )
    op.create_index("ix_employees_school_id", "employees", ["school_id"])

    # -------------------------------------------------------------------------
    # GUARDIANS  (before users — users FK to guardians)
    # -------------------------------------------------------------------------

    op.create_table(
        "guardians",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("first_name", sa.String(100), nullable=False),
        sa.Column("middle_name", sa.String(100), nullable=True),
        sa.Column("last_name", sa.String(100), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column("place_of_birth", sa.String(255), nullable=True),
        sa.Column("sex", sa.String(1), nullable=True),
        sa.Column("civil_state", sa.String(50), nullable=True),
        sa.Column("nationality", sa.String(100), nullable=True),
        sa.Column("naturality", sa.String(100), nullable=True),
        sa.Column("profession", sa.String(255), nullable=True),
        sa.Column("qualifications", sa.String(255), nullable=True),
        sa.Column("id_card_number", sa.String(100), nullable=True),
        sa.Column("photo_url", sa.String(500), nullable=True),
        sa.Column("street", sa.String(255), nullable=True),
        sa.Column("house_number", sa.String(50), nullable=True),
        sa.Column("building_number", sa.String(50), nullable=True),
        sa.Column("apt_number", sa.String(50), nullable=True),
        sa.Column("city", sa.String(100), nullable=True),
        sa.Column("municipio", sa.String(100), nullable=True),
        sa.Column("bairro", sa.String(100), nullable=True),
        sa.Column("mobile_first", sa.String(50), nullable=True),
        sa.Column("mobile_second", sa.String(50), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_guardians_school_id", "guardians", ["school_id"])

    # -------------------------------------------------------------------------
    # USERS
    # -------------------------------------------------------------------------

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("username", sa.String(100), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", sa.String(50), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("last_login", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["employee_id"], ["employees.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["guardian_id"], ["guardians.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("school_id", "username", name="uq_users_school_username"),
    )
    op.create_index("ix_users_school_id", "users", ["school_id"])

    # -------------------------------------------------------------------------
    # CHILDREN
    # -------------------------------------------------------------------------

    op.create_table(
        "children",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("cedula", sa.String(100), nullable=False),
        sa.Column("first_name", sa.String(100), nullable=False),
        sa.Column("middle_name", sa.String(100), nullable=True),
        sa.Column("last_name", sa.String(100), nullable=False),
        sa.Column("birth_date", sa.Date(), nullable=True),
        sa.Column("place_of_birth", sa.String(255), nullable=True),
        sa.Column("sex", sa.String(1), nullable=True),
        sa.Column("nationality", sa.String(100), nullable=True),
        sa.Column("naturality", sa.String(100), nullable=True),
        sa.Column("height", sa.Numeric(5, 2), nullable=True),
        sa.Column("special_needs", sa.String(500), nullable=True),
        sa.Column("medical_prescription", sa.String(500), nullable=True),
        sa.Column("photo_url", sa.String(500), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("street", sa.String(255), nullable=True),
        sa.Column("house_number", sa.String(50), nullable=True),
        sa.Column("building_number", sa.String(50), nullable=True),
        sa.Column("apt_number", sa.String(50), nullable=True),
        sa.Column("city", sa.String(100), nullable=True),
        sa.Column("municipio", sa.String(100), nullable=True),
        sa.Column("bairro", sa.String(100), nullable=True),
        sa.Column("emergency_contact_name", sa.String(255), nullable=True),
        sa.Column("emergency_contact_phone", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "cedula", name="uq_children_school_cedula"),
    )
    op.create_index("ix_children_school_id", "children", ["school_id"])

    # -------------------------------------------------------------------------
    # CHILD-GUARDIAN JUNCTION
    # -------------------------------------------------------------------------

    op.create_table(
        "child_guardians",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("relationship_type", sa.String(50), nullable=False),
        sa.Column("is_primary_contact", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["guardian_id"], ["guardians.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("child_id", "guardian_id", name="uq_child_guardian"),
    )

    # -------------------------------------------------------------------------
    # ACADEMIC — school_years, turmas, activities, schedules, slots, enrollments
    # -------------------------------------------------------------------------

    op.create_table(
        "school_years",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("year_label", sa.String(20), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "year_label", name="uq_school_years_school_label"),
    )
    op.create_index("ix_school_years_school_id", "school_years", ["school_id"])

    op.create_table(
        "turmas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("level", sa.String(100), nullable=False),
        sa.Column("room", sa.String(100), nullable=True),
        sa.Column("max_capacity", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_turmas_school_id", "turmas", ["school_id"])

    op.create_table(
        "activities",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_activities_school_id", "activities", ["school_id"])

    op.create_table(
        "schedules",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("turma_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["turma_id"], ["turmas.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "turma_id", "school_year_id", name="uq_schedule_turma_year"),
    )
    op.create_index("ix_schedules_school_id", "schedules", ["school_id"])

    op.create_table(
        "schedule_teachers",
        sa.Column("schedule_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(["schedule_id"], ["schedules.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["employee_id"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("schedule_id", "employee_id"),
    )
    op.create_index("ix_schedule_teachers_school_id", "schedule_teachers", ["school_id"])

    op.create_table(
        "schedule_slots",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("schedule_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("day_of_week", sa.Integer(), nullable=False),
        sa.Column("slot_time", sa.Time(), nullable=False),
        sa.Column("activity_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["schedule_id"], ["schedules.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["activity_id"], ["activities.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("schedule_id", "day_of_week", "slot_time", name="uq_schedule_slot_day_time"),
    )
    op.create_index("ix_schedule_slots_school_id", "schedule_slots", ["school_id"])

    op.create_table(
        "enrollments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("schedule_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("enrollment_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("status", sa.String(20), nullable=False, server_default="active"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["schedule_id"], ["schedules.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "child_id", "school_year_id", name="uq_enrollment_child_year"),
    )
    op.create_index("ix_enrollments_school_id", "enrollments", ["school_id"])

    # -------------------------------------------------------------------------
    # CADERNETA
    # -------------------------------------------------------------------------

    op.create_table(
        "cadernetas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("teacher_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("report_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("breakfast_rating", sa.String(50), nullable=True),
        sa.Column("lunch_rating", sa.String(50), nullable=True),
        sa.Column("snack_rating", sa.String(50), nullable=True),
        sa.Column("physiological_needs", sa.String(50), nullable=True),
        sa.Column("had_nap", sa.Boolean(), nullable=True),
        sa.Column("sensorial_motor_development", sa.String(255), nullable=True),
        sa.Column("intellectual_development", sa.String(255), nullable=True),
        sa.Column("social_development", sa.String(255), nullable=True),
        sa.Column("affective_development", sa.String(255), nullable=True),
        sa.Column("general_observations", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["teacher_id"], ["employees.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "child_id", "report_date", name="uq_caderneta_child_date"),
    )
    op.create_index("ix_cadernetas_school_id", "cadernetas", ["school_id"])
    op.create_index("ix_cadernetas_child_id", "cadernetas", ["child_id"])
    op.create_index("ix_cadernetas_report_date", "cadernetas", ["report_date"])

    # -------------------------------------------------------------------------
    # FOOD
    # -------------------------------------------------------------------------

    op.create_table(
        "foods",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("details", sa.String(500), nullable=True),
        sa.Column("type", sa.String(50), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_foods_school_id", "foods", ["school_id"])

    op.create_table(
        "food_menus",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("level", sa.String(100), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_food_menus_school_id", "food_menus", ["school_id"])

    op.create_table(
        "food_menu_items",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("food_menu_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("day_of_week", sa.Integer(), nullable=False),
        sa.Column("meal_type", sa.String(50), nullable=False),
        sa.Column("meal_component", sa.String(50), nullable=True),
        sa.Column("food_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["food_menu_id"], ["food_menus.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["food_id"], ["foods.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint(
            "food_menu_id", "day_of_week", "meal_type", "meal_component",
            name="uq_food_menu_item",
        ),
    )
    op.create_index("ix_food_menu_items_school_id", "food_menu_items", ["school_id"])

    # -------------------------------------------------------------------------
    # ABSENCES
    # -------------------------------------------------------------------------

    op.create_table(
        "absences",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("employee_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("responsible_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("absence_date", sa.Date(), nullable=False),
        sa.Column("justified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("justification", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["employee_id"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["responsible_id"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_absences_school_id", "absences", ["school_id"])
    op.create_index("ix_absences_employee_id", "absences", ["employee_id"])

    # -------------------------------------------------------------------------
    # IMMUNIZATIONS
    # -------------------------------------------------------------------------

    op.create_table(
        "immunizations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("vaccine_name", sa.String(255), nullable=False),
        sa.Column("administered_at", sa.Date(), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("administered_by", sa.String(255), nullable=True),
        sa.Column("dose_number", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
    )
    op.create_index("ix_immunizations_school_id", "immunizations", ["school_id"])
    op.create_index("ix_immunizations_child_id", "immunizations", ["child_id"])

    # -------------------------------------------------------------------------
    # FINANCE — expense_categories, expenses, invoices, payments, payment_invoices
    # -------------------------------------------------------------------------

    op.create_table(
        "expense_categories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.UniqueConstraint("school_id", "name", name="uq_expense_category_school_name"),
    )
    op.create_index("ix_expense_categories_school_id", "expense_categories", ["school_id"])

    op.create_table(
        "expenses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("category_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("registered_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("description", sa.String(500), nullable=False),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("expense_date", sa.Date(), nullable=False),
        sa.Column("payment_method", sa.String(50), nullable=True),
        sa.Column("reference", sa.String(255), nullable=True),
        sa.Column("receipt_url", sa.String(500), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["category_id"], ["expense_categories.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["registered_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="SET NULL"),
        sa.CheckConstraint("amount >= 0", name="ck_expenses_amount_positive"),
    )
    op.create_index("ix_expenses_school_id", "expenses", ["school_id"])
    op.create_index("ix_expenses_expense_date", "expenses", ["expense_date"])

    op.create_table(
        "invoices",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("issued_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_year_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("invoice_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("reference_month", sa.Date(), nullable=False),
        sa.Column("description", sa.String(500), nullable=True),
        sa.Column("tuition_amount", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("other_fees", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("total_amount", sa.Numeric(10, 2), nullable=False, server_default="0"),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["issued_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_year_id"], ["school_years.id"], ondelete="SET NULL"),
    )
    op.create_index("ix_invoices_school_id", "invoices", ["school_id"])
    op.create_index("ix_invoices_child_id", "invoices", ["child_id"])

    op.create_table(
        "payments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("received_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("payment_date", sa.Date(), nullable=False, server_default=sa.text("CURRENT_DATE")),
        sa.Column("receipt_number", sa.String(100), nullable=True),
        sa.Column("amount", sa.Numeric(10, 2), nullable=False),
        sa.Column("payment_method", sa.String(50), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["child_id"], ["children.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["received_by"], ["employees.id"], ondelete="RESTRICT"),
        sa.CheckConstraint("amount >= 0", name="ck_payments_amount_positive"),
    )
    op.create_index("ix_payments_school_id", "payments", ["school_id"])
    op.create_index("ix_payments_child_id", "payments", ["child_id"])
    op.create_index("ix_payments_payment_date", "payments", ["payment_date"])

    op.create_table(
        "payment_invoices",
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("invoice_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("amount_applied", sa.Numeric(10, 2), nullable=False),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("payment_id", "invoice_id"),
    )
    op.create_index("ix_payment_invoices_school_id", "payment_invoices", ["school_id"])


def downgrade() -> None:
    # Drop in reverse dependency order
    op.drop_table("payment_invoices")
    op.drop_table("payments")
    op.drop_table("invoices")
    op.drop_table("expenses")
    op.drop_table("expense_categories")
    op.drop_table("immunizations")
    op.drop_table("absences")
    op.drop_table("food_menu_items")
    op.drop_table("food_menus")
    op.drop_table("foods")
    op.drop_table("cadernetas")
    op.drop_table("enrollments")
    op.drop_table("schedule_slots")
    op.drop_table("schedule_teachers")
    op.drop_table("schedules")
    op.drop_table("activities")
    op.drop_table("turmas")
    op.drop_table("school_years")
    op.drop_table("child_guardians")
    op.drop_table("children")
    op.drop_table("users")
    op.drop_table("guardians")
    op.drop_table("employees")
    op.drop_table("platform_users")
    op.drop_table("schools")
