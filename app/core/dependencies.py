import uuid
from typing import Optional
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
):
    payload = decode_token(token)
    if payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )

    role: str = payload.get("role", "")
    user_id: str = payload.get("sub", "")
    school_id_str: Optional[str] = payload.get("school_id")

    if not user_id or not role:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )

    # Import here to avoid circular imports
    if role == "platform_admin":
        from app.models.school import PlatformUser
        result = await db.execute(
            select(PlatformUser).where(PlatformUser.id == uuid.UUID(user_id))
        )
        user = result.scalar_one_or_none()
        if user is None or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found or inactive",
            )
        # Attach role and school_id to the object dynamically for downstream use
        user._role = role
        user._school_id = None
        return user
    else:
        from app.models.user import User
        result = await db.execute(
            select(User).where(User.id == uuid.UUID(user_id))
        )
        user = result.scalar_one_or_none()
        if user is None or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found or inactive",
            )
        user._role = role
        user._school_id = uuid.UUID(school_id_str) if school_id_str else None
        return user


async def require_platform_admin(user=Depends(get_current_user)):
    if getattr(user, "_role", None) != "platform_admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Platform admin access required",
        )
    return user


async def require_school_admin(user=Depends(get_current_user)):
    role = getattr(user, "_role", None)
    if role not in ("school_admin", "platform_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="School admin access required",
        )
    return user


async def require_teacher(user=Depends(get_current_user)):
    role = getattr(user, "_role", None)
    if role not in ("teacher", "school_admin", "platform_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Teacher access required",
        )
    return user


async def require_staff(user=Depends(get_current_user)):
    role = getattr(user, "_role", None)
    if role not in ("staff", "teacher", "school_admin", "platform_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Staff access required",
        )
    return user


async def require_parent(user=Depends(get_current_user)):
    role = getattr(user, "_role", None)
    if role not in ("parent", "school_admin", "platform_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Parent access required",
        )
    return user


async def get_school_id(user=Depends(get_current_user)) -> UUID:
    school_id = getattr(user, "_school_id", None)
    if school_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="School context required",
        )
    return school_id
