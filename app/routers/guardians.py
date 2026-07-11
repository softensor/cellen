import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher
from app.models.person import Child, ChildGuardian, Guardian
from app.schemas.guardian import (
    ChildGuardianLink, ChildGuardianResponse, GuardianCreate, GuardianResponse, GuardianUpdate
)

router = APIRouter(prefix="/guardians", tags=["Guardians"])


@router.get("", response_model=list[GuardianResponse])
async def list_guardians(
    skip: int = 0,
    limit: int = 50,
    search: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Guardian).where(Guardian.school_id == school_id)
    if search:
        query = query.where(
            or_(
                Guardian.first_name.ilike(f"%{search}%"),
                Guardian.last_name.ilike(f"%{search}%"),
                Guardian.middle_name.ilike(f"%{search}%"),
            )
        )
    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=GuardianResponse, status_code=status.HTTP_201_CREATED)
async def create_guardian(
    body: GuardianCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    guardian = Guardian(school_id=school_id, **body.model_dump())
    db.add(guardian)
    await db.commit()
    await db.refresh(guardian)
    return guardian


@router.get("/{guardian_id}", response_model=GuardianResponse)
async def get_guardian(
    guardian_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")
    return guardian


@router.patch("/{guardian_id}", response_model=GuardianResponse)
async def update_guardian(
    guardian_id: uuid.UUID,
    body: GuardianUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(guardian, field, value)

    await db.commit()
    await db.refresh(guardian)
    return guardian


@router.delete("/{guardian_id}")
async def delete_guardian(
    guardian_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    await db.delete(guardian)
    await db.commit()
    return {"message": "Guardian deleted"}


@router.post("/{guardian_id}/children", response_model=ChildGuardianResponse, status_code=status.HTTP_201_CREATED)
async def link_guardian_to_child(
    guardian_id: uuid.UUID,
    body: ChildGuardianLink,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Verify guardian
    g_result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    if g_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    # Verify child
    c_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if c_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    # Check not already linked
    existing = await db.execute(
        select(ChildGuardian).where(
            ChildGuardian.child_id == body.child_id,
            ChildGuardian.guardian_id == guardian_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Guardian already linked to this child")

    link = ChildGuardian(
        school_id=school_id,
        child_id=body.child_id,
        guardian_id=guardian_id,
        relationship_type=body.relationship_type,
        is_primary_contact=body.is_primary_contact,
    )
    db.add(link)
    await db.commit()
    await db.refresh(link)
    return link


@router.delete("/{guardian_id}/children/{child_id}")
async def unlink_guardian_from_child(
    guardian_id: uuid.UUID,
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ChildGuardian).where(
            ChildGuardian.guardian_id == guardian_id,
            ChildGuardian.child_id == child_id,
            ChildGuardian.school_id == school_id,
        )
    )
    link = result.scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=404, detail="Link not found")

    await db.delete(link)
    await db.commit()
    return {"message": "Guardian unlinked from child"}
