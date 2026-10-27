import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_parent, require_school_admin
from app.core.security import hash_password
from app.models.billing import StudentFinanceProfile
from app.models.person import Child, ChildGuardian, Guardian
from app.models.user import User
from app.schemas.guardian import (
    ChildGuardianLink, ChildGuardianResponse, GuardianCreate, GuardianResponse, GuardianUpdate
)
from app.services.billing_profiles import (
    active_enrollment_for_child,
    ensure_profile,
    get_school_year,
    mark_plans_stale,
)

router = APIRouter(prefix="/guardians", tags=["Guardians"])


async def _active_year(db: AsyncSession, school_id: uuid.UUID):
    school_year = await get_school_year(db, school_id)
    if school_year is None or not school_year.is_active:
        return None
    return school_year


async def _sync_profile_after_link(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    child_id: uuid.UUID,
    guardian_id: uuid.UUID,
) -> None:
    """Keep the student's billing identity in step with guardian links.

    The profile only exists for an active school year and an active
    enrollment, but every link change still marks the family's plans stale:
    adding a sibling changes the discount on the other children's tuition.
    """
    school_year = await _active_year(db, school_id)
    if school_year is None:
        return
    primary = (
        await db.execute(
            select(ChildGuardian.guardian_id)
            .where(
                ChildGuardian.school_id == school_id,
                ChildGuardian.child_id == child_id,
                ChildGuardian.is_primary_contact.is_(True),
            )
            .order_by(ChildGuardian.id)
        )
    ).scalars().first()
    enrollment = await active_enrollment_for_child(
        db, school_id, child_id, school_year.id
    )
    if enrollment is not None:
        await ensure_profile(
            db,
            school_id=school_id,
            child_id=child_id,
            school_year_id=school_year.id,
            guardian_id=primary or guardian_id,
            enrollment_date=enrollment.enrollment_date,
        )
    await mark_plans_stale(
        db,
        school_id=school_id,
        school_year_id=school_year.id,
        guardian_ids={guardian_id},
        child_ids={child_id},
    )


class SetPasswordBody(BaseModel):
    password: str


@router.get("", response_model=list[GuardianResponse])
async def list_guardians(
    skip: int = 0,
    limit: int = 50,
    search: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Guardian).where(Guardian.school_id == school_id)
    if search:
        query = query.where(
            or_(
                Guardian.first_name.ilike(f"%{search}%"),
                Guardian.last_name.ilike(f"%{search}%"),
                Guardian.middle_name.ilike(f"%{search}%"),
            )
        )
    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=GuardianResponse, status_code=status.HTTP_201_CREATED)
