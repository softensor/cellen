# -*- coding: utf-8 -*-
"""Request schemas for fee automation."""
import uuid
from datetime import date
from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, Field

from app.schemas.base import DecimalFloat


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
