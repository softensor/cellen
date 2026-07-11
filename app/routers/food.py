import uuid
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin, require_teacher
from app.models.food import Food, FoodMenu, FoodMenuItem
from app.schemas.food import (
    FoodCreate, FoodMenuCreate, FoodMenuItemCreate, FoodMenuItemResponse,
    FoodMenuResponse, FoodMenuUpdate, FoodResponse, FoodUpdate,
)

router = APIRouter(prefix="/food", tags=["Food"])


# ─── Foods ────────────────────────────────────────────────────────────────────

@router.get("/foods", response_model=list[FoodResponse])
async def list_foods(
    skip: int = 0,
    limit: int = 50,
    food_type: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(Food).where(Food.school_id == school_id)
    if food_type:
        query = query.where(Food.type == food_type)
    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.post("/foods", response_model=FoodResponse, status_code=status.HTTP_201_CREATED)
async def create_food(
    body: FoodCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    food = Food(school_id=school_id, **body.model_dump())
    db.add(food)
    await db.commit()
    await db.refresh(food)
    return food


@router.get("/foods/{food_id}", response_model=FoodResponse)
async def get_food(
    food_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(Food).where(Food.id == food_id, Food.school_id == school_id)
    )
    food = result.scalar_one_or_none()
    if food is None:
        raise HTTPException(status_code=404, detail="Food not found")
    return food


@router.patch("/foods/{food_id}", response_model=FoodResponse)
async def update_food(
    food_id: uuid.UUID,
    body: FoodUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Food).where(Food.id == food_id, Food.school_id == school_id)
    )
    food = result.scalar_one_or_none()
    if food is None:
        raise HTTPException(status_code=404, detail="Food not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(food, field, value)
    await db.commit()
    await db.refresh(food)
    return food


@router.delete("/foods/{food_id}")
async def delete_food(
    food_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Food).where(Food.id == food_id, Food.school_id == school_id)
    )
    food = result.scalar_one_or_none()
    if food is None:
        raise HTTPException(status_code=404, detail="Food not found")
    await db.delete(food)
    await db.commit()
    return {"message": "Food deleted"}


# ─── Food Menus ───────────────────────────────────────────────────────────────

@router.get("/menus", response_model=list[FoodMenuResponse])
async def list_menus(
    skip: int = 0,
    limit: int = 50,
    level: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    query = select(FoodMenu).where(FoodMenu.school_id == school_id)
    if level:
        query = query.where(FoodMenu.level == level)
    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.get("/menus/current", response_model=FoodMenuResponse)
async def get_current_menu(
    level: str,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    today = date.today()
    result = await db.execute(
        select(FoodMenu).where(
            FoodMenu.school_id == school_id,
            FoodMenu.level == level,
            FoodMenu.start_date <= today,
            FoodMenu.end_date >= today,
        ).order_by(FoodMenu.start_date.desc()).limit(1)
    )
    menu = result.scalar_one_or_none()
    if menu is None:
        raise HTTPException(status_code=404, detail="No active menu found for this level")
    return menu


@router.post("/menus", response_model=FoodMenuResponse, status_code=status.HTTP_201_CREATED)
async def create_menu(
    body: FoodMenuCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    items_data = body.items
    menu_data = body.model_dump(exclude={"items"})
    menu = FoodMenu(school_id=school_id, **menu_data)
    db.add(menu)
    await db.flush()

    for item_data in items_data:
        item = FoodMenuItem(
            school_id=school_id,
            food_menu_id=menu.id,
            **item_data.model_dump(),
        )
        db.add(item)

    await db.commit()
    await db.refresh(menu)
    return menu


@router.get("/menus/{menu_id}", response_model=FoodMenuResponse)
async def get_menu(
    menu_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    result = await db.execute(
        select(FoodMenu).where(FoodMenu.id == menu_id, FoodMenu.school_id == school_id)
    )
    menu = result.scalar_one_or_none()
    if menu is None:
        raise HTTPException(status_code=404, detail="Menu not found")
    return menu


@router.patch("/menus/{menu_id}", response_model=FoodMenuResponse)
async def update_menu(
    menu_id: uuid.UUID,
    body: FoodMenuUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(FoodMenu).where(FoodMenu.id == menu_id, FoodMenu.school_id == school_id)
    )
    menu = result.scalar_one_or_none()
    if menu is None:
        raise HTTPException(status_code=404, detail="Menu not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(menu, field, value)
    await db.commit()
    await db.refresh(menu)
    return menu


@router.delete("/menus/{menu_id}")
async def delete_menu(
    menu_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(FoodMenu).where(FoodMenu.id == menu_id, FoodMenu.school_id == school_id)
    )
    menu = result.scalar_one_or_none()
    if menu is None:
        raise HTTPException(status_code=404, detail="Menu not found")
    await db.delete(menu)
    await db.commit()
    return {"message": "Menu deleted"}


# Menu items
@router.post("/menus/{menu_id}/items", response_model=FoodMenuItemResponse, status_code=status.HTTP_201_CREATED)
async def add_menu_item(
    menu_id: uuid.UUID,
    body: FoodMenuItemCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    menu_result = await db.execute(
        select(FoodMenu).where(FoodMenu.id == menu_id, FoodMenu.school_id == school_id)
    )
    if menu_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Menu not found")

    item = FoodMenuItem(school_id=school_id, food_menu_id=menu_id, **body.model_dump())
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return item


@router.delete("/menus/{menu_id}/items/{item_id}")
async def delete_menu_item(
    menu_id: uuid.UUID,
    item_id: int,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(FoodMenuItem).where(
            FoodMenuItem.id == item_id,
            FoodMenuItem.food_menu_id == menu_id,
            FoodMenuItem.school_id == school_id,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Menu item not found")
    await db.delete(item)
    await db.commit()
    return {"message": "Menu item deleted"}
