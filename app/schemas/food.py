import uuid
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class FoodBase(BaseModel):
    name: str
    description: Optional[str] = None
    food_type: Optional[str] = None  # breakfast, lunch, snack, etc.


class FoodCreate(FoodBase):
    pass


class FoodUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    food_type: Optional[str] = None


class FoodResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)
    id: uuid.UUID
    school_id: uuid.UUID
    name: str
    # DB columns are `details` and `type`; API exposes them as `description` and `food_type`
    description: Optional[str] = Field(None, validation_alias='details')
    food_type: Optional[str] = Field(None, validation_alias='type')
    created_at: Optional[datetime] = None


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
    food_name: Optional[str] = None


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
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    items: List[FoodMenuItemResponse] = []
