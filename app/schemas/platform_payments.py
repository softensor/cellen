"""Schemas for the platform owner's principia-pay activation surface.

The raw product token is accepted once and never returned: the status
payload carries only the non-secret identifying prefix, the way the rail's
own dashboard does.
"""
import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class PlatformPaymentsActivationRequest(BaseModel):
    product_token: str = Field(min_length=8, max_length=500)


class PlatformPaymentsStatusResponse(BaseModel):
    configured: bool
    enabled: bool
    status: str
    token_prefix: Optional[str] = None
    token_source: Optional[str] = None
    provider: str
    source_system: str
    base_url: str
    last_error: Optional[str] = None
    last_checked_at: Optional[datetime] = None


class PlatformPaymentSchool(BaseModel):
    id: uuid.UUID
    name: str
    slug: str
    is_active: bool
    registered: bool
    client_id: Optional[str] = None
    last_error: Optional[str] = None
    rail_state: str
    providers: dict[str, str] = Field(default_factory=dict)


class PlatformPaymentSchoolsResponse(BaseModel):
    configured: bool
    rail_error: Optional[str] = None
    schools: list[PlatformPaymentSchool]


class PlatformPaymentSchoolRegistration(BaseModel):
    school_id: uuid.UUID
    name: str
    registered: bool
    client_id: Optional[str] = None
    status: str
