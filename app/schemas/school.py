import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class SchoolBase(BaseModel):
    name: str
    slug: str
    address: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    logo_url: Optional[str] = None
    subscription_notes: Optional[str] = None


class SchoolCreate(SchoolBase):
    admin_username: str
    admin_password: str


class SchoolUpdate(BaseModel):
    name: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    logo_url: Optional[str] = None
    subscription_notes: Optional[str] = None
    subscription_started_at: Optional[datetime] = None


class SchoolResponse(SchoolBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    is_active: bool
    subscription_started_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class SchoolWithStats(SchoolResponse):
    active_users_count: int = 0
    children_count: int = 0


class PlatformStats(BaseModel):
    total_schools: int
    active_schools: int
    total_children: int
    total_active_users: int
