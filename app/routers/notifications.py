import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id
from app.models.modern import Notification

router = APIRouter(prefix="/notifications", tags=["notifications"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class NotificationResponse(BaseModel):
    id: uuid.UUID
    school_id: uuid.UUID
    user_id: uuid.UUID
    type: str
    title: str
    body: str
    is_read: bool
    related_id: Optional[uuid.UUID] = None
    related_type: Optional[str] = None
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class UnreadCountResponse(BaseModel):
    count: int


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[NotificationResponse])
async def list_notifications(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(Notification)
        .where(
            Notification.school_id == school_id,
            Notification.user_id == current_user.id,
        )
        .order_by(Notification.created_at.desc())
        .limit(50)
    )
    return result.scalars().all()


@router.get("/unread-count", response_model=UnreadCountResponse)
async def unread_count(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(Notification).where(
            Notification.school_id == school_id,
            Notification.user_id == current_user.id,
            Notification.is_read == False,
        )
    )
    notifications = result.scalars().all()
    return UnreadCountResponse(count=len(notifications))


@router.put("/read-all", status_code=status.HTTP_200_OK)
async def mark_all_notifications_read(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(Notification).where(
            Notification.school_id == school_id,
            Notification.user_id == current_user.id,
            Notification.is_read == False,
        )
    )
    notifications = result.scalars().all()
    for n in notifications:
        n.is_read = True

    await db.commit()
    return {"message": f"Marked {len(notifications)} notifications as read"}


@router.put("/{notification_id}/read", status_code=status.HTTP_200_OK)
async def mark_notification_read(
    notification_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.school_id == school_id,
            Notification.user_id == current_user.id,
        )
    )
    notification = result.scalar_one_or_none()
    if notification is None:
        raise HTTPException(status_code=404, detail="Notification not found")

    notification.is_read = True
    await db.commit()
    return {"message": "Notification marked as read"}
