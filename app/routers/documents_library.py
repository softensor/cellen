import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher
from app.services.storage import save_upload

router = APIRouter(prefix="/documents", tags=["Documents Library"])

ALLOWED_DOCUMENT_TYPES = {"application/pdf", "application/msword",
                           "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                           "image/jpeg", "image/png"}


class DocumentResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    uploaded_by: uuid.UUID
    name: str
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

    if role not in ("school_admin", "platform_admin"):
        if role == "parent":
            query = query.where(DocumentLibrary.target.in_(["all", "parents", "child_specific"]))
        elif role in ("teacher", "staff"):
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
    docs = result.scalars().all()
    return [{
        **d.__dict__,
        "name": getattr(d, "name", getattr(d, "title", "")),
    } for d in docs]


@router.post("", response_model=DocumentResponse, status_code=status.HTTP_201_CREATED)
async def upload_document(
    file: UploadFile = File(...),
    name: str = Form(...),
    description: Optional[str] = Form(None),
    category: Optional[str] = Form(None),
    target: str = Form("all"),
    child_id: Optional[uuid.UUID] = Form(None),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import DocumentLibrary

    # Validate file type for documents
    content_type = file.content_type or ""
    if content_type not in ALLOWED_DOCUMENT_TYPES and content_type != "application/octet-stream":
        raise HTTPException(
            status_code=415,
            detail=f"File type '{content_type}' not allowed for documents. Use PDF, Word, or image files.",
        )
    # Pass content type override for storage validation if it's octet-stream
    ct_override = "application/pdf" if content_type == "application/octet-stream" else None

    file_url = await save_upload(file, "documents", school_id, content_type_override=ct_override)

    doc = DocumentLibrary(
        school_id=school_id,
        uploaded_by=current_user.id,
        title=name,
        description=description,
        file_url=file_url,
        file_name=file.filename or name,
        file_type=Path(file.filename).suffix.lstrip('.').lower() if file.filename else None,
        category=category,
        target=target,
        child_id=child_id,
    )
    db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return {**doc.__dict__, "name": doc.title}


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
