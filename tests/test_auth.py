"""
Tests for /auth/* endpoints.
"""
import pytest
from httpx import AsyncClient

from app.core.config import settings
from tests.conftest import auth, uid


# ---------------------------------------------------------------------------
# 1. Platform-admin login
# ---------------------------------------------------------------------------
async def test_platform_admin_login(client: AsyncClient):
    r = await client.post(
        "/auth/login",
        json={"username": settings.PLATFORM_ADMIN_EMAIL, "password": settings.PLATFORM_ADMIN_PASSWORD},
    )
    assert r.status_code == 200
    data = r.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["access_token"]
    assert data["refresh_token"]


# ---------------------------------------------------------------------------
# 2. School-admin login
# ---------------------------------------------------------------------------
async def test_school_admin_login(client: AsyncClient, make_school):
    school, token, slug, username = await make_school("auth")
    r = await client.post(
        "/auth/login",
        json={"username": username, "password": "Pass1234!", "school_slug": slug},
    )
    assert r.status_code == 200
    assert r.json()["access_token"]


# ---------------------------------------------------------------------------
# 3. Wrong password → 401
# ---------------------------------------------------------------------------
async def test_login_wrong_password(client: AsyncClient):
    r = await client.post(
        "/auth/login",
        json={"username": settings.PLATFORM_ADMIN_EMAIL, "password": "totally-wrong"},
    )
    assert r.status_code == 401


# ---------------------------------------------------------------------------
# 4. Valid user but wrong school_slug → 401
# ---------------------------------------------------------------------------
async def test_login_wrong_slug(client: AsyncClient, make_school):
    school, token, slug, username = await make_school("authslug")
    r = await client.post(
        "/auth/login",
        json={"username": username, "password": "Pass1234!", "school_slug": "nonexistent-slug-xyz"},
    )
    assert r.status_code == 401


# ---------------------------------------------------------------------------
# 5. GET /auth/me — school-admin
# ---------------------------------------------------------------------------
async def test_me_school_admin(client: AsyncClient, make_school):
    school, token, slug, username = await make_school("authme")
    r = await client.get("/auth/me", headers=auth(token))
    assert r.status_code == 200
    assert r.json()["role"] == "school_admin"


# ---------------------------------------------------------------------------
# 6. GET /auth/me — platform-admin
# ---------------------------------------------------------------------------
async def test_me_platform_admin(client: AsyncClient, padmin_token: str):
    r = await client.get("/auth/me", headers=auth(padmin_token))
    assert r.status_code == 200
    assert r.json()["role"] == "platform_admin"


# ---------------------------------------------------------------------------
# 7. Token refresh
# ---------------------------------------------------------------------------
async def test_token_refresh(client: AsyncClient):
    login_r = await client.post(
        "/auth/login",
        json={"username": settings.PLATFORM_ADMIN_EMAIL, "password": settings.PLATFORM_ADMIN_PASSWORD},
    )
    assert login_r.status_code == 200
    refresh_token = login_r.json()["refresh_token"]

    r = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
    assert r.status_code == 200
    data = r.json()
    assert "access_token" in data
    assert data["access_token"]


# ---------------------------------------------------------------------------
# 8. Change password → login with new password succeeds
# ---------------------------------------------------------------------------
async def test_change_password(client: AsyncClient, make_school):
    school, token, slug, username = await make_school("authpw")
    new_pw = f"New{uid()}#1"

    r = await client.post(
        "/auth/change-password",
        json={"current_password": "Pass1234!", "new_password": new_pw},
        headers=auth(token),
    )
    assert r.status_code == 200

    # Login with the new password must succeed
    r2 = await client.post(
        "/auth/login",
        json={"username": username, "password": new_pw, "school_slug": slug},
    )
    assert r2.status_code == 200


# ---------------------------------------------------------------------------
# 9. Change password with wrong current → 400
# ---------------------------------------------------------------------------
async def test_change_password_wrong_current(client: AsyncClient, make_school):
    school, token, slug, username = await make_school("authpww")

    r = await client.post(
        "/auth/change-password",
        json={"current_password": "WrongPassword99!", "new_password": "NewPass1234!"},
        headers=auth(token),
    )
    assert r.status_code == 400


# ---------------------------------------------------------------------------
# 10. Logout → 200
# ---------------------------------------------------------------------------
async def test_logout(client: AsyncClient, padmin_token: str):
    r = await client.post("/auth/logout", headers=auth(padmin_token))
    assert r.status_code == 200


# ---------------------------------------------------------------------------
# 11. Unauthenticated request → 401 or 403
# ---------------------------------------------------------------------------
async def test_unauthenticated_request(client: AsyncClient):
    r = await client.get("/auth/me")
    assert r.status_code in (401, 403)
