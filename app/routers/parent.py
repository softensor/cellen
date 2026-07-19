import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_parent
from app.models.caderneta import Caderneta
from app.models.finance import Invoice
from app.models.person import Child, ChildGuardian
from app.schemas.caderneta import CadernetaResponse
from app.schemas.child import ChildResponse
from app.schemas.finance import InvoiceResponse
from app.services.finance import get_invoice_amount_paid

router = APIRouter(prefix="/parent", tags=["Parent"])


def _require_parent_guardian_id(current_user) -> uuid.UUID:
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated guardian record")
    return guardian_id


@router.get("/children", response_model=list[ChildResponse])
async def parent_get_children(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    role = getattr(current_user, "_role", "")

    if role == "parent":
        guardian_id = _require_parent_guardian_id(current_user)
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

    # school_admin / platform_admin — return all active children
    result = await db.execute(
        select(Child).where(Child.school_id == school_id, Child.is_active)
    )
    return result.scalars().all()


@router.get("/cadernetas", response_model=list[CadernetaResponse])
async def parent_get_cadernetas(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    role = getattr(current_user, "_role", "")

    if role == "parent":
        guardian_id = _require_parent_guardian_id(current_user)
        # Get child_ids belonging to this guardian
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id)
            .join(Child, Child.id == ChildGuardian.child_id)
            .where(
                ChildGuardian.guardian_id == guardian_id,
                Child.school_id == school_id,
                Child.is_active,
            )
        )
        child_ids = [row[0] for row in child_ids_result.all()]

        if not child_ids:
            return []

        result = await db.execute(
            select(Caderneta)
            .where(
                Caderneta.school_id == school_id,
                Caderneta.child_id.in_(child_ids),
            )
            .order_by(Caderneta.report_date.desc())
            .offset(skip)
            .limit(limit)
        )
        return result.scalars().all()

    # school_admin / platform_admin — return all cadernetas
    result = await db.execute(
        select(Caderneta)
        .where(Caderneta.school_id == school_id)
        .order_by(Caderneta.report_date.desc())
        .offset(skip)
        .limit(limit)
    )
    return result.scalars().all()


@router.get("/invoices", response_model=list[InvoiceResponse])
async def parent_get_invoices(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_parent),
):
    role = getattr(current_user, "_role", "")

    if role == "parent":
        guardian_id = _require_parent_guardian_id(current_user)
        # Get child_ids belonging to this guardian
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id)
            .join(Child, Child.id == ChildGuardian.child_id)
            .where(
                ChildGuardian.guardian_id == guardian_id,
                Child.school_id == school_id,
                Child.is_active,
            )
        )
        child_ids = [row[0] for row in child_ids_result.all()]

        if not child_ids:
            return []

        result = await db.execute(
            select(Invoice)
            .where(
                Invoice.school_id == school_id,
                Invoice.child_id.in_(child_ids),
            )
            .order_by(Invoice.reference_month.desc())
            .offset(skip)
            .limit(limit)
        )
    else:
        # school_admin / platform_admin — return all invoices
        result = await db.execute(
            select(Invoice)
            .where(Invoice.school_id == school_id)
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
