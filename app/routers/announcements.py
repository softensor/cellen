import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher

router = APIRouter(prefix="/announcements", tags=["Announcements"])


class AnnouncementCreate(BaseModel):
    title: str
    body: str
    attachment_url: Optional[str] = None
    attachment_name: Optional[str] = None
    target: str = "all"
    pinned: bool = False
    published_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None


class AnnouncementUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    attachment_url: Optional[str] = None
    attachment_name: Optional[str] = None
    target: Optional[str] = None
    pinned: Optional[bool] = None
    published_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None


class AnnouncementResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    created_by: uuid.UUID
    title: str
    body: str
    attachment_url: Optional[str] = None
    attachment_name: Optional[str] = None
    target: str
    pinned: bool
    published_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    created_by_name: Optional[str] = None


@router.get("", response_model=list[AnnouncementResponse])
async def list_announcements(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import Announcement
    from app.models.employee import Employee

    role = getattr(current_user, "_role", "parent")
    query = select(Announcement).where(Announcement.school_id == school_id)

    # Filter by target based on role
    if role not in ("school_admin", "platform_admin"):
        if role == "parent":
            query = query.where(Announcement.target.in_(["all", "parents"]))
        elif role == "teacher":
            query = query.where(Announcement.target.in_(["all", "teachers", "staff"]))
        else:
            query = query.where(Announcement.target.in_(["all", "staff"]))

    result = await db.execute(
        query.order_by(Announcement.pinned.desc(), Announcement.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    announcements = result.scalars().all()

    # Bulk fetch creator names
    creator_ids = [a.created_by for a in announcements]
    employee_names: dict = {}
    if creator_ids:
        emp_result = await db.execute(
            select(Employee.id, Employee.first_name, Employee.last_name)
            .where(Employee.id.in_(creator_ids))
        )
        employee_names = {row.id: f"{row.first_name} {row.last_name}" for row in emp_result}

    return [
        {**a.__dict__, "created_by_name": employee_names.get(a.created_by)}
        for a in announcements
    ]


@router.get("/pinned", response_model=list[AnnouncementResponse])
async def get_pinned_announcements(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.modern import Announcement
    from app.models.employee import Employee

    result = await db.execute(
        select(Announcement).where(
            Announcement.school_id == school_id,
            Announcement.pinned == True,
        ).order_by(Announcement.created_at.desc())
    )
    announcements = result.scalars().all()

    creator_ids = [a.created_by for a in announcements]
    employee_names: dict = {}
    if creator_ids:
        emp_result = await db.execute(
            select(Employee.id, Employee.first_name, Employee.last_name)
            .where(Employee.id.in_(creator_ids))
        )
        employee_names = {row.id: f"{row.first_name} {row.last_name}" for row in emp_result}

    return [
        {**a.__dict__, "created_by_name": employee_names.get(a.created_by)}
        for a in announcements
    ]


@router.post("", response_model=AnnouncementResponse, status_code=status.HTTP_201_CREATED)
async def create_announcement(
    body: AnnouncementCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import Announcement

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    announcement = Announcement(
        school_id=school_id,
        created_by=employee_id,
        **body.model_dump(),
    )
    db.add(announcement)
    await db.commit()
    await db.refresh(announcement)
    return announcement


@router.patch("/{announcement_id}", response_model=AnnouncementResponse)
async def update_announcement(
    announcement_id: uuid.UUID,
    body: AnnouncementUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Announcement

    result = await db.execute(
        select(Announcement).where(
            Announcement.id == announcement_id, Announcement.school_id == school_id
        )
    )
    announcement = result.scalar_one_or_none()
    if announcement is None:
        raise HTTPException(status_code=404, detail="Announcement not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(announcement, field, value)
    await db.commit()
    await db.refresh(announcement)
    return announcement


@router.delete("/{announcement_id}")
async def delete_announcement(
    announcement_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import Announcement

    result = await db.execute(
        select(Announcement).where(
            Announcement.id == announcement_id, Announcement.school_id == school_id
        )
    )
    announcement = result.scalar_one_or_none()
    if announcement is None:
        raise HTTPException(status_code=404, detail="Announcement not found")
    await db.delete(announcement)
    await db.commit()
    return {"message": "Announcement deleted"}
