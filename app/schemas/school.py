import uuid
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, field_validator


class SchoolBase(BaseModel):
    name: str
    slug: str
    address: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    nif: Optional[str] = None
    logo_url: Optional[str] = None
    currency: str = "AOA"
    subscription_notes: Optional[str] = None
    segment: str = "preschool"


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
    nif: Optional[str] = None
    logo_url: Optional[str] = None
    currency: Optional[str] = None
    subscription_notes: Optional[str] = None
    subscription_started_at: Optional[datetime] = None
    wa_enabled: Optional[bool] = None
    wa_phone_number_id: Optional[str] = None
    wa_access_token: Optional[str] = None
    segment: Optional[str] = None
    features: Optional[dict[str, Any]] = None


    @field_validator("features")
    @classmethod
    def validate_custom_roles(cls, value):
        if value is None or "custom_roles" not in value:
            return value
        from app.core.custom_roles import CustomRole
        raw = value["custom_roles"]
        if not isinstance(raw, list) or len(raw) > 50:
            raise ValueError("custom_roles deve ser uma lista com até 50 funções")
        roles = [CustomRole.model_validate(role).model_dump() for role in raw]
        keys = [role["key"] for role in roles]
        labels = [role["label"].casefold() for role in roles]
        if len(set(keys)) != len(keys) or len(set(labels)) != len(labels):
            raise ValueError("As funções personalizadas devem ter nomes e identificadores únicos")
        return {**value, "custom_roles": roles}


class SchoolResponse(SchoolBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    is_active: bool
    subscription_started_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    wa_enabled: bool = False
    wa_phone_number_id: Optional[str] = None
    # wa_access_token intentionally omitted from response for security
    features: Optional[dict[str, Any]] = None
    resolved_features: dict[str, Any] = {}


class SchoolWithStats(SchoolResponse):
    active_users_count: int = 0
    children_count: int = 0


class PlatformStats(BaseModel):
    total_schools: int
    active_schools: int
    total_children: int
    total_active_users: int
