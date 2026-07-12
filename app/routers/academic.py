import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher
from app.models.academic import (
    Activity, Enrollment, Schedule, ScheduleSlot, ScheduleTeacher, SchoolYear, Turma
)
from app.schemas.academic import (
    ActivityCreate, ActivityResponse, ActivityUpdate,
    EnrollmentCreate, EnrollmentResponse, EnrollmentUpdate,
    ScheduleCreate, ScheduleResponse, ScheduleSlotCreate, ScheduleSlotResponse,
    ScheduleTeacherAssign, ScheduleTeacherResponse, ScheduleUpdate,
    TurmaCreate, TurmaResponse, TurmaUpdate,
)

router = APIRouter(prefix="/academic", tags=["Academic"])


# ─── Turmas ───────────────────────────────────────────────────────────────────

@router.get("/turmas", response_model=list[TurmaResponse])
async def list_turmas(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Turma).where(Turma.school_id == school_id).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/turmas", response_model=TurmaResponse, status_code=status.HTTP_201_CREATED)
async def create_turma(
    body: TurmaCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    turma = Turma(school_id=school_id, **body.model_dump())
    db.add(turma)
    await db.commit()
    await db.refresh(turma)
    return turma


@router.get("/turmas/{turma_id}", response_model=TurmaResponse)
async def get_turma(
    turma_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Turma).where(Turma.id == turma_id, Turma.school_id == school_id)
    )
    turma = result.scalar_one_or_none()
    if turma is None:
        raise HTTPException(status_code=404, detail="Turma not found")
    return turma


@router.patch("/turmas/{turma_id}", response_model=TurmaResponse)
async def update_turma(
    turma_id: uuid.UUID,
    body: TurmaUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Turma).where(Turma.id == turma_id, Turma.school_id == school_id)
    )
    turma = result.scalar_one_or_none()
    if turma is None:
        raise HTTPException(status_code=404, detail="Turma not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(turma, field, value)
    await db.commit()
    await db.refresh(turma)
    return turma


@router.delete("/turmas/{turma_id}")
async def delete_turma(
    turma_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Turma).where(Turma.id == turma_id, Turma.school_id == school_id)
    )
    turma = result.scalar_one_or_none()
    if turma is None:
        raise HTTPException(status_code=404, detail="Turma not found")
    await db.delete(turma)
    await db.commit()
    return {"message": "Turma deleted"}


# ─── Activities ───────────────────────────────────────────────────────────────

@router.get("/activities", response_model=list[ActivityResponse])
async def list_activities(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Activity).where(Activity.school_id == school_id).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/activities", response_model=ActivityResponse, status_code=status.HTTP_201_CREATED)
async def create_activity(
    body: ActivityCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    activity = Activity(school_id=school_id, **body.model_dump())
    db.add(activity)
    await db.commit()
    await db.refresh(activity)
    return activity


@router.patch("/activities/{activity_id}", response_model=ActivityResponse)
async def update_activity(
    activity_id: uuid.UUID,
    body: ActivityUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Activity).where(Activity.id == activity_id, Activity.school_id == school_id)
    )
    activity = result.scalar_one_or_none()
    if activity is None:
        raise HTTPException(status_code=404, detail="Activity not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(activity, field, value)
    await db.commit()
    await db.refresh(activity)
    return activity


@router.delete("/activities/{activity_id}")
async def delete_activity(
    activity_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Activity).where(Activity.id == activity_id, Activity.school_id == school_id)
    )
    activity = result.scalar_one_or_none()
    if activity is None:
        raise HTTPException(status_code=404, detail="Activity not found")
    await db.delete(activity)
    await db.commit()
    return {"message": "Activity deleted"}


# ─── Schedules ────────────────────────────────────────────────────────────────

@router.get("/schedules", response_model=list[ScheduleResponse])
async def list_schedules(
    skip: int = 0,
    limit: int = 50,
    turma_id: Optional[uuid.UUID] = None,
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Schedule).where(Schedule.school_id == school_id)
    if turma_id:
        query = query.where(Schedule.turma_id == turma_id)
    if school_year_id:
        query = query.where(Schedule.school_year_id == school_year_id)
    result = await db.execute(query.offset(skip).limit(limit))
    schedules = result.scalars().all()

    # Enrich with turma names and school year labels
    if schedules:
        turma_ids = list({s.turma_id for s in schedules})
        sy_ids = list({s.school_year_id for s in schedules})
        turma_res = await db.execute(
            select(Turma.id, Turma.name).where(Turma.id.in_(turma_ids))
        )
        turma_map = {row[0]: row[1] for row in turma_res.all()}
        sy_res = await db.execute(
            select(SchoolYear.id, SchoolYear.year_label).where(SchoolYear.id.in_(sy_ids))
        )
        sy_map = {row[0]: row[1] for row in sy_res.all()}

        enriched = []
        for s in schedules:
            resp = ScheduleResponse.model_validate(s)
            resp.turma_name = turma_map.get(s.turma_id)
            resp.school_year_label = sy_map.get(s.school_year_id)
            enriched.append(resp)
        return enriched

    return schedules


