# -*- coding: utf-8 -*-
"""Fee automation models — per-school policy and per-student billing inputs.

Cellen owns the whole fee calculation: what each student owes for tuition,
transport and extracurricular activities, which guardian pays, and which
sibling discount applies. FinReg remains the fiscal engine that issues the
document; these rows are the source data Cellen composes its billing plans
from.

Every rate, threshold and period lives here as school-editable data. Nothing
in this module (or in the composer) is a hardcoded business rule.
"""
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer,
    Numeric, String, UniqueConstraint, func
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class SchoolFeePolicy(Base):
    """One fee policy per school year: the defaults every billing run uses."""
    __tablename__ = "school_fee_policies"
    __table_args__ = (
        UniqueConstraint("school_id", "school_year_id", name="uq_fee_policy_school_year"),
        CheckConstraint(
            "sibling_discount_pct >= 0 AND sibling_discount_pct <= 100",
            name="ck_fee_policy_sibling_pct",
        ),
        CheckConstraint(
            "sibling_discount_min_children >= 1",
            name="ck_fee_policy_sibling_min",
        ),
        CheckConstraint(
            "sibling_discount_scope IN ('additional_children', 'all_children')",
            name="ck_fee_policy_sibling_scope",
        ),
        CheckConstraint("billing_day >= 1 AND billing_day <= 31", name="ck_fee_policy_billing_day"),
        CheckConstraint("due_days >= 0 AND due_days <= 365", name="ck_fee_policy_due_days"),
        CheckConstraint(
            "proration_policy IN ('pro_rata_days', 'full_month', 'no_charge')",
            name="ck_fee_policy_proration",
        ),
        Index("ix_school_fee_policies_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    school_year_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="RESTRICT"), nullable=False
    )
    default_tuition_billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    # Matrícula default used when an enrollment is created without an explicit
    # fee. Null means "no default"; each enrollment still decides its own fee.
    default_enrollment_fee: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True)
    sibling_discount_pct: Mapped[Decimal] = mapped_column(
        Numeric(5, 2), nullable=False, default=Decimal("5.00")
    )
    sibling_discount_min_children: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    sibling_discount_scope: Mapped[str] = mapped_column(
        String(30), nullable=False, default="additional_children"
    )
    due_days: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    billing_day: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    auto_generate: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    proration_policy: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pro_rata_days"
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ExtracurricularModality(Base):
    """A billable extracurricular activity (balé, capoeira, natação…)."""
    __tablename__ = "extracurricular_modalities"
    __table_args__ = (
        UniqueConstraint("school_id", "name", name="uq_modality_school_name"),
        CheckConstraint("inscription_fee >= 0", name="ck_modality_inscription_fee"),
        CheckConstraint("monthly_fee >= 0", name="ck_modality_monthly_fee"),
        Index("ix_extracurricular_modalities_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    inscription_fee: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=Decimal("0")
    )
    monthly_fee: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=Decimal("0")
    )
    billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class StudentModalityEnrollment(Base):
    """A student attending a modality, effective-dated and auditable."""
    __tablename__ = "student_modality_enrollments"
    __table_args__ = (
        UniqueConstraint(
            "child_id", "modality_id", "start_date", name="uq_modality_enrollment_start"
        ),
        CheckConstraint(
            "status IN ('active', 'ended', 'withdrawn')",
            name="ck_modality_enrollment_status",
        ),
        Index("ix_modality_enrollments_school_child", "school_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False
    )
    modality_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("extracurricular_modalities.id", ondelete="RESTRICT"),
        nullable=False,
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    # Set when the one-off inscription fee was charged, so it can never be
    # charged twice. Exactly one of the two is used, depending on the mode.
    inscription_instruction_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("finreg_billing_instructions.id", ondelete="SET NULL"),
        nullable=True,
    )
    inscription_invoice_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("invoices.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class TransportRoute(Base):
    """A school transport route with its own monthly price."""
    __tablename__ = "transport_routes"
    __table_args__ = (
        UniqueConstraint("school_id", "name", name="uq_transport_route_school_name"),
        CheckConstraint("monthly_price >= 0", name="ck_transport_route_price"),
        Index("ix_transport_routes_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    monthly_price: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=Decimal("0")
    )
    billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class StudentTransportAssignment(Base):
    """Effective-dated route assignment; a route change closes and opens rows."""
    __tablename__ = "student_transport_assignments"
    __table_args__ = (
        UniqueConstraint("child_id", "start_date", name="uq_transport_assignment_start"),
        CheckConstraint(
            "status IN ('active', 'ended', 'withdrawn')",
            name="ck_transport_assignment_status",
        ),
        Index("ix_transport_assignments_school_child", "school_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False
    )
    route_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("transport_routes.id", ondelete="RESTRICT"), nullable=False
    )
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class StudentFinanceProfile(Base):
    """Billing overrides for one student in one school year.

    The profile is optional: an active enrollment with a primary guardian is
    enough to compose the standard policy charges. The row exists to record
    the guardian-pays choice, a per-student tuition value or item, a different
    billing day, and the stable FinReg plan identity.
    """
    __tablename__ = "student_finance_profiles"
    __table_args__ = (
        UniqueConstraint("child_id", "school_year_id", name="uq_student_finance_profile"),
        UniqueConstraint("school_id", "plan_external_id", name="uq_student_finance_plan_external"),
        CheckConstraint(
            "status IN ('active', 'paused', 'withdrawn')",
            name="ck_student_finance_profile_status",
        ),
        CheckConstraint(
            "tuition_override IS NULL OR tuition_override >= 0",
            name="ck_student_finance_tuition_override",
        ),
        CheckConstraint(
            "billing_day IS NULL OR (billing_day >= 1 AND billing_day <= 31)",
            name="ck_student_finance_billing_day",
        ),
        Index("ix_student_finance_profiles_school_id", "school_id"),
        Index("ix_student_finance_profiles_guardian", "school_id", "billing_guardian_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False
    )
    school_year_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="RESTRICT"), nullable=False
    )
    billing_guardian_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="SET NULL"), nullable=True
    )
    tuition_billing_item_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("billing_items.id", ondelete="SET NULL"), nullable=True
    )
    tuition_override: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True)
    billing_day: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    plan_external_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, default=uuid.uuid4
    )
    plan_revision: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    plan_next_run_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    plan_stale: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    starts_on: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    ends_on: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class BillingRun(Base):
    """One idempotent monthly generation attempt for a school year.

    The unique key is the school, the year and the billing month: pressing
    "Gerar dívidas" twice in the same month resumes the same run instead of
    billing twice.
    """
    __tablename__ = "billing_runs"
    __table_args__ = (
        UniqueConstraint(
            "school_id", "school_year_id", "billing_month", name="uq_billing_run_month"
        ),
        CheckConstraint(
            "status IN ('preview', 'composing', 'running', 'completed', "
            "'partial_failed', 'failed')",
            name="ck_billing_run_status",
        ),
        Index("ix_billing_runs_school_month", "school_id", "billing_month"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    school_year_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="RESTRICT"), nullable=False
    )
    billing_month: Mapped[str] = mapped_column(String(7), nullable=False)  # YYYY-MM
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="running")
    mode: Mapped[str] = mapped_column(String(20), nullable=False, default="internal")
    stats: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    requested_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
