import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher

router = APIRouter(prefix="/documents", tags=["Documents Library"])


class DocumentCreate(BaseModel):
    title: str
    description: Optional[str] = None
    file_url: str
    file_name: str
    file_type: Optional[str] = None
    category: Optional[str] = None
    target: str = "all"
    child_id: Optional[uuid.UUID] = None


class DocumentResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    uploaded_by: uuid.UUID
    title: str
    description: Optional[str] = None
    file_url: str
    file_name: str
    file_type: Optional[str] = None
    category: Optional[str] = None
    target: str
    child_id: Optional[uuid.UUID] = None
    created_at: Optional[datetime] = None


@router.get("", response_model=list[DocumentResponse])
async def list_documents(
    skip: int = 0,
    limit: int = 50,
    child_id: Optional[uuid.UUID] = None,
    category: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import DocumentLibrary

    role = getattr(current_user, "_role", "parent")
    query = select(DocumentLibrary).where(DocumentLibrary.school_id == school_id)

    # Filter by target based on role
    if role not in ("school_admin", "platform_admin"):
        if role == "parent":
            query = query.where(DocumentLibrary.target.in_(["all", "parents", "child_specific"]))
        elif role == "teacher":
            query = query.where(DocumentLibrary.target.in_(["all", "teachers"]))
        else:
            query = query.where(DocumentLibrary.target == "all")

    if child_id:
        query = query.where(DocumentLibrary.child_id == child_id)
    if category:
        query = query.where(DocumentLibrary.category == category)

    result = await db.execute(
        query.order_by(DocumentLibrary.created_at.desc()).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    body: DocumentCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import DocumentLibrary

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    doc = DocumentLibrary(
        school_id=school_id,
        uploaded_by=employee_id,
        **body.model_dump(),
    )
    db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return doc


@router.delete("/{document_id}")
async def delete_document(
    document_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.models.modern import DocumentLibrary

    result = await db.execute(
        select(DocumentLibrary).where(
            DocumentLibrary.id == document_id, DocumentLibrary.school_id == school_id
        )
    )
    doc = result.scalar_one_or_none()
    if doc is None:
        raise HTTPException(status_code=404, detail="Document not found")
    await db.delete(doc)
    await db.commit()
    return {"message": "Document deleted"}
