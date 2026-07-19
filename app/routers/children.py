import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher, get_current_user
from app.models.academic import Enrollment, Schedule
from app.models.caderneta import Caderneta
from app.models.finance import Invoice
from app.models.person import Child, ChildGuardian
from app.schemas.caderneta import CadernetaResponse
from app.schemas.child import ChildCreate, ChildResponse, ChildUpdate, ChildBalance
from app.schemas.finance import InvoiceResponse
from app.services.finance import get_outstanding_balance, get_invoice_amount_paid
from app.services.storage import save_upload

router = APIRouter(prefix="/children", tags=["Children"])


@router.get("", response_model=list[ChildResponse])
async def list_children(
    skip: int = 0,
    limit: int = 50,
    turma_id: Optional[uuid.UUID] = None,
    enrollment_status: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Child).where(Child.school_id == school_id, Child.is_active)

    if turma_id or enrollment_status:
        # Filter via enrollments
        enrollment_query = select(Enrollment.child_id).join(
            Schedule, Schedule.id == Enrollment.schedule_id
        ).where(Enrollment.school_id == school_id)
        if turma_id:
            enrollment_query = enrollment_query.where(Schedule.turma_id == turma_id)
        if enrollment_status:
            enrollment_query = enrollment_query.where(Enrollment.status == enrollment_status)
        query = query.where(Child.id.in_(enrollment_query))

    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=ChildResponse, status_code=status.HTTP_201_CREATED)
async def create_child(
    body: ChildCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    child = Child(school_id=school_id, **body.model_dump())
    db.add(child)
    await db.commit()
    await db.refresh(child)
    return child


@router.get("/my", response_model=list[ChildResponse])
async def get_my_children(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    role = getattr(current_user, "_role", "")

    if role == "parent":
        guardian_id = getattr(current_user, "guardian_id", None)
        if guardian_id is None:
            return []
        result = await db.execute(
            select(Child)
            .join(ChildGuardian, ChildGuardian.child_id == Child.id)
            .where(
                ChildGuardian.guardian_id == guardian_id,
                Child.school_id == school_id,
                Child.is_active,
            )
        )
        return result.scalars().all()

    elif role == "teacher":
        result = await db.execute(
            select(Child).where(Child.school_id == school_id, Child.is_active)
        )
        return result.scalars().all()

    elif role in ("school_admin", "platform_admin"):
        result = await db.execute(
            select(Child).where(Child.school_id == school_id, Child.is_active)
        )
        return result.scalars().all()

    raise HTTPException(status_code=403, detail="Access denied")


@router.get("/{child_id}", response_model=ChildResponse)
async def get_child(
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    child = result.scalar_one_or_none()
    if child is None:
        raise HTTPException(status_code=404, detail="Child not found")
    return child


@router.patch("/{child_id}", response_model=ChildResponse)
async def update_child(
    child_id: uuid.UUID,
    body: ChildUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    child = result.scalar_one_or_none()
    if child is None:
        raise HTTPException(status_code=404, detail="Child not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(child, field, value)

    await db.commit()
    await db.refresh(child)
    return child


@router.delete("/{child_id}")
async def soft_delete_child(
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    child = result.scalar_one_or_none()
    if child is None:
        raise HTTPException(status_code=404, detail="Child not found")

    child.is_active = False
    await db.commit()
    return {"message": "Child deactivated"}


@router.post("/{child_id}/photo")
async def upload_child_photo(
    child_id: uuid.UUID,
    file: UploadFile = File(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    child = result.scalar_one_or_none()
    if child is None:
        raise HTTPException(status_code=404, detail="Child not found")

    url = await save_upload(file, "children", child_id)
    child.photo_url = url
    await db.commit()
    return {"photo_url": url}


@router.get("/{child_id}/guardians")
async def get_child_guardians(
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.person import Guardian

    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    result = await db.execute(
        select(Guardian, ChildGuardian)
        .join(ChildGuardian, ChildGuardian.guardian_id == Guardian.id)
        .where(ChildGuardian.child_id == child_id, ChildGuardian.school_id == school_id)
    )
    rows = result.all()
    return [
        {
            "id": str(g.id),
            "school_id": str(g.school_id),
            "first_name": g.first_name,
            "middle_name": g.middle_name,
            "last_name": g.last_name,
            "mobile_first": g.mobile_first,
            "mobile_second": g.mobile_second,
            "email": g.email,
            "profession": g.profession,
            "id_card_number": g.id_card_number,
            "relationship_type": cg.relationship_type,
            "is_primary_contact": cg.is_primary_contact,
        }
        for g, cg in rows
    ]


@router.get("/{child_id}/cadernetas", response_model=list[CadernetaResponse])
async def get_child_cadernetas(
    child_id: uuid.UUID,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    role = getattr(current_user, "_role", "")
    if role not in ("teacher", "school_admin", "platform_admin", "parent"):
        raise HTTPException(status_code=403, detail="Access denied")

    # Verify child belongs to school
    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    result = await db.execute(
        select(Caderneta)
        .where(Caderneta.child_id == child_id, Caderneta.school_id == school_id)
        .order_by(Caderneta.report_date.desc())
        .offset(skip)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/{child_id}/invoices", response_model=list[InvoiceResponse])
async def get_child_invoices(
    child_id: uuid.UUID,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    role = getattr(current_user, "_role", "")
    if role not in ("school_admin", "platform_admin", "parent"):
        raise HTTPException(status_code=403, detail="Access denied")

    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    result = await db.execute(
        select(Invoice)
        .where(Invoice.child_id == child_id, Invoice.school_id == school_id)
        .order_by(Invoice.reference_month.desc())
        .offset(skip)
        .limit(limit)
    )
    invoices = result.scalars().all()

    output = []
    for invoice in invoices:
        amount_paid = await get_invoice_amount_paid(db, invoice.id)
        data = InvoiceResponse.model_validate(invoice)
        data.amount_paid = amount_paid
        data.balance = invoice.gross_total - amount_paid
        output.append(data)
    return output


@router.get("/{child_id}/balance", response_model=ChildBalance)
async def get_child_balance(
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    role = getattr(current_user, "_role", "")
    if role not in ("school_admin", "platform_admin", "parent"):
        raise HTTPException(status_code=403, detail="Access denied")

    child_result = await db.execute(
        select(Child).where(Child.id == child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    balance = await get_outstanding_balance(db, school_id, child_id)
    return ChildBalance(child_id=child_id, outstanding_balance=balance)