async def create_guardian(
    body: GuardianCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Check username not already taken in this school
    existing = await db.execute(
        select(User).where(User.school_id == school_id, User.username == body.username)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Nome de utilizador já existe nesta escola")

    guardian_data = body.model_dump(exclude={"username", "password"})
    guardian = Guardian(school_id=school_id, **guardian_data)
    db.add(guardian)
    await db.flush()  # get guardian.id before creating user

    user = User(
        school_id=school_id,
        username=body.username,
        password_hash=hash_password(body.password),
        roles=["parent"],
        guardian_id=guardian.id,
    )
    db.add(user)
    await db.commit()
    await db.refresh(guardian)
    response = GuardianResponse.model_validate(guardian)
    response.username = body.username
    return response


@router.get("/me", response_model=GuardianResponse)
async def get_own_guardian_profile(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    user=Depends(require_parent),
):
    guardian_id = getattr(user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="Parent profile required")
    guardian = await db.scalar(select(Guardian).where(
        Guardian.id == guardian_id,
        Guardian.school_id == school_id,
    ))
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")
    return guardian


@router.get("/{guardian_id}", response_model=GuardianResponse)
async def get_guardian(
    guardian_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")
    return guardian


@router.patch("/{guardian_id}", response_model=GuardianResponse)
async def update_guardian(
    guardian_id: uuid.UUID,
    body: GuardianUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(guardian, field, value)

    await db.commit()
    await db.refresh(guardian)
    return guardian


@router.patch("/{guardian_id}/set-password")
async def set_guardian_password(
    guardian_id: uuid.UUID,
    body: SetPasswordBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(User).where(User.guardian_id == guardian_id, User.school_id == school_id)
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="Conta de acesso não encontrada")
    user.password_hash = hash_password(body.password)
    await db.commit()
    return {"message": "Senha actualizada"}


@router.delete("/{guardian_id}")
async def delete_guardian(
    guardian_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    guardian = result.scalar_one_or_none()
    if guardian is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    await db.delete(guardian)
    await db.commit()
    return {"message": "Guardian deleted"}


@router.post("/{guardian_id}/children", response_model=ChildGuardianResponse, status_code=status.HTTP_201_CREATED)
async def link_guardian_to_child(
    guardian_id: uuid.UUID,
    body: ChildGuardianLink,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Verify guardian
    g_result = await db.execute(
        select(Guardian).where(Guardian.id == guardian_id, Guardian.school_id == school_id)
    )
    if g_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Guardian not found")

    # Verify child
    c_result = await db.execute(
        select(Child).where(Child.id == body.child_id, Child.school_id == school_id)
    )
    if c_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Child not found")

    # Check not already linked
    existing = await db.execute(
        select(ChildGuardian).where(
            ChildGuardian.child_id == body.child_id,
            ChildGuardian.guardian_id == guardian_id,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Guardian already linked to this child")

    primaries = list(
        (
            await db.execute(
                select(ChildGuardian).where(
                    ChildGuardian.school_id == school_id,
                    ChildGuardian.child_id == body.child_id,
                    ChildGuardian.is_primary_contact.is_(True),
                )
            )
        ).scalars().all()
    )
    if body.is_primary_contact and any(
        link.guardian_id != guardian_id for link in primaries
    ):
        raise HTTPException(
            status_code=422,
            detail="O aluno já tem um encarregado principal; remova essa marcação primeiro",
        )
    # Every child needs exactly one billing contact: the first link becomes
    # primary automatically, and the director can move the flag afterwards.
    is_primary = body.is_primary_contact or not primaries

    link = ChildGuardian(
        school_id=school_id,
        child_id=body.child_id,
        guardian_id=guardian_id,
        relationship_type=body.relationship_type,
        is_primary_contact=is_primary,
    )
    db.add(link)
    await db.flush()
    await _sync_profile_after_link(
        db, school_id=school_id, child_id=body.child_id, guardian_id=guardian_id
    )
    await db.commit()
    await db.refresh(link)
    return link


@router.delete("/{guardian_id}/children/{child_id}")
async def unlink_guardian_from_child(
    guardian_id: uuid.UUID,
    child_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(ChildGuardian).where(
            ChildGuardian.guardian_id == guardian_id,
            ChildGuardian.child_id == child_id,
            ChildGuardian.school_id == school_id,
        )
    )
    link = result.scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=404, detail="Link not found")

    was_primary = link.is_primary_contact
    await db.delete(link)
    await db.flush()

    remaining = list(
        (
            await db.execute(
                select(ChildGuardian)
                .where(
                    ChildGuardian.school_id == school_id,
                    ChildGuardian.child_id == child_id,
                )
                .order_by(ChildGuardian.id)
            )
        ).scalars().all()
    )
    if was_primary and remaining:
        remaining[0].is_primary_contact = True

    school_year = await _active_year(db, school_id)
    if school_year is not None:
        profile = (
            await db.execute(
                select(StudentFinanceProfile).where(
                    StudentFinanceProfile.school_id == school_id,
                    StudentFinanceProfile.child_id == child_id,
                    StudentFinanceProfile.school_year_id == school_year.id,
                )
            )
        ).scalar_one_or_none()
        if profile is not None and profile.billing_guardian_id == guardian_id:
            profile.billing_guardian_id = (
                remaining[0].guardian_id if remaining else None
            )
            profile.plan_stale = True
        await mark_plans_stale(
            db,
            school_id=school_id,
            school_year_id=school_year.id,
            guardian_ids={guardian_id},
            child_ids={child_id},
        )

    await db.commit()
    return {"message": "Guardian unlinked from child"}
