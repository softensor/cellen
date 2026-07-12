"""
Tests for /schools/* endpoints (school-admin scope).
"""
from httpx import AsyncClient

from tests.conftest import auth, uid


# ---------------------------------------------------------------------------
# 1. GET /schools/me — returns school info
# ---------------------------------------------------------------------------
async def test_get_school_me(client: AsyncClient, make_school):
    school, token, slug, _admin = await make_school("sme")

    r = await client.get("/schools/me", headers=auth(token))
    assert r.status_code == 200
    data = r.json()
    assert "name" in data
    assert "slug" in data
    assert data["slug"] == slug


# ---------------------------------------------------------------------------
# 2. PATCH /schools/me — update city
# ---------------------------------------------------------------------------
async def test_update_school_me(client: AsyncClient, make_school):
    _school, token, _slug, _admin = await make_school("upd")

    r = await client.patch(
        "/schools/me",
        json={"city": "Luanda"},
        headers=auth(token),
    )
    assert r.status_code == 200
    assert r.json()["city"] == "Luanda"


# ---------------------------------------------------------------------------
# 3. Fresh school → GET /schools/school-years → empty list
# ---------------------------------------------------------------------------
async def test_list_school_years_empty(client: AsyncClient, make_school):
    _school, token, _slug, _admin = await make_school("sye")

    r = await client.get("/schools/school-years", headers=auth(token))
    assert r.status_code == 200
    assert r.json() == []


# ---------------------------------------------------------------------------
# 4. Create school year → 201, is_active==False (default), label matches
# ---------------------------------------------------------------------------
async def test_create_school_year(client: AsyncClient, make_school):
    _school, token, _slug, _admin = await make_school("syc")

    r = await client.post(
        "/schools/school-years",
        json={
            "year_label": "2025/2026",
            "start_date": "2025-09-01",
            "end_date": "2026-07-31",
        },
        headers=auth(token),
    )
    assert r.status_code == 201
    data = r.json()
    assert data["year_label"] == "2025/2026"
    assert data["is_active"] is False


# ---------------------------------------------------------------------------
# 5. Activate school year — second year becomes active, first is not
# ---------------------------------------------------------------------------
async def test_activate_school_year(client: AsyncClient, make_school):
    _school, token, _slug, _admin = await make_school("syact")

    # Create year 1
    r1 = await client.post(
        "/schools/school-years",
        json={"year_label": "2024/2025", "start_date": "2024-09-01", "end_date": "2025-07-31"},
        headers=auth(token),
    )
    assert r1.status_code == 201
    year1_id = r1.json()["id"]

    # Create year 2
    r2 = await client.post(
        "/schools/school-years",
        json={"year_label": "2025/2026", "start_date": "2025-09-01", "end_date": "2026-07-31"},
        headers=auth(token),
    )
    assert r2.status_code == 201
    year2_id = r2.json()["id"]

    # Activate year 2
    act_r = await client.post(f"/schools/school-years/{year2_id}/activate", headers=auth(token))
    assert act_r.status_code == 200

    # List years and verify only year 2 is active
    list_r = await client.get("/schools/school-years", headers=auth(token))
    assert list_r.status_code == 200
    years = {y["id"]: y for y in list_r.json()}

    assert years[year2_id]["is_active"] is True
    assert years[year1_id]["is_active"] is False


# ---------------------------------------------------------------------------
# 6. School year isolation — school A's years not visible to school B
# ---------------------------------------------------------------------------
async def test_school_year_isolation(client: AsyncClient, make_school):
    _school_a, token_a, _slug_a, _admin_a = await make_school("iso-a")
    _school_b, token_b, _slug_b, _admin_b = await make_school("iso-b")

    # Create a year in school A
    r = await client.post(
        "/schools/school-years",
        json={"year_label": "2025/2026", "start_date": "2025-09-01", "end_date": "2026-07-31"},
        headers=auth(token_a),
    )
    assert r.status_code == 201
    year_a_id = r.json()["id"]

    # School B should not see school A's year
    list_r = await client.get("/schools/school-years", headers=auth(token_b))
    assert list_r.status_code == 200
    year_ids_for_b = [y["id"] for y in list_r.json()]
    assert year_a_id not in year_ids_for_b
