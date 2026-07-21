import uuid
from datetime import time
from typing import Optional

from pydantic import BaseModel, ConfigDict


# ---------------------------------------------------------------------------
# Period templates
# ---------------------------------------------------------------------------

class PeriodCreate(BaseModel):
    period_number: int
    name: str
    start_time: time
    end_time: time
    is_break: bool = False


class PeriodUpdate(BaseModel):
    name: Optional[str] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    is_break: Optional[bool] = None


class PeriodResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    period_number: int
    name: str
    start_time: time
    end_time: time
    is_break: bool


# ---------------------------------------------------------------------------
# Timetable grid cell (one slot in the week grid)
# ---------------------------------------------------------------------------

class TimetableCellUpsert(BaseModel):
    """Create or update one cell: turma × day × period → subject × teacher × room."""
    schedule_id: uuid.UUID
    day_of_week: int          # 0=Mon..4=Fri
    period_id: uuid.UUID
    subject_id: Optional[uuid.UUID] = None
    employee_id: Optional[uuid.UUID] = None
    room: Optional[str] = None


class TimetableCellResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    schedule_id: uuid.UUID
    day_of_week: int
    slot_time: time
    period_id: Optional[uuid.UUID] = None
    period_number: Optional[int] = None
    period_name: Optional[str] = None
    subject_id: Optional[uuid.UUID] = None
    subject_name: Optional[str] = None
    subject_code: Optional[str] = None
    employee_id: Optional[uuid.UUID] = None
    employee_name: Optional[str] = None
    room: Optional[str] = None


# ---------------------------------------------------------------------------
# Full week grid for one turma
# ---------------------------------------------------------------------------

class TimetableGridResponse(BaseModel):
    schedule_id: uuid.UUID
    turma_id: uuid.UUID
    turma_name: str
    school_year_id: uuid.UUID
    school_year_label: str
    periods: list[PeriodResponse]
    cells: list[TimetableCellResponse]


# ---------------------------------------------------------------------------
# Teacher's personal timetable
# ---------------------------------------------------------------------------

class TeacherSlot(BaseModel):
    day_of_week: int
    period_id: Optional[uuid.UUID] = None
    period_name: Optional[str] = None
    period_number: Optional[int] = None
    slot_time: time
    subject_name: Optional[str] = None
    turma_name: Optional[str] = None
    room: Optional[str] = None
    schedule_id: uuid.UUID
