"""K-12 lesson-level attendance (livro de ponto)."""
import uuid
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_teacher
from app.models.academic import Enrollment, LessonAttendance, Schedule, ScheduleSlot, TimetablePeriod, Turma
from app.models.grades import Subject
from app.models.person import Child
from app.schemas.lesson_attendance import (
    BulkUpsertRequest,
    SessionResponse,
    LessonAttendanceRecord,
    TodaySession,
    TurmaSummaryResponse,
    StudentSubjectSummary,
)

router = APIRouter(prefix="/lesson-attendance", tags=["lesson-attendance"])


# ---------------------------------------------------------------------------
# GET /lesson-attendance/session
# Returns enrolled students + their current status for one session.
# ---------------------------------------------------------------------------

@router.get("/session", response_model=SessionResponse)
async def get_session(
    schedule_id: uuid.UUID = Query(...),
    subject_id: uuid.UUID = Query(...),
    date: date = Query(...),
    period_id: uuid.UUID = Query(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_teacher),
):
    # Get subject info
    subj = await db.get(Subject, subject_id)
    # Get period info
    period = await db.get(TimetablePeriod, period_id)
    # Get schedule → turma name
    schedule = await db.get(Schedule, schedule_id)
    turma = await db.get(Turma, schedule.turma_id) if schedule else None

    # Enrolled children
    enrolled_q = (
        select(Child)
        .join(Enrollment, Enrollment.child_id == Child.id)
        .where(
            Enrollment.schedule_id == schedule_id,
            Enrollment.school_id == school_id,
            Enrollment.status == "active",
        )
        .order_by(Child.name)
    )
    result = await db.execute(enrolled_q)
    children = result.scalars().all()

    # Existing attendance records for this session
    existing_q = select(LessonAttendance).where(
        LessonAttendance.schedule_id == schedule_id,
        LessonAttendance.subject_id == subject_id,
        LessonAttendance.date == date,
        LessonAttendance.period_id == period_id,
        LessonAttendance.school_id == school_id,
    )
    existing_result = await db.execute(existing_q)
    existing = {r.child_id: r for r in existing_result.scalars().all()}

    records = []
    for child in children:
        rec = existing.get(child.id)
        records.append(LessonAttendanceRecord(
            id=rec.id if rec else uuid.uuid4(),
            child_id=child.id,
            child_name=child.name,
            status=rec.status if rec else "present",
            notes=rec.notes if rec else None,
        ))

    return SessionResponse(
        schedule_id=schedule_id,
        subject_id=subject_id,
        subject_name=subj.name if subj else None,
        subject_code=subj.code if subj else None,
        date=date,
        period_id=period_id,
        period_name=period.name if period else None,
        period_number=period.period_number if period else None,
        slot_time=period.start_time if period else None,
        turma_name=turma.name if turma else None,
        records=records,
    )


# ---------------------------------------------------------------------------
# POST /lesson-attendance/session/bulk  — upsert a full session at once
# ---------------------------------------------------------------------------

@router.post("/session/bulk", status_code=204)
async def bulk_upsert_session(
    body: BulkUpsertRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user: object = Depends(require_teacher),
):
    # Get employee_id from current user (teacher)
    employee_id = getattr(user, "employee_id", None)

    # Delete existing records for this session
    existing_q = select(LessonAttendance).where(
        LessonAttendance.schedule_id == body.schedule_id,
        LessonAttendance.subject_id == body.subject_id,
        LessonAttendance.date == body.date,
        LessonAttendance.period_id == body.period_id,
        LessonAttendance.school_id == school_id,
    )
    existing_result = await db.execute(existing_q)
    for rec in existing_result.scalars().all():
        await db.delete(rec)

    # Insert new records
    for item in body.records:
        la = LessonAttendance(
            school_id=school_id,
            schedule_id=body.schedule_id,
            subject_id=body.subject_id,
            employee_id=employee_id,
            date=body.date,
            period_id=body.period_id,
            child_id=item.child_id,
            status=item.status,
            notes=item.notes,
        )
        db.add(la)

    await db.commit()


# ---------------------------------------------------------------------------
# GET /lesson-attendance/turma/{schedule_id}/summary
# Per-student per-subject absence summary for one turma.
# ---------------------------------------------------------------------------

