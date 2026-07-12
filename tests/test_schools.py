"""
Tests for /schools/* endpoints (school-admin scope).
"""
import struct
import zlib

from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _minimal_png() -> bytes:
    """Return a valid 1×1 white pixel PNG (used for logo upload tests)."""
    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    header = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b"IDAT", zlib.compress(b"\x00\xFF\xFF\xFF"))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend


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


# ---------------------------------------------------------------------------
# 7. GET /schools/info — accessible to any authenticated user
# ---------------------------------------------------------------------------

async def _make_school_with_teacher(client, make_school, prefix):
    school, admin_token, slug, _ = await make_school(prefix)
    teacher_username = f"t-{uid()}"
    r = await client.post(
        "/employees",
        json={
            "first_name": "Info",
            "last_name": "Teacher",
            "employee_type": "teacher",
            "username": teacher_username,
            "password": "Teacher1!",
        },
        headers=auth(admin_token),
    )
    assert r.status_code == 201, r.text
    teacher_token = await login(client, teacher_username, "Teacher1!", slug)
    return school, admin_token, teacher_token, slug


async def _make_school_with_parent(client, make_school, prefix):
    school, admin_token, slug, _ = await make_school(prefix)
    parent_username = f"p-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={
            "first_name": "Info",
            "last_name": "Parent",
            "username": parent_username,
            "password": "Parent1!",
        },
        headers=auth(admin_token),
    )
    assert grd_r.status_code == 201, grd_r.text
    parent_token = await login(client, parent_username, "Parent1!", slug)
    return school, admin_token, parent_token, slug


async def test_get_school_info_as_admin(client: AsyncClient, make_school):
    """Admin can call GET /schools/info."""
    _school, token, _slug, _admin = await make_school("info-adm")
    r = await client.get("/schools/info", headers=auth(token))
    assert r.status_code == 200
    data = r.json()
    assert "name" in data
    assert "currency" in data


async def test_get_school_info_as_teacher(client: AsyncClient, make_school):
    """Teacher (non-admin) can also call GET /schools/info."""
    _school, _admin_tok, teacher_tok, _slug = await _make_school_with_teacher(
        client, make_school, "info-tch"
    )
    r = await client.get("/schools/info", headers=auth(teacher_tok))
    assert r.status_code == 200
    assert "currency" in r.json()


async def test_get_school_info_as_parent(client: AsyncClient, make_school):
    """Parent can also call GET /schools/info."""
    _school, _admin_tok, parent_tok, _slug = await _make_school_with_parent(
        client, make_school, "info-par"
    )
    r = await client.get("/schools/info", headers=auth(parent_tok))
    assert r.status_code == 200
    assert "currency" in r.json()


# ---------------------------------------------------------------------------
# 8. Currency field
# ---------------------------------------------------------------------------

async def test_school_currency_defaults_to_aoa(client: AsyncClient, make_school):
    """A newly created school has currency=AOA."""
    _school, token, _slug, _admin = await make_school("cur-def")
    r = await client.get("/schools/me", headers=auth(token))
    assert r.status_code == 200
    assert r.json()["currency"] == "AOA"


async def test_update_school_currency(client: AsyncClient, make_school):
    """Admin can change the school's currency via PATCH /schools/me."""
    _school, token, _slug, _admin = await make_school("cur-upd")
    r = await client.patch("/schools/me", json={"currency": "USD"}, headers=auth(token))
    assert r.status_code == 200
    assert r.json()["currency"] == "USD"

    # Verify it persists
    r2 = await client.get("/schools/me", headers=auth(token))
    assert r2.json()["currency"] == "USD"


# ---------------------------------------------------------------------------
# 9. POST /schools/logo — logo upload
# ---------------------------------------------------------------------------

async def test_upload_school_logo(client: AsyncClient, make_school):
    """Admin can upload a PNG logo; logo_url is updated in the response."""
    _school, token, _slug, _admin = await make_school("logo-up")
    png_bytes = _minimal_png()
    r = await client.post(
        "/schools/logo",
        files={"file": ("logo.png", png_bytes, "image/png")},
        headers=auth(token),
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["logo_url"] is not None
    assert "schools" in data["logo_url"]


async def test_upload_school_logo_invalid_type(client: AsyncClient, make_school):
    """Uploading a non-image (PDF) as a school logo is rejected."""
    _school, token, _slug, _admin = await make_school("logo-bad")
    r = await client.post(
        "/schools/logo",
        files={"file": ("doc.pdf", b"%PDF-1.4 fake", "application/pdf")},
        headers=auth(token),
    )
    assert r.status_code == 400


async def test_upload_school_logo_requires_admin(client: AsyncClient, make_school):
    """A teacher cannot upload a school logo."""
    _school, _admin_tok, teacher_tok, _slug = await _make_school_with_teacher(
        client, make_school, "logo-auth"
    )
    png_bytes = _minimal_png()
    r = await client.post(
        "/schools/logo",
        files={"file": ("logo.png", png_bytes, "image/png")},
        headers=auth(teacher_tok),
    )
    assert r.status_code == 403
