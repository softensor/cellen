from typing import Optional
from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str
    school_slug: Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    role: str            # primary role — kept for compat
    roles: list[str] = []


class RefreshRequest(BaseModel):
    refresh_token: str


class AccessTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class MeResponse(BaseModel):
    id: str
    username: str
    role: str            # primary role — kept for compat
    roles: list[str] = []
    school_id: Optional[str] = None
    is_active: bool
