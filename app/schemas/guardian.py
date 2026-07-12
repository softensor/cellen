import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class GuardianBase(BaseModel):
    first_name: str
    middle_name: Optional[str] = None
    last_name: str
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    civil_state: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
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


class GuardianCreate(GuardianBase):
    username: str
    password: str


class GuardianUpdate(BaseModel):
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    birth_date: Optional[date] = None
    place_of_birth: Optional[str] = None
    sex: Optional[str] = None
    civil_state: Optional[str] = None
    nationality: Optional[str] = None
    naturality: Optional[str] = None
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


class GuardianResponse(GuardianBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ChildGuardianLink(BaseModel):
    child_id: uuid.UUID
    relationship_type: str  # father, mother, legal_guardian, grandparent, other
    is_primary_contact: bool = False


class ChildGuardianResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    child_id: uuid.UUID
    guardian_id: uuid.UUID
    relationship_type: str
    is_primary_contact: bool
