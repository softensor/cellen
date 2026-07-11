import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id
from app.models.modern import Message, MessageThread, ThreadParticipant

router = APIRouter(prefix="/messages", tags=["messages"])


# ─── Schemas ──────────────────────────────────────────────────────────────────

class ThreadCreate(BaseModel):
    subject: str
    participant_user_ids: List[uuid.UUID]
    message: str
    thread_type: Optional[str] = "direct"


class MessagePost(BaseModel):
    body: str


class ThreadResponse(BaseModel):
    id: uuid.UUID
    school_id: uuid.UUID
    subject: str
    thread_type: str
    created_by: uuid.UUID
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class MessageResponse(BaseModel):
    id: uuid.UUID
    thread_id: uuid.UUID
    sender_id: uuid.UUID
    body: str
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/threads", response_model=List[ThreadResponse])
async def list_threads(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    # Get threads where current user is a participant
    thread_ids_result = await db.execute(
        select(ThreadParticipant.thread_id).where(
            ThreadParticipant.user_id == current_user.id,
            ThreadParticipant.school_id == school_id,
        )
    )
    thread_ids = [row[0] for row in thread_ids_result.all()]

    if not thread_ids:
        return []

    result = await db.execute(
        select(MessageThread)
        .where(MessageThread.id.in_(thread_ids), MessageThread.school_id == school_id)
        .order_by(MessageThread.created_at.desc())
    )
    return result.scalars().all()


@router.post("/threads", response_model=ThreadResponse, status_code=status.HTTP_201_CREATED)
async def create_thread(
    body: ThreadCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    thread = MessageThread(
        school_id=school_id,
        subject=body.subject,
        thread_type=body.thread_type,
        created_by=current_user.id,
    )
    db.add(thread)
    await db.flush()

    # Add creator as participant
    participant_ids = set(body.participant_user_ids)
    participant_ids.add(current_user.id)

    for uid in participant_ids:
        participant = ThreadParticipant(
            thread_id=thread.id,
            user_id=uid,
            school_id=school_id,
        )
        db.add(participant)

    # Create first message
    first_message = Message(
        school_id=school_id,
        thread_id=thread.id,
        sender_id=current_user.id,
        body=body.message,
    )
    db.add(first_message)

    await db.commit()
    await db.refresh(thread)
    return thread


@router.get("/threads/{thread_id}/messages", response_model=List[MessageResponse])
async def list_thread_messages(
    thread_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    # Verify thread exists and belongs to school
    thread_result = await db.execute(
        select(MessageThread).where(
            MessageThread.id == thread_id,
            MessageThread.school_id == school_id,
        )
    )
    if thread_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    # Verify user is a participant
    participant_result = await db.execute(
        select(ThreadParticipant).where(
            ThreadParticipant.thread_id == thread_id,
            ThreadParticipant.user_id == current_user.id,
        )
    )
    if participant_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=403, detail="Access denied: not a participant in this thread")

    result = await db.execute(
        select(Message)
        .where(Message.thread_id == thread_id, Message.school_id == school_id)
        .order_by(Message.created_at.asc())
    )
    return result.scalars().all()


@router.post("/threads/{thread_id}/messages", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def post_message(
    thread_id: uuid.UUID,
    body: MessagePost,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    thread_result = await db.execute(
        select(MessageThread).where(
            MessageThread.id == thread_id,
            MessageThread.school_id == school_id,
        )
    )
    if thread_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Thread not found")

    participant_result = await db.execute(
        select(ThreadParticipant).where(
            ThreadParticipant.thread_id == thread_id,
            ThreadParticipant.user_id == current_user.id,
        )
    )
    if participant_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=403, detail="Access denied: not a participant in this thread")

    message = Message(
        school_id=school_id,
        thread_id=thread_id,
        sender_id=current_user.id,
        body=body.body,
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    return message


@router.put("/threads/{thread_id}/read", status_code=status.HTTP_200_OK)
async def mark_thread_read(
    thread_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    participant_result = await db.execute(
        select(ThreadParticipant).where(
            ThreadParticipant.thread_id == thread_id,
            ThreadParticipant.user_id == current_user.id,
        )
    )
    participant = participant_result.scalar_one_or_none()
    if participant is None:
        raise HTTPException(status_code=403, detail="Access denied: not a participant in this thread")

    participant.last_read_at = datetime.utcnow()
    await db.commit()
    return {"message": "Thread marked as read"}
