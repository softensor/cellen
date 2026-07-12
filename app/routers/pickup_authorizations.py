import uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, func, select
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_parent
from app.models.base import Base

router = APIRouter(prefix="/pickup-authorizations", tags=["Pickup Authorizations"])


# ─── Models (inline) ─────────────────────────────────────────────────────────

class PickupAuthorization(Base):
    __tablename__ = "pickup_authorizations"
    __table_args__ = (
        Index("ix_pickup_authorizations_school_id", "school_id"),
        Index("ix_pickup_authorizations_child_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    child_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    authorized_name: Mapped[str] = mapped_column(String(255), nullable=False)
    relationship: Mapped[Optional[str]] = mapped_column(String(100))
    phone: Mapped[Optional[str]] = mapped_column(String(50))
    id_card_number: Mapped[Optional[str]] = mapped_column(String(100))
    notes: Mapped[Optional[str]] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class MealOrder(Base):
    __tablename__ = "meal_orders"
    __table_args__ = (
        UniqueConstraint("school_id", "child_id", "order_date", "meal_type", name="uq_meal_order_child_date_type"),
        Index("ix_meal_orders_school_id", "school_id"),
        Index("ix_meal_orders_order_date", "order_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False)
    child_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    order_date: Mapped[date] = mapped_column(Date, nullable=False)
    meal_type: Mapped[str] = mapped_column(String(50), default="lunch", nullable=False)
    ordered: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── Schemas ─────────────────────────────────────────────────────────────────

class PickupAuthCreate(BaseModel):
    child_id: uuid.UUID
    authorized_name: str
    relationship: Optional[str] = None
    phone: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None


class PickupAuthUpdate(BaseModel):
    authorized_name: Optional[str] = None
    relationship: Optional[str] = None
    phone: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None
    is_active: Optional[bool] = None


class PickupAuthOut(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    authorized_name: str
    relationship: Optional[str] = None
    phone: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None
    is_active: bool
    created_at: Optional[datetime] = None
    child_name: Optional[str] = None


class MealOrderUpsert(BaseModel):
    child_id: uuid.UUID
    order_date: date
    meal_type: str = "lunch"
    ordered: bool


class MealOrderOut(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    child_id: uuid.UUID
    order_date: date
    meal_type: str
    ordered: bool
    child_name: Optional[str] = None


class DailyMealCount(BaseModel):
    order_date: date
    meal_type: str
    total: int


# ─── Pickup authorization endpoints ──────────────────────────────────────────

@router.get("", response_model=list[PickupAuthOut])
async def list_pickup_authorizations(
    child_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.person import Child, ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(PickupAuthorization).where(PickupAuthorization.school_id == school_id)

    if role not in ("school_admin", "platform_admin", "teacher", "staff"):
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            return []
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        allowed = [r[0] for r in child_ids_result.all()]
        if not allowed:
            return []
        query = query.where(PickupAuthorization.child_id.in_(allowed))

    if child_id:
        query = query.where(PickupAuthorization.child_id == child_id)

    result = await db.execute(query.order_by(PickupAuthorization.child_id, PickupAuthorization.authorized_name))
    auths = result.scalars().all()

    # Bulk fetch child names
    child_ids = list({a.child_id for a in auths})
    child_names: dict = {}
    if child_ids:
        from app.models.person import Child
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids))
        )
        child_names = {r.id: f"{r.first_name} {r.last_name}" for r in child_result}

    return [{**a.__dict__, "child_name": child_names.get(a.child_id)} for a in auths]


@router.post("", response_model=PickupAuthOut, status_code=status.HTTP_201_CREATED)
async def create_pickup_authorization(
    body: PickupAuthCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.person import Child
    child_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    auth = PickupAuthorization(school_id=school_id, **body.model_dump())
    db.add(auth)
    await db.commit()
    await db.refresh(auth)

    from app.models.person import Child
    child_result2 = await db.execute(select(Child).where(Child.id == body.child_id))
    child = child_result2.scalar_one_or_none()
    child_name = f"{child.first_name} {child.last_name}" if child else None
    return {**auth.__dict__, "child_name": child_name}


@router.patch("/{auth_id}", response_model=PickupAuthOut)
async def update_pickup_authorization(
    auth_id: uuid.UUID,
    body: PickupAuthUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    result = await db.execute(
        select(PickupAuthorization).where(
            PickupAuthorization.id == auth_id,
            PickupAuthorization.school_id == school_id,
        )
    )
    auth = result.scalar_one_or_none()
    if auth is None:
        raise HTTPException(status_code=404, detail="Not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(auth, field, value)
    await db.commit()
    await db.refresh(auth)
    return {**auth.__dict__, "child_name": None}


@router.delete("/{auth_id}", status_code=status.HTTP_200_OK)
async def delete_pickup_authorization(
    auth_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    result = await db.execute(
        select(PickupAuthorization).where(
            PickupAuthorization.id == auth_id,
            PickupAuthorization.school_id == school_id,
        )
    )
    auth = result.scalar_one_or_none()
    if auth is None:
        raise HTTPException(status_code=404, detail="Not found")
    await db.delete(auth)
    await db.commit()
    return {"message": "Deleted"}


# ─── Meal order endpoints ─────────────────────────────────────────────────────

@router.get("/meal-orders", response_model=list[MealOrderOut])
async def list_meal_orders(
    order_date: Optional[date] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    child_id: Optional[uuid.UUID] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.person import ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(MealOrder).where(MealOrder.school_id == school_id, MealOrder.ordered == True)

    if role not in ("school_admin", "platform_admin", "teacher", "staff"):
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            return []
        child_ids_result = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        allowed = [r[0] for r in child_ids_result.all()]
        query = query.where(MealOrder.child_id.in_(allowed))

    if child_id:
        query = query.where(MealOrder.child_id == child_id)
    if order_date:
        query = query.where(MealOrder.order_date == order_date)
    if date_from:
        query = query.where(MealOrder.order_date >= date_from)
    if date_to:
        query = query.where(MealOrder.order_date <= date_to)

    result = await db.execute(query.order_by(MealOrder.order_date.asc()))
    orders = result.scalars().all()

    child_ids = list({o.child_id for o in orders})
    child_names: dict = {}
    if child_ids:
        from app.models.person import Child
        cr = await db.execute(
            select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids))
        )
        child_names = {r.id: f"{r.first_name} {r.last_name}" for r in cr}

    return [{**o.__dict__, "child_name": child_names.get(o.child_id)} for o in orders]


@router.post("/meal-orders", response_model=MealOrderOut)
async def upsert_meal_order(
    body: MealOrderUpsert,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    existing = await db.execute(
        select(MealOrder).where(
            MealOrder.school_id == school_id,
            MealOrder.child_id == body.child_id,
            MealOrder.order_date == body.order_date,
            MealOrder.meal_type == body.meal_type,
        )
    )
    order = existing.scalar_one_or_none()
    if order:
        order.ordered = body.ordered
    else:
        order = MealOrder(school_id=school_id, **body.model_dump())
        db.add(order)
    await db.commit()
    await db.refresh(order)
    return {**order.__dict__, "child_name": None}


@router.get("/meal-orders/daily-counts", response_model=list[DailyMealCount])
async def get_daily_meal_counts(
    date_from: date,
    date_to: date,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from sqlalchemy import func as sqlfunc
    result = await db.execute(
        select(
            MealOrder.order_date,
            MealOrder.meal_type,
            sqlfunc.count(MealOrder.id).label("total"),
        )
        .where(
            MealOrder.school_id == school_id,
            MealOrder.ordered == True,
            MealOrder.order_date >= date_from,
            MealOrder.order_date <= date_to,
        )
        .group_by(MealOrder.order_date, MealOrder.meal_type)
        .order_by(MealOrder.order_date)
    )
    return [
        DailyMealCount(order_date=row.order_date, meal_type=row.meal_type, total=row.total)
        for row in result.all()
    ]
