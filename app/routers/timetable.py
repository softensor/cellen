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
import asyncio
import functools
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_coordinator, require_teacher
from app.models.academic import (
    Schedule, ScheduleSlot, TimetablePeriod, TimetableRequirement,
    TimetableTeacherConstraint, Turma, SchoolYear,
)
from app.models.employee import Employee
from app.models.grades import Subject, TurmaSubject
from app.schemas.timetable import (
    PeriodCreate, PeriodUpdate, PeriodResponse,
    TimetableCellUpsert, TimetableCellResponse, TimetableGridResponse, TeacherSlot,
    RequirementCreate, RequirementUpdate, RequirementResponse,
    TeacherConstraintCreate, TeacherConstraintResponse,
    GenerateRequest, GenerateResponse, GeneratedCell, GenerateConflict, ApplyRequest,
)
from app.services.timetable_solver import (
    SolverRequirement, SolverPeriod, solve as run_solver,
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
            subject_name=getattr(slot.subject, 'name', None) if slot.subject else None,
            turma_name=turma.name,
            room=slot.room,
            schedule_id=sched.id,
        ))
    return result


# ---------------------------------------------------------------------------
# Requirements (solver input cards)
# ---------------------------------------------------------------------------

def _req_to_response(req: TimetableRequirement, employees: dict) -> RequirementResponse:
    emp = employees.get(req.employee_id)
    employee_name = (
        f"{emp.first_name} {emp.last_name}".strip() if emp else str(req.employee_id)
    )
    subject_name = req.subject.name if req.subject else None
    subject_code = getattr(req.subject, 'code', None) if req.subject else None
    return RequirementResponse(
        id=req.id,
        schedule_id=req.schedule_id,
        subject_id=req.subject_id,
        subject_name=subject_name,
        subject_code=subject_code,
        employee_id=req.employee_id,
        employee_name=employee_name,
        periods_per_week=req.periods_per_week,
        allow_double_period=req.allow_double_period,
        preferred_time_of_day=req.preferred_time_of_day,
    )


