import uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher

router = APIRouter(prefix="/immunizations", tags=["Immunizations"])


class ImmunizationCreate(BaseModel):
    child_id: uuid.UUID
    vaccine_name: str
    administered_at: Optional[date] = None
    due_date: Optional[date] = None
    administered_by: Optional[str] = None
    dose_number: Optional[int] = None
    notes: Optional[str] = None


class ImmunizationUpdate(BaseModel):
    vaccine_name: Optional[str] = None
    administered_at: Optional[date] = None
    due_date: Optional[date] = None
    administered_by: Optional[str] = None
    dose_number: Optional[int] = None
    notes: Optional[str] = None


class ImmunizationResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    vaccine_name: str
    administered_at: Optional[date] = None
    due_date: Optional[date] = None
    administered_by: Optional[str] = None
    dose_number: Optional[int] = None
    notes: Optional[str] = None
    created_at: Optional[datetime] = None
    child_name: Optional[str] = None


@router.get("", response_model=list[ImmunizationResponse])
async def list_immunizations(
    child_id: Optional[uuid.UUID] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.immunization import Immunization
    from app.models.person import ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(Immunization).where(Immunization.school_id == school_id)

    if role not in ("school_admin", "platform_admin", "teacher"):
        # Parents: only see immunizations for their children
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            return []
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        allowed_ids = [row[0] for row in child_ids_result.all()]
        if not allowed_ids:
            return []
        query = query.where(Immunization.child_id.in_(allowed_ids))

    if child_id:
        query = query.where(Immunization.child_id == child_id)

    result = await db.execute(
        query.order_by(Immunization.due_date.asc().nullslast(), Immunization.administered_at.desc()).offset(skip).limit(limit)
    )
    immunizations = result.scalars().all()

    # Bulk fetch child names
    child_ids = list({i.child_id for i in immunizations})
    child_names: dict = {}
    if child_ids:
        from app.models.person import Child
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name)
            .where(Child.id.in_(child_ids))
        )
        child_names = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    return [
        {**i.__dict__, "child_name": child_names.get(i.child_id)}
        for i in immunizations
    ]


@router.post("", response_model=ImmunizationResponse, status_code=status.HTTP_201_CREATED)
async def create_immunization(
    body: ImmunizationCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    from app.models.immunization import Immunization

    immunization = Immunization(
        school_id=school_id,
        **body.model_dump(),
    )
    db.add(immunization)
    await db.commit()
    await db.refresh(immunization)
    return immunization


@router.get("/child/{child_id}", response_model=list[ImmunizationResponse])
async def get_child_immunizations(
    child_id: uuid.UUID,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.immunization import Immunization

    result = await db.execute(
        select(Immunization).where(
            Immunization.school_id == school_id,
            Immunization.child_id == child_id,
        ).order_by(Immunization.due_date.asc().nullslast(), Immunization.administered_at.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.patch("/{immunization_id}", response_model=ImmunizationResponse)
async def update_immunization(
    immunization_id: uuid.UUID,
    body: ImmunizationUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    from app.models.immunization import Immunization

    result = await db.execute(
        select(Immunization).where(
            Immunization.id == immunization_id,
            Immunization.school_id == school_id,
        )
    )
    immunization = result.scalar_one_or_none()
    if immunization is None:
        raise HTTPException(status_code=404, detail="Immunization not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(immunization, field, value)
    await db.commit()
    await db.refresh(immunization)
    return immunization


@router.delete("/{immunization_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_immunization(
    immunization_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.immunization import Immunization

    result = await db.execute(
        select(Immunization).where(
            Immunization.id == immunization_id,
            Immunization.school_id == school_id,
        )
    )
    immunization = result.scalar_one_or_none()
    if immunization is None:
        raise HTTPException(status_code=404, detail="Immunization not found")
    await db.delete(immunization)
    await db.commit()
