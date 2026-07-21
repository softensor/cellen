"""
Timetable router — K-12 period-based schedules.

Endpoints:
  GET  /timetable/periods                 — list school period definitions
  POST /timetable/periods                 — create period
  PATCH /timetable/periods/{id}           — update period
  DELETE /timetable/periods/{id}          — delete period

  GET  /timetable/grid                    — full week grid for one turma (schedule)
  POST /timetable/grid/cells              — upsert one grid cell
  DELETE /timetable/grid/cells/{slot_id}  — clear one cell

  GET  /timetable/teacher                 — current teacher's own week view
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_coordinator, require_teacher
from app.models.academic import Schedule, ScheduleSlot, TimetablePeriod, Turma, SchoolYear
from app.models.employee import Employee
from app.models.grades import Subject
from app.schemas.timetable import (
    PeriodCreate, PeriodUpdate, PeriodResponse,
    TimetableCellUpsert, TimetableCellResponse, TimetableGridResponse, TeacherSlot,
)

router = APIRouter(prefix="/timetable", tags=["Timetable"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cell_to_response(slot: ScheduleSlot) -> TimetableCellResponse:
    period_number = slot.period.period_number if slot.period else None
    period_name = slot.period.name if slot.period else None
    subject_name = slot.subject.name if slot.subject else None
    subject_code = getattr(slot.subject, 'code', None) if slot.subject else None
    employee = getattr(slot, '_employee', None)
    employee_name = None
    if employee:
        employee_name = f"{employee.first_name} {employee.last_name}".strip()
    elif slot.employee_id:
        employee_name = str(slot.employee_id)  # fallback
    return TimetableCellResponse(
        id=slot.id,
        schedule_id=slot.schedule_id,
        day_of_week=slot.day_of_week,
        slot_time=slot.slot_time,
        period_id=slot.period_id,
        period_number=period_number,
        period_name=period_name,
        subject_id=slot.subject_id,
        subject_name=subject_name,
        subject_code=subject_code,
        employee_id=slot.employee_id,
        employee_name=employee_name,
        room=slot.room,
    )


# ---------------------------------------------------------------------------
# Periods
# ---------------------------------------------------------------------------

@router.get("/periods", response_model=list[PeriodResponse])
async def list_periods(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(TimetablePeriod)
        .where(TimetablePeriod.school_id == school_id)
        .order_by(TimetablePeriod.period_number)
    )
    return result.scalars().all()


@router.post("/periods", response_model=PeriodResponse, status_code=status.HTTP_201_CREATED)
async def create_period(
    body: PeriodCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    period = TimetablePeriod(school_id=school_id, **body.model_dump())
    db.add(period)
    await db.commit()
    await db.refresh(period)
    return period


@router.patch("/periods/{period_id}", response_model=PeriodResponse)
async def update_period(
    period_id: uuid.UUID,
    body: PeriodUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(TimetablePeriod).where(
            TimetablePeriod.id == period_id,
            TimetablePeriod.school_id == school_id,
        )
    )
    period = result.scalar_one_or_none()
    if not period:
        raise HTTPException(status_code=404, detail="Period not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(period, field, value)
    await db.commit()
    await db.refresh(period)
    return period


@router.delete("/periods/{period_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_period(
    period_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(TimetablePeriod).where(
            TimetablePeriod.id == period_id,
            TimetablePeriod.school_id == school_id,
        )
    )
    period = result.scalar_one_or_none()
    if not period:
        raise HTTPException(status_code=404, detail="Period not found")
    await db.delete(period)
    await db.commit()


# ---------------------------------------------------------------------------
# Timetable grid
# ---------------------------------------------------------------------------

@router.get("/grid", response_model=TimetableGridResponse)
async def get_timetable_grid(
    schedule_id: uuid.UUID = Query(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    # Load schedule
    sched_result = await db.execute(
        select(Schedule).where(
            Schedule.id == schedule_id,
            Schedule.school_id == school_id,
        )
    )
    schedule = sched_result.scalar_one_or_none()
    if not schedule:
        raise HTTPException(status_code=404, detail="Schedule not found")

    # Load turma + year
    turma_result = await db.execute(select(Turma).where(Turma.id == schedule.turma_id))
    turma = turma_result.scalar_one_or_none()
    year_result = await db.execute(select(SchoolYear).where(SchoolYear.id == schedule.school_year_id))
    year = year_result.scalar_one_or_none()

    # Load periods
    periods_result = await db.execute(
        select(TimetablePeriod)
        .where(TimetablePeriod.school_id == school_id)
        .order_by(TimetablePeriod.period_number)
    )
    periods = periods_result.scalars().all()

    # Load slots (K-12 cells)
    slots_result = await db.execute(
        select(ScheduleSlot)
        .where(ScheduleSlot.schedule_id == schedule_id, ScheduleSlot.subject_id.is_not(None))
        .order_by(ScheduleSlot.day_of_week, ScheduleSlot.slot_time)
    )
    slots = slots_result.scalars().all()

    # Enrich with employee names
    emp_ids = {s.employee_id for s in slots if s.employee_id}
    employees: dict = {}
    if emp_ids:
        emp_result = await db.execute(select(Employee).where(Employee.id.in_(emp_ids)))
        for emp in emp_result.scalars().all():
            employees[emp.id] = emp
    for slot in slots:
        slot._employee = employees.get(slot.employee_id)

    return TimetableGridResponse(
        schedule_id=schedule.id,
        turma_id=turma.id if turma else schedule.turma_id,
        turma_name=turma.name if turma else "",
        school_year_id=year.id if year else schedule.school_year_id,
        school_year_label=year.year_label if year else "",
        periods=[PeriodResponse.model_validate(p) for p in periods],
        cells=[_cell_to_response(s) for s in slots],
    )


@router.post("/grid/cells", response_model=TimetableCellResponse, status_code=status.HTTP_201_CREATED)
async def upsert_cell(
    body: TimetableCellUpsert,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    # Validate period belongs to school
    period_result = await db.execute(
        select(TimetablePeriod).where(
            TimetablePeriod.id == body.period_id,
            TimetablePeriod.school_id == school_id,
        )
    )
    period = period_result.scalar_one_or_none()
    if not period:
        raise HTTPException(status_code=404, detail="Period not found")

    # Check for existing slot at same day+period in this schedule
    existing_result = await db.execute(
        select(ScheduleSlot).where(
            ScheduleSlot.schedule_id == body.schedule_id,
            ScheduleSlot.day_of_week == body.day_of_week,
            ScheduleSlot.period_id == body.period_id,
        )
    )
    slot = existing_result.scalar_one_or_none()

    if slot is None:
        slot = ScheduleSlot(
            school_id=school_id,
            schedule_id=body.schedule_id,
            day_of_week=body.day_of_week,
            slot_time=period.start_time,
            period_id=body.period_id,
        )
        db.add(slot)

    slot.subject_id = body.subject_id
    slot.employee_id = body.employee_id
    slot.room = body.room
    slot.slot_time = period.start_time  # keep in sync with period

    await db.commit()
    await db.refresh(slot)
    slot._employee = None
    if slot.employee_id:
        emp_r = await db.execute(select(Employee).where(Employee.id == slot.employee_id))
        slot._employee = emp_r.scalar_one_or_none()
    return _cell_to_response(slot)


@router.delete("/grid/cells/{slot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def clear_cell(
    slot_id: int,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(ScheduleSlot).where(
            ScheduleSlot.id == slot_id,
            ScheduleSlot.school_id == school_id,
        )
    )
    slot = result.scalar_one_or_none()
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    await db.delete(slot)
    await db.commit()


# ---------------------------------------------------------------------------
# Teacher's own timetable view
# ---------------------------------------------------------------------------

@router.get("/teacher", response_model=list[TeacherSlot])
async def my_timetable(
    school_year_id: Optional[uuid.UUID] = Query(None),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user),
):
    employee_id = getattr(user, "employee_id", None) or getattr(user, "_employee_id", None)
    if not employee_id:
        # Try from token payload
        from app.core.dependencies import get_current_user as _gcu
        emp_id_str = getattr(user, "employee_id", None)
        if emp_id_str:
            employee_id = uuid.UUID(str(emp_id_str))

    if not employee_id:
        return []

    # Find active year if not specified
    if school_year_id is None:
        yr_result = await db.execute(
            select(SchoolYear).where(
                SchoolYear.school_id == school_id,
                SchoolYear.is_active == True,  # noqa: E712
            )
        )
        active_year = yr_result.scalar_one_or_none()
        if active_year:
            school_year_id = active_year.id

    if school_year_id is None:
        return []

    # Find all schedule slots where this teacher is assigned
    slots_result = await db.execute(
        select(ScheduleSlot, Schedule, Turma)
        .join(Schedule, Schedule.id == ScheduleSlot.schedule_id)
        .join(Turma, Turma.id == Schedule.turma_id)
        .where(
            Schedule.school_id == school_id,
            Schedule.school_year_id == school_year_id,
            ScheduleSlot.employee_id == employee_id,
            ScheduleSlot.subject_id.is_not(None),
        )
        .order_by(ScheduleSlot.day_of_week, ScheduleSlot.slot_time)
    )
    rows = slots_result.all()

    result = []
    for slot, sched, turma in rows:
        result.append(TeacherSlot(
            day_of_week=slot.day_of_week,
            period_id=slot.period_id,
            period_name=slot.period.name if slot.period else None,
            period_number=slot.period.period_number if slot.period else None,
            slot_time=slot.slot_time,
            subject_name=slot.subject_name,
            turma_name=turma.name,
            room=slot.room,
            schedule_id=sched.id,
        ))
    return result