@router.get("/requirements", response_model=list[RequirementResponse])
async def list_requirements(
    schedule_id: uuid.UUID = Query(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    """List all requirement cards for a given schedule (class+year)."""
    # Verify schedule belongs to school
    sched = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    if not sched.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Schedule not found")

    result = await db.execute(
        select(TimetableRequirement)
        .where(
            TimetableRequirement.schedule_id == schedule_id,
            TimetableRequirement.school_id == school_id,
        )
        .order_by(TimetableRequirement.created_at)
    )
    reqs = result.scalars().all()

    emp_ids = {r.employee_id for r in reqs}
    employees: dict = {}
    if emp_ids:
        emp_result = await db.execute(select(Employee).where(Employee.id.in_(emp_ids)))
        for emp in emp_result.scalars().all():
            employees[emp.id] = emp

    return [_req_to_response(r, employees) for r in reqs]


@router.post("/requirements", response_model=RequirementResponse, status_code=status.HTTP_201_CREATED)
async def create_requirement(
    body: RequirementCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    """Create a requirement card (subject + teacher + periods/week for a class)."""
    # Verify schedule belongs to school
    sched = await db.execute(
        select(Schedule).where(Schedule.id == body.schedule_id, Schedule.school_id == school_id)
    )
    if not sched.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Schedule not found")

    # Check for duplicate (same schedule+subject+employee)
    existing = await db.execute(
        select(TimetableRequirement).where(
            TimetableRequirement.schedule_id == body.schedule_id,
            TimetableRequirement.subject_id == body.subject_id,
            TimetableRequirement.employee_id == body.employee_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="Já existe um requisito para esta disciplina e professor nesta turma",
        )

    if body.periods_per_week < 1 or body.periods_per_week > 10:
        raise HTTPException(status_code=400, detail="periods_per_week deve ser entre 1 e 10")

    req = TimetableRequirement(school_id=school_id, **body.model_dump())
    db.add(req)
    await db.commit()
    await db.refresh(req)

    emp_result = await db.execute(select(Employee).where(Employee.id == req.employee_id))
    emp = emp_result.scalar_one_or_none()
    return _req_to_response(req, {req.employee_id: emp} if emp else {})


@router.patch("/requirements/{requirement_id}", response_model=RequirementResponse)
async def update_requirement(
    requirement_id: uuid.UUID,
    body: RequirementUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(TimetableRequirement).where(
            TimetableRequirement.id == requirement_id,
            TimetableRequirement.school_id == school_id,
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Requisito não encontrado")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(req, field, value)

    await db.commit()
    await db.refresh(req)

    emp_result = await db.execute(select(Employee).where(Employee.id == req.employee_id))
    emp = emp_result.scalar_one_or_none()
    return _req_to_response(req, {req.employee_id: emp} if emp else {})


@router.delete("/requirements/{requirement_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_requirement(
    requirement_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(TimetableRequirement).where(
            TimetableRequirement.id == requirement_id,
            TimetableRequirement.school_id == school_id,
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="Requisito não encontrado")
    await db.delete(req)
    await db.commit()


# ---------------------------------------------------------------------------
# Teacher unavailability constraints
# ---------------------------------------------------------------------------

@router.get("/constraints", response_model=list[TeacherConstraintResponse])
async def list_teacher_constraints(
    employee_id: uuid.UUID = Query(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    """List unavailable slots for a teacher."""
    result = await db.execute(
        select(TimetableTeacherConstraint).where(
            TimetableTeacherConstraint.employee_id == employee_id,
            TimetableTeacherConstraint.school_id == school_id,
        ).order_by(TimetableTeacherConstraint.day_of_week, TimetableTeacherConstraint.period_id)
    )
    return result.scalars().all()


@router.post("/constraints", response_model=TeacherConstraintResponse, status_code=status.HTTP_201_CREATED)
async def create_teacher_constraint(
    body: TeacherConstraintCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    """Mark a teacher as unavailable for a specific day+period."""
    if body.day_of_week < 0 or body.day_of_week > 4:
        raise HTTPException(status_code=400, detail="day_of_week deve ser 0 (2ª) a 4 (6ª)")

    existing = await db.execute(
        select(TimetableTeacherConstraint).where(
            TimetableTeacherConstraint.employee_id == body.employee_id,
            TimetableTeacherConstraint.day_of_week == body.day_of_week,
            TimetableTeacherConstraint.period_id == body.period_id,
            TimetableTeacherConstraint.school_id == school_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Restrição já existe")

    constraint = TimetableTeacherConstraint(school_id=school_id, **body.model_dump())
    db.add(constraint)
    await db.commit()
    await db.refresh(constraint)
    return constraint


@router.delete("/constraints/{constraint_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_teacher_constraint(
    constraint_id: int,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    result = await db.execute(
        select(TimetableTeacherConstraint).where(
            TimetableTeacherConstraint.id == constraint_id,
            TimetableTeacherConstraint.school_id == school_id,
        )
    )
    constraint = result.scalar_one_or_none()
    if not constraint:
        raise HTTPException(status_code=404, detail="Restrição não encontrada")
    await db.delete(constraint)
    await db.commit()


# ---------------------------------------------------------------------------
# Solver: generate preview
# ---------------------------------------------------------------------------

@router.post("/generate", response_model=GenerateResponse)
async def generate_timetable(
    body: GenerateRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    """
    Run the constraint solver for the given schedules and return a proposed
    timetable. Nothing is written to the database — call /apply to commit.

    Solving multiple schedules simultaneously ensures cross-class teacher
    conflicts are avoided (e.g. Prof. Silva can't teach 10A and 10B at the
    same time).
    """
    if not body.schedule_ids:
        raise HTTPException(status_code=400, detail="schedule_ids não pode estar vazio")

    # Verify all schedules belong to this school
    sched_result = await db.execute(
        select(Schedule).where(
            Schedule.id.in_(body.schedule_ids),
            Schedule.school_id == school_id,
        )
    )
    found_schedules = {s.id for s in sched_result.scalars().all()}
    missing = set(body.schedule_ids) - found_schedules
    if missing:
        raise HTTPException(status_code=404, detail="Um ou mais schedules não encontrados")

    # Load requirements for all requested schedules
    req_result = await db.execute(
        select(TimetableRequirement).where(
            TimetableRequirement.schedule_id.in_(body.schedule_ids),
            TimetableRequirement.school_id == school_id,
        )
    )
    db_reqs = req_result.scalars().all()

    if not db_reqs:
        raise HTTPException(
            status_code=400,
            detail="Nenhum requisito encontrado para os horários seleccionados. "
                   "Adicione os cartões de requisitos primeiro.",
        )

    # Load employee names
    emp_ids = {r.employee_id for r in db_reqs}
    emp_result = await db.execute(select(Employee).where(Employee.id.in_(emp_ids)))
    employees = {e.id: e for e in emp_result.scalars().all()}

    # Load non-break periods (ordered)
    period_result = await db.execute(
        select(TimetablePeriod)
        .where(
            TimetablePeriod.school_id == school_id,
            TimetablePeriod.is_break == False,  # noqa: E712
        )
        .order_by(TimetablePeriod.period_number)
    )
    db_periods = period_result.scalars().all()
    if not db_periods:
        raise HTTPException(
            status_code=400,
            detail="Nenhum período lectivo definido. Configure os períodos primeiro.",
        )

    # Load teacher constraints (unavailability)
    constraint_result = await db.execute(
        select(TimetableTeacherConstraint).where(
            TimetableTeacherConstraint.employee_id.in_(emp_ids),
            TimetableTeacherConstraint.school_id == school_id,
        )
    )
    blocked: set[tuple] = {
        (c.employee_id, c.day_of_week, c.period_id)
        for c in constraint_result.scalars().all()
    }

    # Build solver inputs
    solver_reqs = []
    for r in db_reqs:
        emp = employees.get(r.employee_id)
        emp_name = (
            f"{emp.first_name} {emp.last_name}".strip() if emp else str(r.employee_id)
        )
        sub_name = r.subject.name if r.subject else str(r.subject_id)
        solver_reqs.append(SolverRequirement(
            id=r.id,
            schedule_id=r.schedule_id,
            subject_id=r.subject_id,
            subject_name=sub_name,
            employee_id=r.employee_id,
            employee_name=emp_name,
            periods_per_week=r.periods_per_week,
            allow_double_period=r.allow_double_period,
            preferred_time_of_day=r.preferred_time_of_day,
        ))

    solver_periods = [
        SolverPeriod(id=p.id, period_number=p.period_number)
        for p in db_periods
    ]

    # Run solver off the async event loop (it blocks for up to 5 s with OR-Tools,
    # then falls back to greedy which completes in milliseconds).
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None,
        functools.partial(run_solver, solver_reqs, solver_periods, blocked, 5.0),
    )

    # Build response with enriched names
    period_map = {p.id: p for p in db_periods}
    subject_map = {r.subject_id: r.subject.name for r in db_reqs if r.subject}

    cells_out = []
    for cell in result.cells:
        emp = employees.get(cell.employee_id)
        cells_out.append(GeneratedCell(
            schedule_id=cell.schedule_id,
            day_of_week=cell.day_of_week,
            period_id=cell.period_id,
            subject_id=cell.subject_id,
            subject_name=subject_map.get(cell.subject_id),
            employee_id=cell.employee_id,
            employee_name=(
                f"{emp.first_name} {emp.last_name}".strip() if emp else None
            ),
        ))

    conflicts_out = [
        GenerateConflict(
            requirement_id=c.requirement_id,
            subject_name=c.subject_name,
            employee_name=c.employee_name,
            periods_requested=c.periods_requested,
            periods_assigned=c.periods_assigned,
            reason=c.reason,
        )
        for c in result.conflicts
    ]

    return GenerateResponse(
        status=result.status,
        cells=cells_out,
        conflicts=conflicts_out,
    )


# ---------------------------------------------------------------------------
# Solver: apply (commit proposed grid to DB)
# ---------------------------------------------------------------------------

@router.post("/apply", status_code=status.HTTP_201_CREATED)
async def apply_timetable(
    body: ApplyRequest,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_coordinator),
):
    """
    Write the solver-proposed cells to the database as ScheduleSlots.
    If replace_existing=True (default), all existing K-12 slots for the
    given schedules are deleted first, so this is idempotent.
    """
    if not body.schedule_ids:
        raise HTTPException(status_code=400, detail="schedule_ids não pode estar vazio")

    # Verify schedules belong to school and load their turma/year metadata
    sched_result = await db.execute(
        select(Schedule).where(
            Schedule.id.in_(body.schedule_ids),
            Schedule.school_id == school_id,
        )
    )
    schedules = sched_result.scalars().all()
    found = {s.id for s in schedules}
    if len(found) != len(body.schedule_ids):
        raise HTTPException(status_code=404, detail="Um ou mais schedules não encontrados")
    schedule_meta = {s.id: s for s in schedules}

    # Load period start times (needed for slot_time)
    period_ids = {c.period_id for c in body.cells}
    period_result = await db.execute(
        select(TimetablePeriod).where(TimetablePeriod.id.in_(period_ids))
    )
    period_map = {p.id: p for p in period_result.scalars().all()}

    if body.replace_existing:
        # Delete all existing K-12 slots (subject_id is not null) for these schedules
        existing_result = await db.execute(
            select(ScheduleSlot).where(
                ScheduleSlot.schedule_id.in_(body.schedule_ids),
                ScheduleSlot.subject_id.is_not(None),
            )
        )
        for slot in existing_result.scalars().all():
            await db.delete(slot)
        await db.flush()

    created = 0
    for cell in body.cells:
        period = period_map.get(cell.period_id)
        if not period:
            continue  # skip cells referencing unknown periods

        slot = ScheduleSlot(
            school_id=school_id,
            schedule_id=cell.schedule_id,
            day_of_week=cell.day_of_week,
            slot_time=period.start_time,
            period_id=cell.period_id,
            subject_id=cell.subject_id,
            employee_id=cell.employee_id,
        )
        db.add(slot)
        created += 1

    # ── Auto-sync TurmaSubject from timetable (single source of truth) ──────────
    # Collect unique (turma, subject, year, teacher) combos from applied cells.
    # This means Pautas & Notas never needs manual teacher-class assignment.
    seen_ts: set[tuple] = set()
    for cell in body.cells:
        sched = schedule_meta.get(cell.schedule_id)
        if sched is None or cell.subject_id is None or cell.employee_id is None:
            continue
        key = (sched.turma_id, cell.subject_id, sched.school_year_id)
        if key in seen_ts:
            continue
        seen_ts.add(key)
        # Upsert: update teacher if record already exists, else create
        existing = await db.execute(
            select(TurmaSubject).where(
                TurmaSubject.school_id == school_id,
                TurmaSubject.turma_id == sched.turma_id,
                TurmaSubject.subject_id == cell.subject_id,
                TurmaSubject.school_year_id == sched.school_year_id,
            )
        )
        ts = existing.scalar_one_or_none()
        if ts:
            ts.teacher_id = cell.employee_id  # update to latest timetable assignment
        else:
            db.add(TurmaSubject(
                school_id=school_id,
                turma_id=sched.turma_id,
                subject_id=cell.subject_id,
                school_year_id=sched.school_year_id,
                teacher_id=cell.employee_id,
            ))

    await db.commit()
    return {"created": created, "schedules": len(body.schedule_ids)}
