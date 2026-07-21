from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.security import decode_token, create_access_token, hash_password, verify_password
from app.schemas.auth import (
    LoginRequest, TokenResponse, RefreshRequest, AccessTokenResponse, MeResponse
)
from app.services.auth import (
    authenticate_school_user,
    authenticate_platform_user,
    get_school_by_slug,
    build_tokens_for_school_user,
    build_tokens_for_platform_user,
)


class ChangePasswordBody(BaseModel):
    current_password: str
    new_password: str

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    if body.school_slug:
        school = await get_school_by_slug(db, body.school_slug)
        if school is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials",
            )
        user = await authenticate_school_user(db, body.username, body.password, school.id)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials",
            )
        return build_tokens_for_school_user(user)
    else:
        # Platform admin login
        user = await authenticate_platform_user(db, body.username, body.password)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials",
            )
        return build_tokens_for_platform_user(user)


@router.post("/refresh", response_model=AccessTokenResponse)
async def refresh_token(body: RefreshRequest):
    payload = decode_token(body.refresh_token)
    if payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type",
        )
    # Build new access token preserving all original claims
    role = payload.get("role", "")
    roles = payload.get("roles") or ([role] if role else [])
    token_data = {
        "sub": payload["sub"],
        "role": role,
        "roles": roles,
        "school_id": payload.get("school_id"),
        "employee_id": payload.get("employee_id"),
        "guardian_id": payload.get("guardian_id"),
    }
    access_token = create_access_token(token_data)
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/logout")
async def logout():
    # Stateless JWT — client discards token
    return {"message": "Logged out successfully"}


@router.post("/change-password")
async def change_password(
    body: ChangePasswordBody,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    password_hash = getattr(current_user, "password_hash", None)
    if password_hash is None or not verify_password(body.current_password, password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Palavra-passe actual incorrecta",
        )
    current_user.password_hash = hash_password(body.new_password)
    await db.commit()
    return {"message": "Palavra-passe alterada com sucesso"}


@router.get("/me", response_model=MeResponse)
async def me(current_user=Depends(get_current_user)):
    role = getattr(current_user, "_role", "unknown")
    school_id = getattr(current_user, "_school_id", None)

    # PlatformUser has email, User has username
    username = getattr(current_user, "username", None) or getattr(current_user, "email", "")

    roles_list: list[str] = getattr(current_user, "_roles_list", [role])
    return MeResponse(
        id=str(current_user.id),
        username=username,
        role=role,
        roles=roles_list,
        school_id=str(school_id) if school_id else None,
        is_active=current_user.is_active,
    )
