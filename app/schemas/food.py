import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict


class FoodBase(BaseModel):
    name: str
    details: Optional[str] = None
    type: Optional[str] = None  # sopa, prato, sobremesa, lanche, bebida


class FoodCreate(FoodBase):
    pass


class FoodUpdate(BaseModel):
    name: Optional[str] = None
    details: Optional[str] = None
    type: Optional[str] = None


class FoodResponse(FoodBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime


class FoodMenuItemBase(BaseModel):
    day_of_week: int
    meal_type: str  # breakfast, lunch, snack
    meal_component: Optional[str] = None  # sopa, prato, sobremesa, drink
    food_id: uuid.UUID


class FoodMenuItemCreate(FoodMenuItemBase):
    pass


class FoodMenuItemResponse(FoodMenuItemBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    food_menu_id: uuid.UUID
    school_id: uuid.UUID


class FoodMenuBase(BaseModel):
    level: str
    start_date: date
    end_date: date


class FoodMenuCreate(FoodMenuBase):
    items: List[FoodMenuItemCreate] = []


class FoodMenuUpdate(BaseModel):
    level: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class FoodMenuResponse(FoodMenuBase):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    items: List[FoodMenuItemResponse] = []
