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

# ---------------------------------------------------------------------------
# Role sets for permission checks
# ---------------------------------------------------------------------------

_PLATFORM_ADMIN = {"platform_admin"}
_SCHOOL_ADMIN   = {"school_admin"}
_COORDINATOR    = {"coordinator"}
_FINANCE        = {"finance_officer"}
_SECRETARY      = {"secretary"}
_TEACHER        = {"teacher"}
_NURSE          = {"nurse"}
_PARENT         = {"parent"}
_STUDENT        = {"student"}

# Composed permission groups
_ADMIN_OR_PLATFORM      = _SCHOOL_ADMIN | _PLATFORM_ADMIN
_ACADEMIC_STAFF         = _SCHOOL_ADMIN | _COORDINATOR | _PLATFORM_ADMIN
_FINANCE_ACCESS         = _SCHOOL_ADMIN | _FINANCE | _PLATFORM_ADMIN
_TEACHER_ACCESS         = _SCHOOL_ADMIN | _COORDINATOR | _TEACHER | _PLATFORM_ADMIN
_STAFF_ACCESS           = _SCHOOL_ADMIN | _COORDINATOR | _TEACHER | _SECRETARY | _NURSE | _PLATFORM_ADMIN
_HEALTH_ACCESS          = _SCHOOL_ADMIN | _COORDINATOR | _TEACHER | _NURSE | _PLATFORM_ADMIN
_PARENT_OR_ADMIN        = _PARENT | _ADMIN_OR_PLATFORM


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

    user_id: str = payload.get("sub", "")
    # Support both old (role: str) and new (roles: list) tokens
    roles_raw = payload.get("roles")
    if isinstance(roles_raw, list) and roles_raw:
        roles: list[str] = [str(r) for r in roles_raw]
    else:
        single = payload.get("role", "")
        roles = [single] if single else []

    school_id_str: Optional[str] = payload.get("school_id")

    if not user_id or not roles:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )

    if "platform_admin" in roles:
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
        user._roles = set(roles)
        user._roles_list = roles
        user._role = roles[0]
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
        user._roles = set(roles)
        user._roles_list = roles
        user._role = roles[0]
        user._school_id = uuid.UUID(school_id_str) if school_id_str else None
        return user


def _check_roles(user, allowed: set[str], detail: str):
    user_roles: set[str] = getattr(user, "_roles", set())
    if not user_roles.intersection(allowed):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)
    return user


async def require_platform_admin(user=Depends(get_current_user)):
    return _check_roles(user, _PLATFORM_ADMIN, "Platform admin access required")


async def require_school_admin(user=Depends(get_current_user)):
    return _check_roles(user, _ADMIN_OR_PLATFORM, "School admin access required")


async def require_coordinator(user=Depends(get_current_user)):
    """Coordinator or school_admin."""
    return _check_roles(user, _ACADEMIC_STAFF, "Coordinator access required")


async def require_finance_access(user=Depends(get_current_user)):
    """finance_officer or school_admin."""
    return _check_roles(user, _FINANCE_ACCESS, "Finance access required")


async def require_secretary(user=Depends(get_current_user)):
    """secretary, coordinator, or school_admin."""
    return _check_roles(user, _ACADEMIC_STAFF | _SECRETARY, "Secretary access required")


async def require_teacher(user=Depends(get_current_user)):
    """teacher, coordinator, school_admin (classroom operations)."""
    return _check_roles(user, _TEACHER_ACCESS, "Teacher access required")


async def require_staff(user=Depends(get_current_user)):
    """Any school staff member (all roles except parent/student)."""
    return _check_roles(user, _STAFF_ACCESS, "Staff access required")


async def require_health_access(user=Depends(get_current_user)):
    """nurse, teacher, coordinator, school_admin."""
    return _check_roles(user, _HEALTH_ACCESS, "Health access required")


async def require_nurse(user=Depends(get_current_user)):
    """nurse or school_admin."""
    return _check_roles(user, _NURSE | _ADMIN_OR_PLATFORM, "Nurse access required")


async def require_parent(user=Depends(get_current_user)):
    return _check_roles(user, _PARENT_OR_ADMIN, "Parent access required")


async def get_school_id(user=Depends(get_current_user)) -> UUID:
    school_id = getattr(user, "_school_id", None)
    if school_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="School context required",
        )
    return school_id
