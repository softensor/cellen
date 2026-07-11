import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class AbsenceBase(BaseModel):
    employee_id: uuid.UUID
    responsible_id: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    absence_date: date
    justified: bool = False
    justification: Optional[str] = None


class AbsenceCreate(AbsenceBase):
    pass


class AbsenceUpdate(BaseModel):
    responsible_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None
    absence_date: Optional[date] = None
    justified: Optional[bool] = None
    justification: Optional[str] = None


class AbsenceResponse(AbsenceBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime


class AbsenceSummary(BaseModel):
    employee_id: uuid.UUID
    total: int
    justified: int
    unjustified: int
