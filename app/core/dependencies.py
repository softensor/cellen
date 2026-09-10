import uuid
from typing import Optional
from uuid import UUID

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.custom_roles import resolve_permissions, resolve_roles
from app.core.security import decode_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

# ---------------------------------------------------------------------------
# Role sets for permission checks
# ---------------------------------------------------------------------------

_PLATFORM_ADMIN = {"platform_admin"}
_SCHOOL_ADMIN   = {"school_admin"}
_COORDINATOR    = {"coordinator"}
_FINANCE        = {"finance_officer"}
_CONFIGURABLE_FINANCE = {"coordinator", "finance_officer", "secretary"}
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

_PATH_PERMISSIONS = (
    ("/api/v1/academic/activities", "activities"),
    ("/api/v1/reports/med", "med_report"),
    ("/api/v1/lesson-attendance", "lesson_attendance"),
    ("/api/v1/pickup-authorizations", "pickup_auth"),
    ("/api/v1/trip-authorizations", "trip_auth"),
    ("/api/v1/health-events", "health"),
    ("/api/v1/immunizations", "immunizations"),
    ("/api/v1/announcements", "announcements"),
    ("/api/v1/appointments", "appointments"),
    ("/api/v1/cadernetas", "caderneta"),
    ("/api/v1/evaluations", "evaluations"),
    ("/api/v1/attendance", "checkin"),
    ("/api/v1/timetable", "timetable_k12"),
    ("/api/v1/absences", "absences"),
    ("/api/v1/incidents", "incidents"),
    ("/api/v1/documents", "documents"),
    ("/api/v1/academic", "academic"),
    ("/api/v1/children", "people"),
    ("/api/v1/guardians", "people"),
    ("/api/v1/employees", "people"),
    ("/api/v1/messages", "messages"),
    ("/api/v1/photos", "photos"),
    ("/api/v1/events", "events"),
    ("/api/v1/food", "meal_orders"),
    ("/api/v1/grades", "grades"),
    ("/api/v1/reports", "reports"),
    ("/api/v1/schools", "school_settings"),
    ("/api/v1/finance", "finance"),
    ("/api/v1/finreg", "finance"),
)


def _request_permission(request: Request | None) -> str | None:
    path = request.url.path if request is not None else ""
    return next((permission for prefix, permission in _PATH_PERMISSIONS
                 if path.startswith(prefix)), None)


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
        from app.models.school import School
        school = await db.get(School, user._school_id) if user._school_id else None
        if school is None or not school.is_active or user.school_id != school.id:
            raise HTTPException(status_code=401, detail="Invalid school context")
        user._school_features = school.resolved_features
        # Use current stored assignments so disabling or changing a custom role
        # takes effect even for previously issued access/refresh tokens.
        effective_roles = resolve_roles(list(user.roles), user._school_features)
        if not effective_roles:
            raise HTTPException(status_code=403, detail="Nenhuma função de acesso activa")
        user._roles = set(effective_roles)
        user._roles_list = effective_roles
        user._role = effective_roles[0]
        user._custom_permissions = resolve_permissions(
            list(user.roles), user._school_features
        )
        return user


def _check_roles(user, allowed: set[str], detail: str, request: Request | None = None):
    user_roles: set[str] = getattr(user, "_roles", set())
    custom_permissions: set[str] = getattr(user, "_custom_permissions", set())
    permission = _request_permission(request)
    school_features = getattr(user, "_school_features", {}) or {}
    custom_allowed = (permission in custom_permissions
                      and school_features.get(permission, True) is not False)
    if (not user_roles.intersection(allowed)
            and not custom_allowed):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)
    return user


async def require_platform_admin(user=Depends(get_current_user)):
    return _check_roles(user, _PLATFORM_ADMIN, "Platform admin access required")


async def require_school_admin(request: Request, user=Depends(get_current_user)):
    return _check_roles(user, _ADMIN_OR_PLATFORM, "School admin access required", request)


async def require_coordinator(request: Request, user=Depends(get_current_user)):
    """Coordinator or school_admin."""
    return _check_roles(user, _ACADEMIC_STAFF, "Coordinator access required", request)


async def require_finance_access(user=Depends(get_current_user)):
    """School administrators or locally granted operational finance roles."""
    roles = set(getattr(user, "_roles", set()))
    if roles & _ADMIN_OR_PLATFORM:
        return user
    features = getattr(user, "_school_features", {}) or {}
    if not features.get("finance", True):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Finance access required")
    if "finance" in getattr(user, "_custom_permissions", set()):
        return user
    eligible = roles & _CONFIGURABLE_FINANCE
    if not eligible:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Finance access required")
    permissions = features.get("role_permissions") or {}
    for role in eligible:
        configured = (permissions.get(role) or {}).get("finance")
        default = role == "finance_officer"
        if configured if isinstance(configured, bool) else default:
            return user
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Finance access required")


async def require_secretary(request: Request, user=Depends(get_current_user)):
    """secretary, coordinator, or school_admin."""
    return _check_roles(user, _ACADEMIC_STAFF | _SECRETARY, "Secretary access required", request)


async def require_teacher(request: Request, user=Depends(get_current_user)):
    """teacher, coordinator, school_admin (classroom operations)."""
    return _check_roles(user, _TEACHER_ACCESS, "Teacher access required", request)


async def require_staff(request: Request, user=Depends(get_current_user)):
    """Any school staff member (all roles except parent/student)."""
    return _check_roles(user, _STAFF_ACCESS, "Staff access required", request)


async def require_health_access(request: Request, user=Depends(get_current_user)):
    """nurse, teacher, coordinator, school_admin."""
    return _check_roles(user, _HEALTH_ACCESS, "Health access required", request)


async def require_nurse(request: Request, user=Depends(get_current_user)):
    """nurse or school_admin."""
    return _check_roles(user, _NURSE | _ADMIN_OR_PLATFORM, "Nurse access required", request)


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
