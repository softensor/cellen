import uuid
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


class CadernetaBase(BaseModel):
    child_id: uuid.UUID
    teacher_id: uuid.UUID
    report_date: date
    breakfast_rating: Optional[str] = None  # Bem, Muito Bem, Mal, Não Comeu
    lunch_rating: Optional[str] = None
    snack_rating: Optional[str] = None
    physiological_needs: Optional[str] = None  # Normal, Mole, Duro
    had_nap: Optional[bool] = None
    sensorial_motor_development: Optional[str] = None
    intellectual_development: Optional[str] = None
    social_development: Optional[str] = None
    affective_development: Optional[str] = None
    general_observations: Optional[str] = None


class CadernetaCreate(CadernetaBase):
    pass


class CadernetaUpdate(BaseModel):
    breakfast_rating: Optional[str] = None
    lunch_rating: Optional[str] = None
    snack_rating: Optional[str] = None
    physiological_needs: Optional[str] = None
    had_nap: Optional[bool] = None
    sensorial_motor_development: Optional[str] = None
    intellectual_development: Optional[str] = None
    social_development: Optional[str] = None
    affective_development: Optional[str] = None
    general_observations: Optional[str] = None


class CadernetaResponse(CadernetaBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    school_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
