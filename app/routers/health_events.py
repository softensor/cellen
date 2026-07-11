import uuid
from datetime import date, datetime, time
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_teacher

router = APIRouter(prefix="/health-events", tags=["Health Events"])


class HealthEventCreate(BaseModel):
    child_id: uuid.UUID
    event_date: date
    event_time: Optional[time] = None
    event_type: str
    description: str
    temperature: Optional[Decimal] = None
    medication_given: Optional[str] = None
    parent_notified: bool = False
    parent_notified_at: Optional[datetime] = None
    action_taken: Optional[str] = None


class HealthEventUpdate(BaseModel):
    event_type: Optional[str] = None
    description: Optional[str] = None
    temperature: Optional[Decimal] = None
    medication_given: Optional[str] = None
    parent_notified: Optional[bool] = None
    parent_notified_at: Optional[datetime] = None
    action_taken: Optional[str] = None


class HealthEventResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    recorded_by: uuid.UUID
    event_date: date
    event_time: Optional[time] = None
    event_type: str
    description: str
    temperature: Optional[Decimal] = None
    medication_given: Optional[str] = None
    parent_notified: bool
    parent_notified_at: Optional[datetime] = None
    action_taken: Optional[str] = None
    created_at: Optional[datetime] = None
    child_name: Optional[str] = None


@router.get("", response_model=list[HealthEventResponse])
async def list_health_events(
    child_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import HealthEvent
    from app.models.person import ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(HealthEvent).where(HealthEvent.school_id == school_id)

    if role not in ("school_admin", "platform_admin", "teacher"):
        # Parents: only see health events for their children
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            return []
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        allowed_ids = [row[0] for row in child_ids_result.all()]
        if not allowed_ids:
            return []
        query = query.where(HealthEvent.child_id.in_(allowed_ids))

    if child_id:
        query = query.where(HealthEvent.child_id == child_id)
    if date_from:
        query = query.where(HealthEvent.event_date >= date_from)
    if date_to:
        query = query.where(HealthEvent.event_date <= date_to)

    result = await db.execute(
        query.order_by(HealthEvent.event_date.desc()).offset(skip).limit(limit)
    )
    events = result.scalars().all()

    # Bulk fetch child names
    child_ids = list({e.child_id for e in events})
    child_names: dict = {}
    if child_ids:
        from app.models.person import Child
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name)
            .where(Child.id.in_(child_ids))
        )
        child_names = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    return [
        {**e.__dict__, "child_name": child_names.get(e.child_id)}
        for e in events
    ]


@router.post("", response_model=HealthEventResponse, status_code=status.HTTP_201_CREATED)
async def create_health_event(
    body: HealthEventCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import HealthEvent

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    event = HealthEvent(
        school_id=school_id,
        recorded_by=employee_id,
        **body.model_dump(),
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return event


@router.get("/child/{child_id}", response_model=list[HealthEventResponse])
async def get_child_health_events(
    child_id: uuid.UUID,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.modern import HealthEvent

    result = await db.execute(
        select(HealthEvent).where(
            HealthEvent.school_id == school_id,
            HealthEvent.child_id == child_id,
        ).order_by(HealthEvent.event_date.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.patch("/{event_id}", response_model=HealthEventResponse)
async def update_health_event(
    event_id: uuid.UUID,
    body: HealthEventUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    from app.models.modern import HealthEvent

    result = await db.execute(
        select(HealthEvent).where(HealthEvent.id == event_id, HealthEvent.school_id == school_id)
    )
    event = result.scalar_one_or_none()
    if event is None:
        raise HTTPException(status_code=404, detail="Health event not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(event, field, value)
    await db.commit()
    await db.refresh(event)
    return event
