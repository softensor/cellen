import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class UserBase(BaseModel):
    username: str
    role: str
    is_active: bool = True
    employee_id: Optional[uuid.UUID] = None
    guardian_id: Optional[uuid.UUID] = None


class UserCreate(UserBase):
    password: str


class UserUpdate(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    employee_id: Optional[uuid.UUID] = None
    guardian_id: Optional[uuid.UUID] = None


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    school_id: uuid.UUID
    username: str
    role: str
    is_active: bool
    employee_id: Optional[uuid.UUID] = None
    guardian_id: Optional[uuid.UUID] = None
    last_login: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
