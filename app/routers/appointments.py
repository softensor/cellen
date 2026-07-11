import uuid
from datetime import date, datetime, time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_parent, require_school_admin, require_teacher

router = APIRouter(prefix="/appointments", tags=["Appointments"])


class AppointmentCreate(BaseModel):
    employee_id: uuid.UUID
    child_id: Optional[uuid.UUID] = None
    title: str
    notes: Optional[str] = None
    proposed_date: date
    proposed_time: Optional[time] = None


class AppointmentRespondBody(BaseModel):
    status: str  # confirmed / declined
    confirmed_date: Optional[date] = None
    confirmed_time: Optional[time] = None
    response_notes: Optional[str] = None


class AppointmentResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    requested_by: uuid.UUID
    employee_id: uuid.UUID
    child_id: Optional[uuid.UUID] = None
    title: str
    notes: Optional[str] = None
    proposed_date: date
    proposed_time: Optional[time] = None
    confirmed_date: Optional[date] = None
    confirmed_time: Optional[time] = None
    status: str
    response_notes: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    employee_name: Optional[str] = None
    child_name: Optional[str] = None


@router.get("", response_model=list[AppointmentResponse])
async def list_appointments(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import Appointment
    from app.models.employee import Employee
    from app.models.person import Child

    role = getattr(current_user, "_role", "parent")
    query = select(Appointment).where(Appointment.school_id == school_id)

    if role in ("school_admin", "platform_admin"):
        pass  # see all
    elif role == "teacher":
        employee_id = getattr(current_user, "employee_id", None)
        if employee_id:
            query = query.where(Appointment.employee_id == employee_id)
    else:
        # parent — sees own appointments
        query = query.where(Appointment.requested_by == current_user.id)

    result = await db.execute(
        query.order_by(Appointment.proposed_date.desc()).offset(skip).limit(limit)
    )
    appointments = result.scalars().all()

    # Bulk fetch employee names
    emp_ids = list({a.employee_id for a in appointments})
    employee_names: dict = {}
    if emp_ids:
        emp_result = await db.execute(
            select(Employee.id, Employee.first_name, Employee.last_name)
            .where(Employee.id.in_(emp_ids))
        )
        employee_names = {row.id: f"{row.first_name} {row.last_name}" for row in emp_result}

    # Bulk fetch child names
    child_ids = list({a.child_id for a in appointments if a.child_id is not None})
    child_names: dict = {}
    if child_ids:
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name)
            .where(Child.id.in_(child_ids))
        )
        child_names = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    return [
        {
            **a.__dict__,
            "employee_name": employee_names.get(a.employee_id),
            "child_name": child_names.get(a.child_id) if a.child_id else None,
        }
        for a in appointments
    ]


@router.post("", response_model=AppointmentResponse, status_code=status.HTTP_201_CREATED)
async def create_appointment(
    body: AppointmentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    from app.models.modern import Appointment

    appointment = Appointment(
        school_id=school_id,
        requested_by=current_user.id,
        status="pending",
        **body.model_dump(),
    )
    db.add(appointment)
    await db.commit()
    await db.refresh(appointment)
    return appointment


@router.get("/{appointment_id}", response_model=AppointmentResponse)
async def get_appointment(
    appointment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import Appointment

    result = await db.execute(
        select(Appointment).where(
            Appointment.id == appointment_id, Appointment.school_id == school_id
        )
    )
    appointment = result.scalar_one_or_none()
    if appointment is None:
        raise HTTPException(status_code=404, detail="Appointment not found")

    role = getattr(current_user, "_role", "parent")
    if role not in ("school_admin", "platform_admin", "teacher"):
        if appointment.requested_by != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied")

    return appointment


@router.patch("/{appointment_id}/respond", response_model=AppointmentResponse)
async def respond_to_appointment(
    appointment_id: uuid.UUID,
    body: AppointmentRespondBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import Appointment

    if body.status not in ("confirmed", "declined"):
        raise HTTPException(status_code=400, detail="status must be 'confirmed' or 'declined'")

    result = await db.execute(
        select(Appointment).where(
            Appointment.id == appointment_id, Appointment.school_id == school_id
        )
    )
    appointment = result.scalar_one_or_none()
    if appointment is None:
        raise HTTPException(status_code=404, detail="Appointment not found")

    appointment.status = body.status
    if body.confirmed_date:
        appointment.confirmed_date = body.confirmed_date
    if body.confirmed_time:
        appointment.confirmed_time = body.confirmed_time
    if body.response_notes:
        appointment.response_notes = body.response_notes

    await db.commit()
    await db.refresh(appointment)
    return appointment


@router.patch("/{appointment_id}/cancel", response_model=AppointmentResponse)
async def cancel_appointment(
    appointment_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import Appointment

    result = await db.execute(
        select(Appointment).where(
            Appointment.id == appointment_id, Appointment.school_id == school_id
        )
    )
    appointment = result.scalar_one_or_none()
    if appointment is None:
        raise HTTPException(status_code=404, detail="Appointment not found")

    role = getattr(current_user, "_role", "parent")
    if role not in ("school_admin", "platform_admin"):
        if appointment.requested_by != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied")

    appointment.status = "cancelled"
    await db.commit()
    await db.refresh(appointment)
    return appointment
