import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token
from app.models.school import PlatformUser, School
from app.models.user import User


async def authenticate_school_user(
    db: AsyncSession, username: str, password: str, school_id: uuid.UUID
) -> Optional[User]:
    result = await db.execute(
        select(User).where(User.school_id == school_id, User.username == username, User.is_active == True)
    )
    user = result.scalar_one_or_none()
    if user is None or not verify_password(password, user.password_hash):
        return None
    return user


async def authenticate_platform_user(
    db: AsyncSession, email: str, password: str
) -> Optional[PlatformUser]:
    result = await db.execute(
        select(PlatformUser).where(PlatformUser.email == email, PlatformUser.is_active == True)
    )
    user = result.scalar_one_or_none()
    if user is None or not verify_password(password, user.password_hash):
        return None
    return user


async def get_school_by_slug(db: AsyncSession, slug: str) -> Optional[School]:
    result = await db.execute(
        select(School).where(School.slug == slug, School.is_active == True)
    )
    return result.scalar_one_or_none()


def build_tokens_for_school_user(user: User) -> dict:
    token_data = {
        "sub": str(user.id),
        "role": user.role,
        "school_id": str(user.school_id),
    }
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "role": user.role,
    }


def build_tokens_for_platform_user(user: PlatformUser) -> dict:
    token_data = {
        "sub": str(user.id),
        "role": "platform_admin",
        "school_id": None,
    }
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "role": "platform_admin",
    }
