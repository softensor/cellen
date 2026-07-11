import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict


class ChildBase(BaseModel):
    cedula: str
    first_name: str
    middle_name: Optional[str] = None
    last_name: str
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
    height: Optional[Decimal] = None
    special_needs: Optional[str] = None
    medical_prescription: Optional[str] = None
    photo_url: Optional[str] = None
    street: Optional[str] = None
    house_number: Optional[str] = None
    building_number: Optional[str] = None
    apt_number: Optional[str] = None
    city: Optional[str] = None
    municipio: Optional[str] = None
    bairro: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None


class ChildCreate(ChildBase):
    pass


class ChildUpdate(BaseModel):
    cedula: Optional[str] = None
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
    height: Optional[Decimal] = None
    special_needs: Optional[str] = None
    medical_prescription: Optional[str] = None
    photo_url: Optional[str] = None
    street: Optional[str] = None
    house_number: Optional[str] = None
    building_number: Optional[str] = None
    apt_number: Optional[str] = None
    city: Optional[str] = None
    municipio: Optional[str] = None
    bairro: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    is_active: Optional[bool] = None


class ChildResponse(ChildBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    school_id: uuid.UUID
    is_active: bool
    created_at: datetime
    updated_at: datetime


class ChildBalance(BaseModel):
    child_id: uuid.UUID
    outstanding_balance: Decimal
