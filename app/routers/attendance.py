import uuid
from datetime import date, datetime, time
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import (
    get_current_user,
    get_school_id,
    require_school_admin,
    require_teacher,
)
from app.models.modern import Attendance
from app.models.person import Child

router = APIRouter(prefix="/attendance", tags=["attendance"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class CheckInBody(BaseModel):
    child_id: uuid.UUID
    notes: Optional[str] = None


class CheckOutBody(BaseModel):
    child_id: uuid.UUID


class BulkAttendanceRecord(BaseModel):
    child_id: uuid.UUID
    status: str  # present / absent / late / excused


class BulkAttendanceBody(BaseModel):
    date: date
    records: List[BulkAttendanceRecord]


class AttendanceChildInfo(BaseModel):
    child_id: uuid.UUID
    first_name: str
    last_name: str
    photo_url: Optional[str] = None
    check_in_time: Optional[time] = None
    check_out_time: Optional[time] = None
    status: str

    model_config = {"from_attributes": True}


class AttendanceSummary(BaseModel):
    total_enrolled: int
    checked_in: int
    checked_out: int
    absent: int


class TodayAttendanceResponse(BaseModel):
    records: List[AttendanceChildInfo]
    summary: AttendanceSummary


class AttendanceRecord(BaseModel):
    id: uuid.UUID
    child_id: uuid.UUID
    attendance_date: date
    check_in_time: Optional[time] = None
    check_out_time: Optional[time] = None
    status: str
    notes: Optional[str] = None
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ChildMonthlySummary(BaseModel):
    child_id: uuid.UUID
    first_name: str
    last_name: str
    present: int
    absent: int
    late: int
    excused: int
    total_days: int


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _get_or_create_attendance(
    db: AsyncSession,
    school_id: uuid.UUID,
    child_id: uuid.UUID,
    att_date: date,
    recorded_by: uuid.UUID,
) -> Attendance:
    result = await db.execute(
        select(Attendance).where(
            Attendance.school_id == school_id,
            Attendance.child_id == child_id,
            Attendance.attendance_date == att_date,
        )
    )
    record = result.scalar_one_or_none()
    if record is None:
        record = Attendance(
            school_id=school_id,
            child_id=child_id,
            recorded_by=recorded_by,
            attendance_date=att_date,
            status="present",
        )
        db.add(record)
        await db.flush()
    return record


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/today", response_model=TodayAttendanceResponse)
async def get_today_attendance(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    today = date.today()

    # Get all active children
    children_result = await db.execute(
        select(Child).where(Child.school_id == school_id, Child.is_active == True)
    )
    children = children_result.scalars().all()
    child_map = {c.id: c for c in children}
    total_enrolled = len(children)

    # Get today's attendance records
    att_result = await db.execute(
        select(Attendance).where(
            Attendance.school_id == school_id,
            Attendance.attendance_date == today,
        )
    )
    attendance_records = att_result.scalars().all()
    att_map = {a.child_id: a for a in attendance_records}

    records = []
    checked_in = 0
    checked_out = 0
    absent = 0

    for child in children:
        att = att_map.get(child.id)
        if att:
            check_in = att.check_in_time
            check_out = att.check_out_time
            s = att.status
        else:
            check_in = None
            check_out = None
            s = "absent"

        if check_in is not None:
            checked_in += 1
        if check_out is not None:
            checked_out += 1
        if s == "absent":
            absent += 1

        records.append(AttendanceChildInfo(
            child_id=child.id,
            first_name=child.first_name,
            last_name=child.last_name,
            photo_url=child.photo_url,
            check_in_time=check_in,
            check_out_time=check_out,
            status=s,
        ))

    summary = AttendanceSummary(
        total_enrolled=total_enrolled,
        checked_in=checked_in,
        checked_out=checked_out,
        absent=absent,
    )
    return TodayAttendanceResponse(records=records, summary=summary)


@router.post("/checkin", response_model=AttendanceRecord, status_code=status.HTTP_200_OK)
async def checkin(
    body: CheckInBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    # Verify child belongs to school
    child_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    record = await _get_or_create_attendance(db, school_id, body.child_id, date.today(), employee_id)
    record.check_in_time = datetime.now().time()
    record.status = "present"
    if body.notes:
        record.notes = body.notes
    record.recorded_by = employee_id

    await db.commit()
    await db.refresh(record)
    return record


@router.post("/checkout", response_model=AttendanceRecord, status_code=status.HTTP_200_OK)
async def checkout(
    body: CheckOutBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    child_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    record = await _get_or_create_attendance(db, school_id, body.child_id, date.today(), employee_id)
    record.check_out_time = datetime.now().time()
    record.recorded_by = employee_id

    await db.commit()
    await db.refresh(record)
    return record


@router.post("/bulk", status_code=status.HTTP_200_OK)
async def bulk_attendance(
    body: BulkAttendanceBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_school_admin),
):
    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    upserted = 0
    for rec in body.records:
        result = await db.execute(
            select(Attendance).where(
                Attendance.school_id == school_id,
                Attendance.child_id == rec.child_id,
                Attendance.attendance_date == body.date,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.status = rec.status
            existing.recorded_by = employee_id
        else:
            att = Attendance(
                school_id=school_id,
                child_id=rec.child_id,
                recorded_by=employee_id,
                attendance_date=body.date,
                status=rec.status,
            )
            db.add(att)
        upserted += 1

    await db.commit()
    return {"upserted": upserted, "date": body.date}


@router.get("/child/{child_id}", response_model=List[AttendanceRecord])
async def get_child_attendance(
    child_id: uuid.UUID,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    result = await db.execute(
        select(Attendance)
        .where(Attendance.school_id == school_id, Attendance.child_id == child_id)
        .order_by(Attendance.attendance_date.desc())
        .offset(skip)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/summary")
async def attendance_summary(
    month: str,  # YYYY-MM
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    try:
        year_int, month_int = int(month[:4]), int(month[5:7])
    except (ValueError, IndexError):
        raise HTTPException(status_code=400, detail="month must be in YYYY-MM format")

    from_date = date(year_int, month_int, 1)
    import calendar
    last_day = calendar.monthrange(year_int, month_int)[1]
    to_date = date(year_int, month_int, last_day)

    result = await db.execute(
        select(Attendance).where(
            Attendance.school_id == school_id,
            Attendance.attendance_date >= from_date,
            Attendance.attendance_date <= to_date,
        )
    )
    records = result.scalars().all()

    # Group by child
    from collections import defaultdict
    child_stats: dict = defaultdict(lambda: {"present": 0, "absent": 0, "late": 0, "excused": 0})
    child_ids_seen = set()
    for r in records:
        child_ids_seen.add(r.child_id)
        s = r.status if r.status in ("present", "absent", "late", "excused") else "present"
        child_stats[r.child_id][s] += 1

    # Fetch child names
    if not child_ids_seen:
        return []

    children_result = await db.execute(
        select(Child).where(Child.school_id == school_id, Child.id.in_(child_ids_seen))
    )
    children = {c.id: c for c in children_result.scalars().all()}

    summaries = []
    for child_id, stats in child_stats.items():
        child = children.get(child_id)
        if not child:
            continue
        total = sum(stats.values())
        summaries.append(ChildMonthlySummary(
            child_id=child_id,
            first_name=child.first_name,
            last_name=child.last_name,
            present=stats["present"],
            absent=stats["absent"],
            late=stats["late"],
            excused=stats["excused"],
            total_days=total,
        ))

    return summaries