@router.post("/schedules", response_model=ScheduleResponse, status_code=status.HTTP_201_CREATED)
async def create_schedule(
    body: ScheduleCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    schedule = Schedule(school_id=school_id, **body.model_dump())
    db.add(schedule)
    await db.commit()
    await db.refresh(schedule)
    await db.refresh(schedule, attribute_names=["slots", "teacher_links"])
    return schedule


@router.get("/schedules/{schedule_id}", response_model=ScheduleResponse)
async def get_schedule(
    schedule_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    schedule = result.scalar_one_or_none()
    if schedule is None:
        raise HTTPException(status_code=404, detail="Schedule not found")
    return schedule


@router.patch("/schedules/{schedule_id}", response_model=ScheduleResponse)
async def update_schedule(
    schedule_id: uuid.UUID,
    body: ScheduleUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    schedule = result.scalar_one_or_none()
    if schedule is None:
        raise HTTPException(status_code=404, detail="Schedule not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(schedule, field, value)
    await db.commit()
    await db.refresh(schedule)
    return schedule


@router.delete("/schedules/{schedule_id}")
async def delete_schedule(
    schedule_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    schedule = result.scalar_one_or_none()
    if schedule is None:
        raise HTTPException(status_code=404, detail="Schedule not found")
    await db.delete(schedule)
    await db.commit()
    return {"message": "Schedule deleted"}


# Schedule slots
@router.get("/schedules/{schedule_id}/slots", response_model=list[ScheduleSlotResponse])
async def list_schedule_slots(
    schedule_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(ScheduleSlot).where(
            ScheduleSlot.schedule_id == schedule_id, ScheduleSlot.school_id == school_id
        ).order_by(ScheduleSlot.day_of_week, ScheduleSlot.slot_time)
    )
    return result.scalars().all()


@router.post("/schedules/{schedule_id}/slots", response_model=ScheduleSlotResponse, status_code=status.HTTP_201_CREATED)
async def add_schedule_slot(
    schedule_id: uuid.UUID,
    body: ScheduleSlotCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Verify schedule
    sched_result = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    if sched_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Schedule not found")

    slot = ScheduleSlot(
        school_id=school_id,
        schedule_id=schedule_id,
        **body.model_dump(),
    )
    db.add(slot)
    await db.commit()
    await db.refresh(slot)
    return slot


@router.delete("/schedules/{schedule_id}/slots/{slot_id}")
async def delete_schedule_slot(
    schedule_id: uuid.UUID,
    slot_id: int,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ScheduleSlot).where(
            ScheduleSlot.id == slot_id,
            ScheduleSlot.schedule_id == schedule_id,
            ScheduleSlot.school_id == school_id,
        )
    )
    slot = result.scalar_one_or_none()
    if slot is None:
        raise HTTPException(status_code=404, detail="Slot not found")
    await db.delete(slot)
    await db.commit()
    return {"message": "Slot removed"}


# Schedule teachers
@router.post("/schedules/{schedule_id}/teachers", response_model=ScheduleTeacherResponse, status_code=status.HTTP_201_CREATED)
async def assign_teacher_to_schedule(
    schedule_id: uuid.UUID,
    body: ScheduleTeacherAssign,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Verify schedule
    sched_result = await db.execute(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.school_id == school_id)
    )
    if sched_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Schedule not found")

    # Check not already assigned
    existing = await db.execute(
        select(ScheduleTeacher).where(
            ScheduleTeacher.schedule_id == schedule_id,
            ScheduleTeacher.employee_id == body.employee_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Teacher already assigned to this schedule")

    st = ScheduleTeacher(
        schedule_id=schedule_id,
        employee_id=body.employee_id,
        school_id=school_id,
    )
    db.add(st)
    await db.commit()
    return ScheduleTeacherResponse(schedule_id=schedule_id, employee_id=body.employee_id)


@router.delete("/schedules/{schedule_id}/teachers/{employee_id}")
async def unassign_teacher_from_schedule(
    schedule_id: uuid.UUID,
    employee_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ScheduleTeacher).where(
            ScheduleTeacher.schedule_id == schedule_id,
            ScheduleTeacher.employee_id == employee_id,
            ScheduleTeacher.school_id == school_id,
        )
    )
    st = result.scalar_one_or_none()
    if st is None:
        raise HTTPException(status_code=404, detail="Teacher assignment not found")
    await db.delete(st)
    await db.commit()
    return {"message": "Teacher unassigned from schedule"}


# ─── Enrollments ──────────────────────────────────────────────────────────────

@router.get("/enrollments", response_model=list[EnrollmentResponse])
async def list_enrollments(
    skip: int = 0,
    limit: int = 50,
    school_year_id: Optional[uuid.UUID] = None,
    turma_id: Optional[uuid.UUID] = None,
    child_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Enrollment).where(Enrollment.school_id == school_id)
    if school_year_id:
        query = query.where(Enrollment.school_year_id == school_year_id)
    if child_id:
        query = query.where(Enrollment.child_id == child_id)
    if turma_id:
        query = query.join(Schedule, Schedule.id == Enrollment.schedule_id).where(
            Schedule.turma_id == turma_id
        )
    result = await db.execute(query.offset(skip).limit(limit))
    enrollments = result.scalars().all()

    if not enrollments:
        return []

    # Enrich: child names, turma names, school year labels
    from app.models.person import Child
    child_ids = list({e.child_id for e in enrollments})
    schedule_ids = list({e.schedule_id for e in enrollments})

    child_res = await db.execute(
        select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids))
    )
    child_map = {row[0]: f"{row[1]} {row[2]}" for row in child_res.all()}

    sched_res = await db.execute(
        select(Schedule.id, Schedule.turma_id, Schedule.school_year_id)
        .where(Schedule.id.in_(schedule_ids))
    )
    sched_rows = sched_res.all()
    sched_turma = {row[0]: row[1] for row in sched_rows}
    sched_year = {row[0]: row[2] for row in sched_rows}

    turma_ids = list({v for v in sched_turma.values() if v})
    year_ids = list({v for v in sched_year.values() if v})

    turma_res = await db.execute(select(Turma.id, Turma.name).where(Turma.id.in_(turma_ids)))
    turma_map = {row[0]: row[1] for row in turma_res.all()}

    year_res = await db.execute(
        select(SchoolYear.id, SchoolYear.year_label).where(SchoolYear.id.in_(year_ids))
    )
    year_map = {row[0]: row[1] for row in year_res.all()}

    output = []
    for e in enrollments:
        data = EnrollmentResponse.model_validate(e)
        data.child_name = child_map.get(e.child_id)
        turma_id = sched_turma.get(e.schedule_id)
        data.turma_name = turma_map.get(turma_id) if turma_id else None
        year_id = sched_year.get(e.schedule_id)
        data.school_year = year_map.get(year_id) if year_id else None
        output.append(data)
    return output


@router.post("/enrollments", response_model=EnrollmentResponse, status_code=status.HTTP_201_CREATED)
async def create_enrollment(
    body: EnrollmentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    enrollment = Enrollment(school_id=school_id, **body.model_dump())
    db.add(enrollment)
    await db.commit()
    await db.refresh(enrollment)
    return enrollment


@router.get("/enrollments/{enrollment_id}", response_model=EnrollmentResponse)
async def get_enrollment(
    enrollment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Enrollment).where(
            Enrollment.id == enrollment_id, Enrollment.school_id == school_id
        )
    )
    enrollment = result.scalar_one_or_none()
    if enrollment is None:
        raise HTTPException(status_code=404, detail="Enrollment not found")
    return enrollment


@router.patch("/enrollments/{enrollment_id}", response_model=EnrollmentResponse)
async def update_enrollment(
    enrollment_id: uuid.UUID,
    body: EnrollmentUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Enrollment).where(
            Enrollment.id == enrollment_id, Enrollment.school_id == school_id
        )
    )
    enrollment = result.scalar_one_or_none()
    if enrollment is None:
        raise HTTPException(status_code=404, detail="Enrollment not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(enrollment, field, value)
    await db.commit()
    await db.refresh(enrollment)
    return enrollment


@router.delete("/enrollments/{enrollment_id}")
async def delete_enrollment(
    enrollment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Enrollment).where(
            Enrollment.id == enrollment_id, Enrollment.school_id == school_id
        )
    )
    enrollment = result.scalar_one_or_none()
    if enrollment is None:
        raise HTTPException(status_code=404, detail="Enrollment not found")
    await db.delete(enrollment)
    await db.commit()
    return {"message": "Enrollment deleted"}
