import uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func as sqlfunc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id
from app.models.pickup_auth import MealOrder, PickupAuthorization

router = APIRouter(prefix="/pickup-authorizations", tags=["Pickup Authorizations"])


# ─── Schemas ─────────────────────────────────────────────────────────────────

class PickupAuthCreate(BaseModel):
    child_id: uuid.UUID
    authorized_person_name: str
    relationship: Optional[str] = None
    mobile: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None


class PickupAuthUpdate(BaseModel):
    authorized_person_name: Optional[str] = None
    relationship: Optional[str] = None
    mobile: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None
    is_active: Optional[bool] = None


class PickupAuthOut(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    authorized_person_name: str
    relationship: Optional[str] = None
    mobile: Optional[str] = None
    id_card_number: Optional[str] = None
    notes: Optional[str] = None
    is_active: bool
    created_at: Optional[datetime] = None
    child_name: Optional[str] = None


class MealOrderCreate(BaseModel):
    child_id: uuid.UUID
    order_date: date
    meal_type: str = "lunch"
    quantity: int = 1


class MealOrderOut(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    child_id: uuid.UUID
    order_date: date
    meal_type: str
    quantity: int
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

    result = await db.execute(query.order_by(PickupAuthorization.child_id, PickupAuthorization.authorized_person_name))
    auths = result.scalars().all()

    # Bulk fetch child names
    child_ids_set = list({a.child_id for a in auths})
    child_names: dict = {}
    if child_ids_set:
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids_set))
        )
        child_names = {r.id: f"{r.first_name} {r.last_name}" for r in child_result}

    return [{**a.__dict__, "child_name": child_names.get(a.child_id)} for a in auths]


@router.post("", response_model=PickupAuthOut, status_code=status.HTTP_201_CREATED)
async def create_pickup_authorization(
    body: PickupAuthCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.person import Child, ChildGuardian

    child_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if child_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    # Parents can only create authorizations for their own children
    role = getattr(current_user, "_role", None)
    if role not in ("school_admin", "platform_admin"):
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == body.child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

    auth = PickupAuthorization(school_id=school_id, **body.model_dump())
    db.add(auth)
    await db.commit()
    await db.refresh(auth)

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
    current_user=Depends(get_current_user),
):
    from app.models.person import ChildGuardian

    result = await db.execute(
        select(PickupAuthorization).where(
            PickupAuthorization.id == auth_id,
            PickupAuthorization.school_id == school_id,
        )
    )
    auth = result.scalar_one_or_none()
    if auth is None:
        raise HTTPException(status_code=404, detail="Not found")

    # Parents can only update authorizations for their own children
    role = getattr(current_user, "_role", None)
    if role not in ("school_admin", "platform_admin"):
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == auth.child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

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
    current_user=Depends(get_current_user),
):
    from app.models.person import ChildGuardian

    result = await db.execute(
        select(PickupAuthorization).where(
            PickupAuthorization.id == auth_id,
            PickupAuthorization.school_id == school_id,
        )
    )
    auth = result.scalar_one_or_none()
    if auth is None:
        raise HTTPException(status_code=404, detail="Not found")

    # Parents can only delete authorizations for their own children
    role = getattr(current_user, "_role", None)
    if role not in ("school_admin", "platform_admin"):
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == auth.child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

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
    from app.models.person import Child, ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(MealOrder).where(MealOrder.school_id == school_id, MealOrder.ordered)

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

    child_ids_set = list({o.child_id for o in orders})
    child_names: dict = {}
    if child_ids_set:
        from app.models.person import Child
        cr = await db.execute(
            select(Child.id, Child.first_name, Child.last_name).where(Child.id.in_(child_ids_set))
        )
        child_names = {r.id: f"{r.first_name} {r.last_name}" for r in cr}

    return [{**o.__dict__, "child_name": child_names.get(o.child_id)} for o in orders]


@router.post("/meal-orders", response_model=MealOrderOut, status_code=status.HTTP_201_CREATED)
async def create_meal_order(
    body: MealOrderCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    # Parents can only create meal orders for their own children
    role = getattr(current_user, "_role", None)
    if role not in ("school_admin", "platform_admin", "teacher", "staff"):
        from app.models.person import ChildGuardian
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            raise HTTPException(status_code=403, detail="No guardian record linked")
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == body.child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="Not your child")

    # Upsert: update if exists, create if not
    existing = await db.execute(
        select(MealOrder).where(
            MealOrder.school_id == school_id,
            MealOrder.child_id == body.child_id,
            MealOrder.order_date == body.order_date,
            MealOrder.meal_type == body.meal_type,
        )
    )
    order = existing.scalar_one_or_none()
    ordered = body.quantity > 0
    if order:
        order.quantity = body.quantity
        order.ordered = ordered
    else:
        order = MealOrder(
            school_id=school_id,
            child_id=body.child_id,
            order_date=body.order_date,
            meal_type=body.meal_type,
            quantity=body.quantity,
            ordered=ordered,
        )
        db.add(order)
    await db.commit()
    await db.refresh(order)
    return {**order.__dict__, "child_name": None}


@router.get("/meal-orders/daily-counts", response_model=list[DailyMealCount])
async def get_daily_meal_counts(
    date: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from datetime import date as dt_date
    # Support both single date and date range
    if date:
        d = dt_date.fromisoformat(date)
        q_from, q_to = d, d
    elif date_from and date_to:
        q_from = dt_date.fromisoformat(date_from)
        q_to = dt_date.fromisoformat(date_to)
    else:
        q_from = q_to = dt_date.today()

    result = await db.execute(
        select(
            MealOrder.order_date,
            MealOrder.meal_type,
            sqlfunc.count(MealOrder.id).label("total"),
        )
        .where(
            MealOrder.school_id == school_id,
            MealOrder.ordered,
            MealOrder.order_date >= q_from,
            MealOrder.order_date <= q_to,
        )
        .group_by(MealOrder.order_date, MealOrder.meal_type)
        .order_by(MealOrder.order_date)
    )
    return [
        DailyMealCount(order_date=row.order_date, meal_type=row.meal_type, total=row.total)
        for row in result.all()
    ]
