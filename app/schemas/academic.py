import uuid
from datetime import date, datetime, time
from typing import List, Optional

from pydantic import BaseModel, ConfigDict


# School Year
class SchoolYearBase(BaseModel):
    year_label: str
    start_date: date
    end_date: date
    is_active: bool = False


class SchoolYearCreate(SchoolYearBase):
    pass


class SchoolYearUpdate(BaseModel):
    year_label: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    is_active: Optional[bool] = None


class SchoolYearResponse(SchoolYearBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID


# Turma
class TurmaBase(BaseModel):
    name: str
    level: str
    room: Optional[str] = None
    max_capacity: int = 0


class TurmaCreate(TurmaBase):
    pass


class TurmaUpdate(BaseModel):
    name: Optional[str] = None
    level: Optional[str] = None
    room: Optional[str] = None
    max_capacity: Optional[int] = None


class TurmaResponse(TurmaBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime


# Activity
class ActivityBase(BaseModel):
    name: str
    description: Optional[str] = None


class ActivityCreate(ActivityBase):
    pass


class ActivityUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


class ActivityResponse(ActivityBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime


# Schedule Slot
class ScheduleSlotBase(BaseModel):
    day_of_week: int
    slot_time: time
    activity_id: uuid.UUID


class ScheduleSlotCreate(ScheduleSlotBase):
    pass


class ScheduleSlotResponse(ScheduleSlotBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    schedule_id: uuid.UUID
    school_id: uuid.UUID


# Schedule
class ScheduleBase(BaseModel):
    turma_id: uuid.UUID
    school_year_id: uuid.UUID


class ScheduleCreate(ScheduleBase):
    pass


class ScheduleUpdate(BaseModel):
    turma_id: Optional[uuid.UUID] = None
    school_year_id: Optional[uuid.UUID] = None


class ScheduleResponse(ScheduleBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    slots: List[ScheduleSlotResponse] = []
    turma_name: Optional[str] = None
    school_year_label: Optional[str] = None


class ScheduleTeacherAssign(BaseModel):
    employee_id: uuid.UUID


class ScheduleTeacherResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    schedule_id: uuid.UUID
    employee_id: uuid.UUID


# Enrollment
class EnrollmentBase(BaseModel):
    child_id: uuid.UUID
    schedule_id: uuid.UUID
    school_year_id: uuid.UUID
    enrollment_date: Optional[date] = None
    status: str = "active"


class EnrollmentCreate(EnrollmentBase):
    pass


class EnrollmentUpdate(BaseModel):
    status: Optional[str] = None
    enrollment_date: Optional[date] = None


class EnrollmentResponse(EnrollmentBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    child_name: Optional[str] = None
    turma_name: Optional[str] = None
    school_year: Optional[str] = None
