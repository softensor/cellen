# -*- coding: utf-8 -*-
"""Request schemas for fee automation."""
import uuid
from datetime import date
from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

from app.schemas.base import DecimalFloat


class LateFeeBand(BaseModel):
    """One editable multa band.

    ``anchor`` names the month the window belongs to: the month the document
    was due (``due_month``) or the following one (``next_month``). ``end_day``
    null means "to the end of that month". ``min_amount``/``max_amount`` cap
    the fee for small or very large balances.
    """

    id: str = Field(min_length=1, max_length=60)
    label: Optional[str] = Field(default=None, max_length=120)
    anchor: Literal["due_month", "next_month"] = "due_month"
    start_day: int = Field(ge=1, le=31)
    end_day: Optional[int] = Field(default=None, ge=1, le=31)
    percent: DecimalFloat = Field(gt=0, le=100)
    min_amount: Optional[DecimalFloat] = Field(default=None, ge=0)
    max_amount: Optional[DecimalFloat] = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_window(self):
        if self.end_day is not None and self.end_day < self.start_day:
            raise ValueError("end_day must not precede start_day")
        if (
            self.min_amount is not None
            and self.max_amount is not None
            and self.max_amount < self.min_amount
        ):
            raise ValueError("max_amount must not be below min_amount")
        return self


class DunningStep(BaseModel):
    """One reminder in the school's policy-defined schedule."""

    level: int = Field(ge=1, le=50)
    offset_days: int = Field(ge=0, le=365)
    channels: list[Literal["email", "sms", "whatsapp", "in_app"]] = Field(
        default_factory=lambda: ["email"]
    )
    message: Optional[str] = Field(default=None, max_length=2000)


class FeePolicyUpdate(BaseModel):
    school_year_id: Optional[uuid.UUID] = None
    default_tuition_billing_item_id: Optional[uuid.UUID] = None
    default_enrollment_fee: Optional[DecimalFloat] = Field(default=None, ge=0)
    sibling_discount_pct: DecimalFloat = Field(default=Decimal("5.00"), ge=0, le=100)
    sibling_discount_min_children: int = Field(default=2, ge=1, le=20)
    sibling_discount_scope: Literal["additional_children", "all_children"] = (
        "additional_children"
    )
    due_days: int = Field(default=5, ge=0, le=365)
    billing_day: int = Field(default=1, ge=1, le=31)
    auto_generate: bool = False
    proration_policy: Literal["pro_rata_days", "full_month", "no_charge"] = (
        "pro_rata_days"
    )
    late_fee_enabled: bool = False
    late_fee_billing_item_id: Optional[uuid.UUID] = None
    late_fee_base: Literal["outstanding", "document_total"] = "outstanding"
    late_fee_bands: list[LateFeeBand] = Field(default_factory=list)
    dunning_enabled: bool = False
    dunning_schedule: list[DunningStep] = Field(default_factory=list)
    dunning_message_template: Optional[str] = Field(default=None, max_length=4000)

    @model_validator(mode="after")
    def validate_bands_and_schedule(self):
        ids = [band.id for band in self.late_fee_bands]
        if len(ids) != len(set(ids)):
            raise ValueError("late_fee_bands ids must be unique")
        levels = [step.level for step in self.dunning_schedule]
        if len(levels) != len(set(levels)):
            raise ValueError("dunning_schedule levels must be unique")
        offsets = [(step.level, step.offset_days) for step in self.dunning_schedule]
        if len(offsets) != len(set(offsets)):
            raise ValueError("dunning_schedule level/offset pairs must be unique")
        return self


class LateFeeAssessRequest(BaseModel):
    as_of: Optional[date] = None
    dry_run: bool = False


class DunningRunRequest(BaseModel):
    as_of: Optional[date] = None
    dry_run: bool = False


class ModalityCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=500)
    inscription_fee: DecimalFloat = Field(default=Decimal("0"), ge=0)
    monthly_fee: DecimalFloat = Field(default=Decimal("0"), ge=0)
    billing_item_id: Optional[uuid.UUID] = None
    is_active: bool = True


class ModalityUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=500)
    inscription_fee: Optional[DecimalFloat] = Field(default=None, ge=0)
    monthly_fee: Optional[DecimalFloat] = Field(default=None, ge=0)
    billing_item_id: Optional[uuid.UUID] = None
    is_active: Optional[bool] = None


class ModalityEnrollmentCreate(BaseModel):
    child_id: uuid.UUID
    start_date: Optional[date] = None


class EndDatedBody(BaseModel):
    end_date: Optional[date] = None
    status: Literal["ended", "withdrawn"] = "ended"


class TransportRouteCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=500)
    monthly_price: DecimalFloat = Field(default=Decimal("0"), ge=0)
    billing_item_id: Optional[uuid.UUID] = None
    is_active: bool = True


class TransportRouteUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=500)
    monthly_price: Optional[DecimalFloat] = Field(default=None, ge=0)
    billing_item_id: Optional[uuid.UUID] = None
    is_active: Optional[bool] = None


class TransportAssignmentCreate(BaseModel):
    child_id: uuid.UUID
    start_date: Optional[date] = None


class StudentProfileUpdate(BaseModel):
    school_year_id: Optional[uuid.UUID] = None
    billing_guardian_id: Optional[uuid.UUID] = None
    tuition_billing_item_id: Optional[uuid.UUID] = None
    tuition_override: Optional[DecimalFloat] = Field(default=None, ge=0)
    billing_day: Optional[int] = Field(default=None, ge=1, le=31)
    status: Optional[Literal["active", "paused", "withdrawn"]] = None
    starts_on: Optional[date] = None
    ends_on: Optional[date] = None


class BillingRunRequest(BaseModel):
    billing_month: Optional[str] = Field(default=None, pattern=r"^\d{4}-\d{2}$")
    school_year_id: Optional[uuid.UUID] = None


class BillingPreviewRequest(BillingRunRequest):
    child_id: Optional[uuid.UUID] = None
