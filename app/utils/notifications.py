import uuid
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.modern import Notification


async def create_notification(
    db: AsyncSession,
    school_id: uuid.UUID,
    user_id: uuid.UUID,
    type: str,
    title: str,
    body: str,
    related_id: Optional[uuid.UUID] = None,
    related_type: Optional[str] = None,
) -> Notification:
    notification = Notification(
        school_id=school_id,
        user_id=user_id,
        type=type,
        title=title,
        body=body,
        related_id=related_id,
        related_type=related_type,
    )
    db.add(notification)
    return notification
