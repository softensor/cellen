import uuid
from datetime import date, time
from typing import Optional

from pydantic import BaseModel, ConfigDict


class LessonAttendanceUpsert(BaseModel):
    child_id: uuid.UUID
    status: str  # present | absent | late | justified
    notes: Optional[str] = None


class BulkUpsertRequest(BaseModel):
    schedule_id: uuid.UUID
    subject_id: uuid.UUID
    date: date
    period_id: uuid.UUID
    records: list[LessonAttendanceUpsert]


class LessonAttendanceRecord(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    child_id: uuid.UUID
    child_name: Optional[str] = None
    status: str
    notes: Optional[str] = None


class SessionResponse(BaseModel):
    """Session header + enrolled students with their current status."""
    schedule_id: uuid.UUID
    subject_id: uuid.UUID
    subject_name: Optional[str] = None
    subject_code: Optional[str] = None
    date: date
    period_id: uuid.UUID
    period_name: Optional[str] = None
    period_number: Optional[int] = None
    slot_time: Optional[time] = None
    employee_id: Optional[uuid.UUID] = None
    turma_name: Optional[str] = None
    records: list[LessonAttendanceRecord]


class StudentSubjectSummary(BaseModel):
    child_id: uuid.UUID
    child_name: str
    subject_id: uuid.UUID
    subject_name: str
    total_lessons: int
    present: int
    absent: int
    late: int
    justified: int
    absence_pct: float  # (absent + late) / total_lessons * 100
    at_risk: bool       # absence_pct >= 25


class TurmaSummaryResponse(BaseModel):
    schedule_id: uuid.UUID
    turma_name: str
    rows: list[StudentSubjectSummary]


class TodaySession(BaseModel):
    schedule_id: uuid.UUID
    turma_name: str
    subject_id: uuid.UUID
    subject_name: Optional[str] = None
    period_id: uuid.UUID
    period_name: Optional[str] = None
    period_number: Optional[int] = None
    slot_time: Optional[time] = None
    attendance_taken: bool
    student_count: int
