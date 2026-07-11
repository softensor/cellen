import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher, get_current_user
from app.models.caderneta import Caderneta
from app.schemas.caderneta import CadernetaCreate, CadernetaResponse, CadernetaUpdate

router = APIRouter(prefix="/cadernetas", tags=["Caderneta"])


@router.get("", response_model=list[CadernetaResponse])
async def list_cadernetas(
    skip: int = 0,
    limit: int = 50,
    child_id: Optional[uuid.UUID] = None,
    teacher_id: Optional[uuid.UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Caderneta).where(Caderneta.school_id == school_id)
    if child_id:
        query = query.where(Caderneta.child_id == child_id)
    if teacher_id:
        query = query.where(Caderneta.teacher_id == teacher_id)
    if date_from:
        query = query.where(Caderneta.report_date >= date_from)
    if date_to:
        query = query.where(Caderneta.report_date <= date_to)
    result = await db.execute(query.order_by(Caderneta.report_date.desc()).offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=CadernetaResponse, status_code=status.HTTP_201_CREATED)
async def create_caderneta(
    body: CadernetaCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    caderneta = Caderneta(school_id=school_id, **body.model_dump())
    db.add(caderneta)
    await db.commit()
    await db.refresh(caderneta)
    return caderneta


@router.get("/my", response_model=list[CadernetaResponse])
async def get_my_cadernetas(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    result = await db.execute(
        select(Caderneta)
        .where(
            Caderneta.school_id == school_id,
            Caderneta.teacher_id == employee_id,
        )
        .order_by(Caderneta.report_date.desc())
        .offset(skip)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/{caderneta_id}", response_model=CadernetaResponse)
async def get_caderneta(
    caderneta_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Caderneta).where(Caderneta.id == caderneta_id, Caderneta.school_id == school_id)
    )
    caderneta = result.scalar_one_or_none()
    if caderneta is None:
        raise HTTPException(status_code=404, detail="Caderneta not found")
    return caderneta


@router.patch("/{caderneta_id}", response_model=CadernetaResponse)
async def update_caderneta(
    caderneta_id: uuid.UUID,
    body: CadernetaUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Caderneta).where(Caderneta.id == caderneta_id, Caderneta.school_id == school_id)
    )
    caderneta = result.scalar_one_or_none()
    if caderneta is None:
        raise HTTPException(status_code=404, detail="Caderneta not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(caderneta, field, value)
    await db.commit()
    await db.refresh(caderneta)
    return caderneta


@router.delete("/{caderneta_id}")
async def delete_caderneta(
    caderneta_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Caderneta).where(Caderneta.id == caderneta_id, Caderneta.school_id == school_id)
    )
    caderneta = result.scalar_one_or_none()
    if caderneta is None:
        raise HTTPException(status_code=404, detail="Caderneta not found")
    await db.delete(caderneta)
    await db.commit()
    return {"message": "Caderneta deleted"}
