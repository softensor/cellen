import uuid
from datetime import date, datetime
from typing import Any, List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_teacher
from app.models.modern import Photo

router = APIRouter(prefix="/photos", tags=["photos"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class PhotoCreate(BaseModel):
    url: str
    caption: Optional[str] = None
    photo_date: Optional[date] = None
    turma_id: Optional[uuid.UUID] = None
    child_ids: Optional[List[uuid.UUID]] = None


class PhotoResponse(BaseModel):
    id: uuid.UUID
    school_id: uuid.UUID
    uploaded_by: uuid.UUID
    turma_id: Optional[uuid.UUID] = None
    child_ids: Optional[Any] = None
    url: str
    caption: Optional[str] = None
    photo_date: date
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[PhotoResponse])
async def list_photos(
    turma_id: Optional[uuid.UUID] = None,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    query = select(Photo).where(Photo.school_id == school_id)
    if turma_id:
        query = query.where(Photo.turma_id == turma_id)
    if from_date:
        query = query.where(Photo.photo_date >= from_date)
    if to_date:
        query = query.where(Photo.photo_date <= to_date)

    result = await db.execute(
        query.order_by(Photo.photo_date.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/", response_model=PhotoResponse, status_code=status.HTTP_201_CREATED)
async def create_photo(
    body: PhotoCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    child_ids_serialized = [str(cid) for cid in body.child_ids] if body.child_ids else None

    photo = Photo(
        school_id=school_id,
        uploaded_by=employee_id,
        url=body.url,
        caption=body.caption,
        photo_date=body.photo_date or date.today(),
        turma_id=body.turma_id,
        child_ids=child_ids_serialized,
    )
    db.add(photo)
    await db.commit()
    await db.refresh(photo)
    return photo


@router.delete("/{photo_id}", status_code=status.HTTP_200_OK)
async def delete_photo(
    photo_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    result = await db.execute(
        select(Photo).where(Photo.id == photo_id, Photo.school_id == school_id)
    )
    photo = result.scalar_one_or_none()
    if photo is None:
        raise HTTPException(status_code=404, detail="Photo not found")

    await db.delete(photo)
    await db.commit()
    return {"message": "Photo deleted"}