@router.get("/turma/{schedule_id}/summary", response_model=TurmaSummaryResponse)
async def turma_summary(
    schedule_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _: object = Depends(require_teacher),
):
    schedule = await db.get(Schedule, schedule_id)
    turma = await db.get(Turma, schedule.turma_id) if schedule else None

    # All lesson_attendance rows for this turma
    rows_q = select(LessonAttendance).where(
        LessonAttendance.schedule_id == schedule_id,
        LessonAttendance.school_id == school_id,
    )
    rows_result = await db.execute(rows_q)
    rows = rows_result.scalars().all()

    # Build summary grouped by (child_id, subject_id)
    from collections import defaultdict
    groups: dict[tuple, dict] = defaultdict(lambda: {"present": 0, "absent": 0, "late": 0, "justified": 0})
    for r in rows:
        key = (r.child_id, r.subject_id)
        groups[key][r.status] = groups[key].get(r.status, 0) + 1

    # Child and subject name lookups
    child_ids = {r.child_id for r in rows}
    subject_ids = {r.subject_id for r in rows}

    child_map: dict[uuid.UUID, str] = {}
    if child_ids:
        c_result = await db.execute(select(Child).where(Child.id.in_(child_ids)))
        child_map = {c.id: c.name for c in c_result.scalars().all()}

    subject_map: dict[uuid.UUID, str] = {}
    if subject_ids:
        s_result = await db.execute(select(Subject).where(Subject.id.in_(subject_ids)))
        subject_map = {s.id: s.name for s in s_result.scalars().all()}

    summary_rows = []
    for (child_id, subject_id), counts in groups.items():
        total = sum(counts.values())
        absent = counts["absent"] + counts["late"]
        pct = round(absent / total * 100, 1) if total else 0.0
        summary_rows.append(StudentSubjectSummary(
            child_id=child_id,
            child_name=child_map.get(child_id, ""),
            subject_id=subject_id,
            subject_name=subject_map.get(subject_id, ""),
            total_lessons=total,
            present=counts["present"],
            absent=counts["absent"],
            late=counts["late"],
            justified=counts["justified"],
            absence_pct=pct,
            at_risk=pct >= 25,
        ))

    summary_rows.sort(key=lambda r: (r.child_name, r.subject_name))

    return TurmaSummaryResponse(
        schedule_id=schedule_id,
        turma_name=turma.name if turma else "",
        rows=summary_rows,
    )


# ---------------------------------------------------------------------------
# GET /lesson-attendance/today — teacher's sessions today with taken/not taken
# ---------------------------------------------------------------------------

@router.get("/today", response_model=list[TodaySession])
async def today_sessions(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user: object = Depends(require_teacher),
):
    from datetime import date as date_cls
    today = date_cls.today()

    employee_id = getattr(user, "employee_id", None)
    if not employee_id:
        return []

    # Find timetable cells assigned to this teacher today (day_of_week = weekday)
    day_of_week = today.weekday()  # 0=Mon..4=Fri
    slots_q = (
        select(ScheduleSlot)
        .join(TimetablePeriod, TimetablePeriod.id == ScheduleSlot.period_id)
        .where(
            ScheduleSlot.employee_id == employee_id,
            ScheduleSlot.day_of_week == day_of_week,
            ScheduleSlot.subject_id.isnot(None),
            ScheduleSlot.period_id.isnot(None),
        )
        .order_by(TimetablePeriod.period_number)
    )
    slots_result = await db.execute(slots_q)
    slots = slots_result.scalars().all()

    # For each slot, check if attendance is already taken and count enrolled students
    result_sessions = []
    for slot in slots:
        # Count enrolled active students in this schedule
        count_q = select(func.count(Enrollment.id)).where(
            Enrollment.schedule_id == slot.schedule_id,
            Enrollment.school_id == school_id,
            Enrollment.status == "active",
        )
        count_result = await db.execute(count_q)
        student_count = count_result.scalar() or 0

        # Check if any attendance record exists for this session today
        taken_q = select(func.count(LessonAttendance.id)).where(
            LessonAttendance.schedule_id == slot.schedule_id,
            LessonAttendance.subject_id == slot.subject_id,
            LessonAttendance.date == today,
            LessonAttendance.period_id == slot.period_id,
            LessonAttendance.school_id == school_id,
        )
        taken_result = await db.execute(taken_q)
        taken_count = taken_result.scalar() or 0

        # Get schedule/turma name
        schedule = await db.get(Schedule, slot.schedule_id)
        turma_obj = await db.get(Turma, schedule.turma_id) if schedule else None
        period = await db.get(TimetablePeriod, slot.period_id)
        subject = await db.get(Subject, slot.subject_id)

        result_sessions.append(TodaySession(
            schedule_id=slot.schedule_id,
            turma_name=turma_obj.name if turma_obj else "",
            subject_id=slot.subject_id,
            subject_name=subject.name if subject else None,
            period_id=slot.period_id,
            period_name=period.name if period else None,
            period_number=period.period_number if period else None,
            slot_time=period.start_time if period else None,
            attendance_taken=taken_count > 0,
            student_count=student_count,
        ))

    return result_sessions
