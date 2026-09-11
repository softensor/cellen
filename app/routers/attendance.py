import uuid
from datetime import date, datetime, time
from typing import List, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import (
    get_current_user,
    get_school_id,
    require_teacher,
)
from app.models.modern import Attendance, AttendanceDayStatus, AttendanceLog
from app.models.person import Child, ChildGuardian

router = APIRouter(prefix="/attendance", tags=["attendance"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class CheckInBody(BaseModel):
    child_id: uuid.UUID
    notes: Optional[str] = None


class CheckOutBody(BaseModel):
    child_id: uuid.UUID


class BulkAttendanceRecord(BaseModel):
    child_id: uuid.UUID
    status: Literal["present", "absent", "late", "excused"]
    notes: Optional[str] = None


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
    unrecorded: int


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


class AttendanceHistoryRecord(AttendanceRecord):
    child_name: str


class AttendanceLogEntry(BaseModel):
    id: uuid.UUID
    child_id: uuid.UUID
    attendance_date: date
    event_type: str  # check_in | check_out
    event_time: time
    notes: Optional[str] = None
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ChildMonthlySummary(BaseModel):
    child_id: uuid.UUID
    first_name: str
    last_name: str
    present: int
    present_days: int = 0  # alias for present (spec compliance)
    days_present: int = 0  # additional alias
    absent: int
    late: int
    excused: int
    total_days: int


# ─── Day-Status Schemas ───────────────────────────────────────────────────────

class DayStatusBody(BaseModel):
    child_id: uuid.UUID
    status_date: date
    status: Literal["present", "absent", "excused", "late"]
    notes: Optional[str] = None


class DayStatusOut(BaseModel):
    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    status_date: date
    status: str
    notes: Optional[str] = None
    recorded_by: Optional[uuid.UUID] = None
    recorded_by_user_id: Optional[uuid.UUID] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class DayStatusMonthlySummary(BaseModel):
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
    recorded_by: Optional[uuid.UUID],
    recorded_by_user_id: uuid.UUID,
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
            recorded_by_user_id=recorded_by_user_id,
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
        select(Child).where(Child.school_id == school_id, Child.is_active)
    )
    children = children_result.scalars().all()
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
    unrecorded = 0

    for child in children:
        att = att_map.get(child.id)
        if att:
            check_in = att.check_in_time
            check_out = att.check_out_time
            if check_out is not None:
                s = "checked_out"
            else:
                s = att.status
        else:
            check_in = None
            check_out = None
            s = "unrecorded"

        if s in {"present", "late"} and check_out is None:
            checked_in += 1
        if check_out is not None:
            checked_out += 1
        if s == "absent":
            absent += 1
        if s == "unrecorded":
            unrecorded += 1

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
        unrecorded=unrecorded,
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

    now = datetime.now()
    today = date.today()
    record = await _get_or_create_attendance(
        db, school_id, body.child_id, today, employee_id, current_user.id
    )
    record.check_in_time = now.time()
    record.check_out_time = None
    record.status = "present"
    if body.notes:
        record.notes = body.notes
    record.recorded_by = employee_id
    record.recorded_by_user_id = current_user.id

    log_entry = AttendanceLog(
        school_id=school_id,
        child_id=body.child_id,
        recorded_by=employee_id,
        recorded_by_user_id=current_user.id,
        attendance_date=today,
        event_type="check_in",
        event_time=now.time(),
        notes=body.notes,
    )
    db.add(log_entry)

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

    now = datetime.now()
    today = date.today()
    record = await _get_or_create_attendance(
        db, school_id, body.child_id, today, employee_id, current_user.id
    )
    record.check_out_time = now.time()
    record.recorded_by = employee_id
    record.recorded_by_user_id = current_user.id

    log_entry = AttendanceLog(
        school_id=school_id,
        child_id=body.child_id,
        recorded_by=employee_id,
        recorded_by_user_id=current_user.id,
        attendance_date=today,
        event_type="check_out",
        event_time=now.time(),
    )
    db.add(log_entry)

    await db.commit()
    await db.refresh(record)
    return record


@router.post("/bulk", status_code=status.HTTP_200_OK)
async def bulk_attendance(
    body: BulkAttendanceBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    employee_id = getattr(current_user, "employee_id", None)

    child_ids = {rec.child_id for rec in body.records}
    if child_ids:
        valid_child_ids = set((await db.execute(
            select(Child.id).where(
                Child.school_id == school_id,
                Child.id.in_(child_ids),
            )
        )).scalars().all())
        if valid_child_ids != child_ids:
            raise HTTPException(status_code=404, detail="One or more children were not found")

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
            previous_status = existing.status
            existing.status = rec.status
            existing.recorded_by = employee_id
            existing.recorded_by_user_id = current_user.id
            if rec.status in {"absent", "excused"}:
                existing.check_in_time = None
                existing.check_out_time = None
            elif rec.status in {"present", "late"}:
                existing.check_out_time = None
            if rec.notes is not None:
                existing.notes = rec.notes
            if previous_status != rec.status:
                db.add(AttendanceLog(
                    school_id=school_id,
                    child_id=rec.child_id,
                    recorded_by=employee_id,
                    recorded_by_user_id=current_user.id,
                    attendance_date=body.date,
                    event_type="status_change",
                    event_time=datetime.now().time(),
                    notes=f"{previous_status} -> {rec.status}",
                ))
        else:
            att = Attendance(
                school_id=school_id,
                child_id=rec.child_id,
                recorded_by=employee_id,
                recorded_by_user_id=current_user.id,
                attendance_date=body.date,
                status=rec.status,
                notes=rec.notes,
            )
            db.add(att)
        upserted += 1

    await db.commit()
    return {"upserted": upserted, "date": body.date}


@router.get("/history", response_model=List[AttendanceHistoryRecord])
async def attendance_history(
    request: Request,
    child_id: Optional[uuid.UUID] = Query(default=None),
    start_date: Optional[date] = Query(default=None),
    end_date: Optional[date] = Query(default=None),
    skip: int = 0,
    limit: int = Query(default=500, ge=1, le=1000),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Return dated attendance records for staff or the current parent."""
    if start_date and end_date and start_date > end_date:
        raise HTTPException(status_code=400, detail="start_date must be on or before end_date")

    roles = set(getattr(current_user, "_roles", set()))
    allowed_child_ids: Optional[set[uuid.UUID]] = None
    if "parent" in roles:
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        allowed_child_ids = set((await db.execute(
            select(ChildGuardian.child_id).where(
                ChildGuardian.school_id == school_id,
                ChildGuardian.guardian_id == guardian_id,
            )
        )).scalars().all())
        if child_id is not None and child_id not in allowed_child_ids:
            raise HTTPException(status_code=403, detail="Not your child")
    else:
        await require_teacher(request, current_user)

    query = (
        select(Attendance, Child)
        .join(Child, Child.id == Attendance.child_id)
        .where(
            Attendance.school_id == school_id,
            Child.school_id == school_id,
        )
    )
    if child_id is not None:
        query = query.where(Attendance.child_id == child_id)
    elif allowed_child_ids is not None:
        if not allowed_child_ids:
            return []
        query = query.where(Attendance.child_id.in_(allowed_child_ids))
    if start_date is not None:
        query = query.where(Attendance.attendance_date >= start_date)
    if end_date is not None:
        query = query.where(Attendance.attendance_date <= end_date)

    rows = (await db.execute(
        query.order_by(Attendance.attendance_date.desc(), Child.first_name, Child.last_name)
        .offset(skip)
        .limit(limit)
    )).all()
    return [
        AttendanceHistoryRecord(
            id=attendance.id,
            child_id=attendance.child_id,
            child_name=f"{child.first_name} {child.last_name}".strip(),
            attendance_date=attendance.attendance_date,
            check_in_time=attendance.check_in_time,
            check_out_time=attendance.check_out_time,
            status=attendance.status,
            notes=attendance.notes,
            created_at=attendance.created_at,
        )
        for attendance, child in rows
    ]


@router.get("/child/{child_id}/log", response_model=List[AttendanceLogEntry])
async def get_child_attendance_log(
    child_id: uuid.UUID,
    date_filter: Optional[date] = Query(default=None, alias="date"),
    skip: int = 0,
    limit: int = 100,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    # Parents can only view their own children's logs
    if getattr(current_user, "_role", None) == "parent":
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

    query = select(AttendanceLog).where(
        AttendanceLog.school_id == school_id,
        AttendanceLog.child_id == child_id,
    )
    if date_filter:
        query = query.where(AttendanceLog.attendance_date == date_filter)
    query = query.order_by(AttendanceLog.attendance_date.desc(), AttendanceLog.event_time.asc())
    query = query.offset(skip).limit(limit)
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/child/{child_id}", response_model=List[AttendanceRecord])
async def get_child_attendance(
    child_id: uuid.UUID,
    date_filter: Optional[date] = Query(default=None, alias="date"),
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    # Parents can only view their own children's attendance
    if getattr(current_user, "_role", None) == "parent":
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

    query = select(Attendance).where(
        Attendance.school_id == school_id, Attendance.child_id == child_id
    )
    if date_filter:
        query = query.where(Attendance.attendance_date == date_filter)
    result = await db.execute(
        query.order_by(Attendance.attendance_date.desc()).offset(skip).limit(limit)
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
            present_days=stats["present"],
            days_present=stats["present"],
            absent=stats["absent"],
            late=stats["late"],
            excused=stats["excused"],
            total_days=total,
        ))

    return summaries


# ─── Day-Status Endpoints ─────────────────────────────────────────────────────

VALID_DAY_STATUSES = {"present", "absent", "excused", "late"}


@router.post("/day-status", response_model=DayStatusOut, status_code=status.HTTP_200_OK)
async def set_day_status(
    body: DayStatusBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    """Set or update the daily attendance status for a child (upsert)."""
    # Verify child belongs to school
    child_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    employee_id = getattr(current_user, "employee_id", None)
    # Upsert: find existing record for this child+date or create new
    result = await db.execute(
        select(AttendanceDayStatus).where(
            AttendanceDayStatus.school_id == school_id,
            AttendanceDayStatus.child_id == body.child_id,
            AttendanceDayStatus.status_date == body.status_date,
        )
    )
    record = result.scalar_one_or_none()

    if record:
        record.status = body.status
        record.notes = body.notes
        record.recorded_by = employee_id
        record.recorded_by_user_id = current_user.id
    else:
        record = AttendanceDayStatus(
            school_id=school_id,
            child_id=body.child_id,
            status_date=body.status_date,
            status=body.status,
            notes=body.notes,
            recorded_by=employee_id,
            recorded_by_user_id=current_user.id,
        )
        db.add(record)

    await db.commit()
    await db.refresh(record)
    return record


@router.get("/day-status", response_model=List[DayStatusOut])
async def list_day_statuses(
    child_id: Optional[uuid.UUID] = Query(default=None),
    date_from: Optional[date] = Query(default=None),
    date_to: Optional[date] = Query(default=None),
    status_filter: Optional[str] = Query(default=None, alias="status"),
    skip: int = 0,
    limit: int = 100,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    """List daily attendance statuses with optional date range and child filter."""
    query = select(AttendanceDayStatus).where(
        AttendanceDayStatus.school_id == school_id,
    )
    if child_id is not None:
        query = query.where(AttendanceDayStatus.child_id == child_id)
    if date_from is not None:
        query = query.where(AttendanceDayStatus.status_date >= date_from)
    if date_to is not None:
        query = query.where(AttendanceDayStatus.status_date <= date_to)
    if status_filter is not None:
        query = query.where(AttendanceDayStatus.status == status_filter)

    query = query.order_by(
        AttendanceDayStatus.status_date.desc(),
        AttendanceDayStatus.child_id,
    ).offset(skip).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/day-status/summary", response_model=List[DayStatusMonthlySummary])
async def day_status_summary(
    month: str,  # YYYY-MM
    child_id: Optional[uuid.UUID] = Query(default=None),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    """Monthly summary based on AttendanceDayStatus records."""
    import calendar
    from collections import defaultdict

    try:
        year_int, month_int = int(month[:4]), int(month[5:7])
    except (ValueError, IndexError):
        raise HTTPException(status_code=400, detail="month must be in YYYY-MM format")

    from_date = date(year_int, month_int, 1)
    last_day = calendar.monthrange(year_int, month_int)[1]
    to_date = date(year_int, month_int, last_day)

    query = select(AttendanceDayStatus).where(
        AttendanceDayStatus.school_id == school_id,
        AttendanceDayStatus.status_date >= from_date,
        AttendanceDayStatus.status_date <= to_date,
    )
    if child_id is not None:
        query = query.where(AttendanceDayStatus.child_id == child_id)

    result = await db.execute(query)
    records = result.scalars().all()

    child_stats: dict = defaultdict(lambda: {"present": 0, "absent": 0, "late": 0, "excused": 0})
    child_ids_seen = set()
    for r in records:
        child_ids_seen.add(r.child_id)
        s = r.status if r.status in VALID_DAY_STATUSES else "present"
        child_stats[r.child_id][s] += 1

    if not child_ids_seen:
        return []

    children_result = await db.execute(
        select(Child).where(Child.school_id == school_id, Child.id.in_(child_ids_seen))
    )
    children = {c.id: c for c in children_result.scalars().all()}

    summaries = []
    for cid, stats in child_stats.items():
        child = children.get(cid)
        if not child:
            continue
        total = sum(stats.values())
        summaries.append(DayStatusMonthlySummary(
            child_id=cid,
            first_name=child.first_name,
            last_name=child.last_name,
            present=stats["present"],
            absent=stats["absent"],
            late=stats["late"],
            excused=stats["excused"],
            total_days=total,
        ))

    return summaries
