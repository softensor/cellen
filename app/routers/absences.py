import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher
from app.models.absence import Absence
from app.schemas.absence import AbsenceCreate, AbsenceResponse, AbsenceSummary, AbsenceUpdate

router = APIRouter(prefix="/absences", tags=["Absences"])


@router.get("", response_model=list[AbsenceResponse])
async def list_absences(
    skip: int = 0,
    limit: int = 50,
    employee_id: Optional[uuid.UUID] = None,
    school_year_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    justified: Optional[bool] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Absence).where(Absence.school_id == school_id)
    if employee_id:
        query = query.where(Absence.employee_id == employee_id)
    if school_year_id:
        query = query.where(Absence.school_year_id == school_year_id)
    if date_from:
        query = query.where(Absence.absence_date >= date_from)
    if date_to:
        query = query.where(Absence.absence_date <= date_to)
    if justified is not None:
        query = query.where(Absence.justified == justified)
    result = await db.execute(query.order_by(Absence.absence_date.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=AbsenceResponse, status_code=status.HTTP_201_CREATED)
async def create_absence(
    body: AbsenceCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    absence = Absence(school_id=school_id, **body.model_dump())
    db.add(absence)
    await db.commit()
    await db.refresh(absence)
    return absence


@router.get("/summary/{employee_id}", response_model=AbsenceSummary)
async def absence_summary(
    employee_id: uuid.UUID,
    school_year_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Absence).where(
        Absence.school_id == school_id, Absence.employee_id == employee_id
    )
    if school_year_id:
        query = query.where(Absence.school_year_id == school_year_id)
    result = await db.execute(query)
    absences = result.scalars().all()

    total = len(absences)
    justified = sum(1 for a in absences if a.justified)
    unjustified = total - justified
    return AbsenceSummary(
        employee_id=employee_id,
        total=total,
        justified=justified,
        unjustified=unjustified,
    )


@router.get("/{absence_id}", response_model=AbsenceResponse)
async def get_absence(
    absence_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Absence).where(Absence.id == absence_id, Absence.school_id == school_id)
    )
    absence = result.scalar_one_or_none()
    if absence is None:
        raise HTTPException(status_code=404, detail="Absence not found")
    return absence


@router.patch("/{absence_id}", response_model=AbsenceResponse)
async def update_absence(
    absence_id: uuid.UUID,
    body: AbsenceUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Absence).where(Absence.id == absence_id, Absence.school_id == school_id)
    )
    absence = result.scalar_one_or_none()
    if absence is None:
        raise HTTPException(status_code=404, detail="Absence not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(absence, field, value)
    await db.commit()
    await db.refresh(absence)
    return absence


@router.delete("/{absence_id}")
async def delete_absence(
    absence_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Absence).where(Absence.id == absence_id, Absence.school_id == school_id)
    )
    absence = result.scalar_one_or_none()
    if absence is None:
        raise HTTPException(status_code=404, detail="Absence not found")
    await db.delete(absence)
    await db.commit()
    return {"message": "Absence deleted"}
