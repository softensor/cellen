import uuid
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher

router = APIRouter(prefix="/evaluations", tags=["Child Evaluations"])


class EvaluationCreate(BaseModel):
    child_id: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    evaluation_period: str
    evaluation_date: date
    cognitive: Optional[int] = None
    motor: Optional[int] = None
    language: Optional[int] = None
    social_emotional: Optional[int] = None
    creativity: Optional[int] = None
    autonomy: Optional[int] = None
    overall_rating: Optional[str] = None
    observations: Optional[str] = None
    areas_to_improve: Optional[str] = None
    objectives_next_period: Optional[str] = None


class EvaluationUpdate(BaseModel):
    evaluation_period: Optional[str] = None
    evaluation_date: Optional[date] = None
    cognitive: Optional[int] = None
    motor: Optional[int] = None
    language: Optional[int] = None
    social_emotional: Optional[int] = None
    creativity: Optional[int] = None
    autonomy: Optional[int] = None
    overall_rating: Optional[str] = None
    observations: Optional[str] = None
    areas_to_improve: Optional[str] = None
    objectives_next_period: Optional[str] = None


class EvaluationResponse(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    school_id: uuid.UUID
    child_id: uuid.UUID
    evaluated_by: uuid.UUID
    school_year_id: Optional[uuid.UUID] = None
    evaluation_period: str
    evaluation_date: date
    cognitive: Optional[int] = None
    motor: Optional[int] = None
    language: Optional[int] = None
    social_emotional: Optional[int] = None
    creativity: Optional[int] = None
    autonomy: Optional[int] = None
    overall_rating: Optional[str] = None
    observations: Optional[str] = None
    areas_to_improve: Optional[str] = None
    objectives_next_period: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    child_name: Optional[str] = None


@router.get("", response_model=list[EvaluationResponse])
async def list_evaluations(
    child_id: Optional[uuid.UUID] = None,
    school_year_id: Optional[uuid.UUID] = None,
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.modern import ChildEvaluation
    from app.models.person import ChildGuardian

    role = getattr(current_user, "_role", "parent")
    query = select(ChildEvaluation).where(ChildEvaluation.school_id == school_id)

    if role not in ("school_admin", "platform_admin", "teacher"):
        # Parent: only see evaluations for their children
        guardian_id_result = await db.execute(
            select(ChildGuardian.child_id).where(
                ChildGuardian.guardian_id.in_(
                    select(ChildGuardian.guardian_id).where(
                        ChildGuardian.guardian_id == getattr(current_user, "guardian_id", None)
                    )
                )
            )
        )
        allowed_child_ids = [row[0] for row in guardian_id_result.all()]
        if not allowed_child_ids:
            return []
        query = query.where(ChildEvaluation.child_id.in_(allowed_child_ids))

    if child_id:
        query = query.where(ChildEvaluation.child_id == child_id)
    if school_year_id:
        query = query.where(ChildEvaluation.school_year_id == school_year_id)

    result = await db.execute(
        query.order_by(ChildEvaluation.evaluation_date.desc()).offset(skip).limit(limit)
    )
    evaluations = result.scalars().all()

    # Bulk fetch child names
    child_ids = list({e.child_id for e in evaluations})
    child_names: dict = {}
    if child_ids:
        from app.models.person import Child
        child_result = await db.execute(
            select(Child.id, Child.first_name, Child.last_name)
            .where(Child.id.in_(child_ids))
        )
        child_names = {row.id: f"{row.first_name} {row.last_name}" for row in child_result}

    return [
        {**e.__dict__, "child_name": child_names.get(e.child_id)}
        for e in evaluations
    ]


@router.post("", response_model=EvaluationResponse, status_code=status.HTTP_201_CREATED)
async def create_evaluation(
    body: EvaluationCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    from app.models.modern import ChildEvaluation

    employee_id = getattr(current_user, "employee_id", None)
    if employee_id is None:
        raise HTTPException(status_code=400, detail="Current user has no associated employee record")

    evaluation = ChildEvaluation(
        school_id=school_id,
        evaluated_by=employee_id,
        **body.model_dump(),
    )
    db.add(evaluation)
    await db.commit()
    await db.refresh(evaluation)
    return evaluation


@router.get("/child/{child_id}", response_model=list[EvaluationResponse])
async def get_child_evaluations(
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.modern import ChildEvaluation

    result = await db.execute(
        select(ChildEvaluation).where(
            ChildEvaluation.school_id == school_id,
            ChildEvaluation.child_id == child_id,
        ).order_by(ChildEvaluation.evaluation_date.desc())
    )
    return result.scalars().all()


@router.get("/{evaluation_id}", response_model=EvaluationResponse)
async def get_evaluation(
    evaluation_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    from app.models.modern import ChildEvaluation

    result = await db.execute(
        select(ChildEvaluation).where(
            ChildEvaluation.id == evaluation_id, ChildEvaluation.school_id == school_id
        )
    )
    evaluation = result.scalar_one_or_none()
    if evaluation is None:
        raise HTTPException(status_code=404, detail="Evaluation not found")
    return evaluation


@router.patch("/{evaluation_id}", response_model=EvaluationResponse)
async def update_evaluation(
    evaluation_id: uuid.UUID,
    body: EvaluationUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_teacher),
):
    from app.models.modern import ChildEvaluation

    result = await db.execute(
        select(ChildEvaluation).where(
            ChildEvaluation.id == evaluation_id, ChildEvaluation.school_id == school_id
        )
    )
    evaluation = result.scalar_one_or_none()
    if evaluation is None:
        raise HTTPException(status_code=404, detail="Evaluation not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(evaluation, field, value)
    await db.commit()
    await db.refresh(evaluation)
    return evaluation
