"""
Tests for /platform/* endpoints (platform-admin only).
"""
from httpx import AsyncClient

from tests.conftest import auth, uid


# ---------------------------------------------------------------------------
# 1. List schools as platform-admin
# ---------------------------------------------------------------------------
async def test_list_schools_as_padmin(client: AsyncClient, padmin_token: str):
    r = await client.get("/platform/schools", headers=auth(padmin_token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# ---------------------------------------------------------------------------
# 2. Create school → 201, is_active==True, slug matches
# ---------------------------------------------------------------------------
async def test_create_school(client: AsyncClient, padmin_token: str):
    slug = f"newsch-{uid()}"
    r = await client.post(
        "/platform/schools",
        json={
            "name": "Test School",
            "slug": slug,
            "admin_username": f"adm-{uid()}",
            "admin_password": "Pass1234!",
        },
        headers=auth(padmin_token),
    )
    assert r.status_code == 201
    data = r.json()
    assert data["is_active"] is True
    assert data["slug"] == slug


# ---------------------------------------------------------------------------
# 3. Duplicate slug → 400
# ---------------------------------------------------------------------------
async def test_create_school_duplicate_slug(client: AsyncClient, padmin_token: str):
    slug = f"dupsch-{uid()}"
    payload = {
        "name": "Dup School",
        "slug": slug,
        "admin_username": f"adm-{uid()}",
        "admin_password": "Pass1234!",
    }
    r1 = await client.post("/platform/schools", json=payload, headers=auth(padmin_token))
    assert r1.status_code == 201

    # Second call reuses the same slug with a different admin username
    payload["admin_username"] = f"adm-{uid()}"
    r2 = await client.post("/platform/schools", json=payload, headers=auth(padmin_token))
    assert r2.status_code == 400


# ---------------------------------------------------------------------------
# 4. Get school by ID
# ---------------------------------------------------------------------------
async def test_get_school_by_id(client: AsyncClient, padmin_token: str, make_school):
    school, _token, _slug, _admin = await make_school("getbyid")
    school_id = school["id"]

    r = await client.get(f"/platform/schools/{school_id}", headers=auth(padmin_token))
    assert r.status_code == 200
    assert r.json()["id"] == school_id


# ---------------------------------------------------------------------------
# 5. Update school name
# ---------------------------------------------------------------------------
async def test_update_school(client: AsyncClient, padmin_token: str, make_school):
    school, _token, _slug, _admin = await make_school("update")
    school_id = school["id"]
    new_name = f"Updated Name {uid()}"

    r = await client.patch(
        f"/platform/schools/{school_id}",
        json={"name": new_name},
        headers=auth(padmin_token),
    )
    assert r.status_code == 200
    assert r.json()["name"] == new_name


# ---------------------------------------------------------------------------
# 6. Toggle activation — flips twice
# ---------------------------------------------------------------------------
async def test_toggle_activation(client: AsyncClient, padmin_token: str, make_school):
    school, _token, _slug, _admin = await make_school("toggle")
    school_id = school["id"]
    original_active = school["is_active"]  # True after creation

    r1 = await client.post(f"/platform/schools/{school_id}/activate", headers=auth(padmin_token))
    assert r1.status_code == 200
    assert r1.json()["is_active"] is not original_active

    r2 = await client.post(f"/platform/schools/{school_id}/activate", headers=auth(padmin_token))
    assert r2.status_code == 200
    assert r2.json()["is_active"] is original_active


# ---------------------------------------------------------------------------
# 7. Platform stats
# ---------------------------------------------------------------------------
async def test_platform_stats(client: AsyncClient, padmin_token: str):
    r = await client.get("/platform/stats", headers=auth(padmin_token))
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data["total_schools"], int)
    assert isinstance(data["active_schools"], int)
    assert isinstance(data["total_children"], int)
    assert isinstance(data["total_active_users"], int)


# ---------------------------------------------------------------------------
# 8. School-admin forbidden on platform routes
# ---------------------------------------------------------------------------
async def test_school_admin_forbidden_on_platform(client: AsyncClient, make_school):
    _school, admin_token, _slug, _admin = await make_school("forbid")

    r = await client.get("/platform/schools", headers=auth(admin_token))
    assert r.status_code == 403
