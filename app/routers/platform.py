import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_platform_admin
from app.core.security import hash_password
from app.models.finance import ExpenseCategory
from app.models.person import Child
from app.models.school import School
from app.models.user import User
from app.schemas.school import (
    SchoolCreate, SchoolResponse, SchoolUpdate, SchoolWithStats, PlatformStats
)

router = APIRouter(prefix="/platform", tags=["Platform"])

DEFAULT_EXPENSE_CATEGORIES = [
    "Salários",
    "Rendas",
    "Serviços de Utilidade (água/luz)",
    "Alimentação",
    "Material Escolar",
    "Manutenção",
    "Seguros",
    "Outros",
]


@router.get("/schools", response_model=list[SchoolWithStats])
async def list_schools(
    skip: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    result = await db.execute(select(School).offset(skip).limit(limit))
    schools = result.scalars().all()

    output = []
    for school in schools:
        # Count active users
        users_count_result = await db.execute(
            select(func.count(User.id)).where(User.school_id == school.id, User.is_active == True)
        )
        users_count = users_count_result.scalar_one()

        # Count children
        children_count_result = await db.execute(
            select(func.count(Child.id)).where(Child.school_id == school.id, Child.is_active == True)
        )
        children_count = children_count_result.scalar_one()

        school_dict = SchoolResponse.model_validate(school).model_dump()
        output.append(SchoolWithStats(**school_dict, active_users_count=users_count, children_count=children_count))

    return output


@router.post("/schools", response_model=SchoolResponse, status_code=status.HTTP_201_CREATED)
async def create_school(
    body: SchoolCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    # Check slug uniqueness
    existing = await db.execute(select(School).where(School.slug == body.slug))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="School slug already in use")

    school = School(
        name=body.name,
        slug=body.slug,
        address=body.address,
        city=body.city,
        country=body.country,
        phone=body.phone,
        email=body.email,
        logo_url=body.logo_url,
        subscription_notes=body.subscription_notes,
        is_active=True,
    )
    db.add(school)
    await db.flush()

    # Seed default expense categories
    for cat_name in DEFAULT_EXPENSE_CATEGORIES:
        category = ExpenseCategory(
            school_id=school.id,
            name=cat_name,
        )
        db.add(category)

    # Create school_admin user
    admin_user = User(
        school_id=school.id,
        username=body.admin_username,
        password_hash=hash_password(body.admin_password),
        role="school_admin",
        is_active=True,
    )
    db.add(admin_user)

    await db.commit()
    await db.refresh(school)
    return school


@router.get("/schools/{school_id}", response_model=SchoolResponse)
async def get_school(
    school_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")
    return school


@router.patch("/schools/{school_id}", response_model=SchoolResponse)
async def update_school(
    school_id: uuid.UUID,
    body: SchoolUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(school, field, value)

    await db.commit()
    await db.refresh(school)
    return school


@router.post("/schools/{school_id}/activate")
async def toggle_school_activation(
    school_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    school.is_active = not school.is_active
    await db.commit()
    return {"id": str(school.id), "is_active": school.is_active}


@router.get("/stats", response_model=PlatformStats)
async def platform_stats(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    total_schools_result = await db.execute(select(func.count(School.id)))
    total_schools = total_schools_result.scalar_one()

    active_schools_result = await db.execute(
        select(func.count(School.id)).where(School.is_active == True)
    )
    active_schools = active_schools_result.scalar_one()

    total_children_result = await db.execute(
        select(func.count(Child.id)).where(Child.is_active == True)
    )
    total_children = total_children_result.scalar_one()

    total_users_result = await db.execute(
        select(func.count(User.id)).where(User.is_active == True)
    )
    total_active_users = total_users_result.scalar_one()

    return PlatformStats(
        total_schools=total_schools,
        active_schools=active_schools,
        total_children=total_children,
        total_active_users=total_active_users,
    )
