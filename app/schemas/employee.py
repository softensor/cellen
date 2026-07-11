import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict


class EmployeeBase(BaseModel):
    first_name: str
    middle_name: Optional[str] = None
    last_name: str
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    civil_state: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
    height: Optional[Decimal] = None
    profession: Optional[str] = None
    qualifications: Optional[str] = None
    id_card_number: Optional[str] = None
    photo_url: Optional[str] = None
    street: Optional[str] = None
    house_number: Optional[str] = None
    building_number: Optional[str] = None
    apt_number: Optional[str] = None
    city: Optional[str] = None
    municipio: Optional[str] = None
    bairro: Optional[str] = None
    mobile_first: Optional[str] = None
    mobile_second: Optional[str] = None
    email: Optional[str] = None
    employee_type: str  # teacher, staff, admin
    position: Optional[str] = None
    title_academic: Optional[str] = None
    social_security: Optional[str] = None
    contract_type: Optional[str] = None
    hire_date: Optional[date] = None
    salary: Optional[Decimal] = None
    status: str = "active"
    privilege: Optional[str] = None


class EmployeeCreate(EmployeeBase):
    pass


class EmployeeUpdate(BaseModel):
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    civil_state: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
    height: Optional[Decimal] = None
    profession: Optional[str] = None
    qualifications: Optional[str] = None
    id_card_number: Optional[str] = None
    photo_url: Optional[str] = None
    street: Optional[str] = None
    house_number: Optional[str] = None
    building_number: Optional[str] = None
    apt_number: Optional[str] = None
    city: Optional[str] = None
    municipio: Optional[str] = None
    bairro: Optional[str] = None
    mobile_first: Optional[str] = None
    mobile_second: Optional[str] = None
    email: Optional[str] = None
    employee_type: Optional[str] = None
    position: Optional[str] = None
    title_academic: Optional[str] = None
    social_security: Optional[str] = None
    contract_type: Optional[str] = None
    hire_date: Optional[date] = None
    salary: Optional[Decimal] = None
    status: Optional[str] = None
    privilege: Optional[str] = None


class EmployeeResponse(EmployeeBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
