"""
Tests for /attendance/* endpoints.

Setup pattern: create a school, create a teacher employee (to satisfy
require_teacher), login as the teacher for checkin/checkout, and create
a child for per-child operations.

Note: checkin/checkout require the current user to have an associated
employee record, so those tests use the teacher token.  Bulk attendance
requires school_admin and uses the admin token.
"""
from datetime import date

import pytest
from httpx import AsyncClient

from tests.conftest import auth, login, uid


async def _setup_school_with_teacher(client: AsyncClient, make_school):
    """Create a school, a teacher employee, an admin employee, and a child."""
    school, admin_token, slug, _ = await make_school("att")

    teacher_username = f"teacher-{uid()}"
    emp_r = await client.post(
        "/employees",
        json={
            "first_name": "Att",
            "last_name": "Teacher",
            "employee_type": "teacher",
            "username": teacher_username,
            "password": "Teacher1!",
        },
        headers=auth(admin_token),
    )
    assert emp_r.status_code == 201, emp_r.text

    teacher_token = await login(client, teacher_username, "Teacher1!", slug)

    # Admin-type employee: role=school_admin AND has employee_id (needed for bulk)
    adm_emp_username = f"adminemp-{uid()}"
    adm_emp_r = await client.post(
        "/employees",
        json={
            "first_name": "Adm",
            "last_name": "Emp",
            "employee_type": "admin",
            "username": adm_emp_username,
            "password": "Admin1!",
        },
        headers=auth(admin_token),
    )
    assert adm_emp_r.status_code == 201, adm_emp_r.text
    admin_emp_token = await login(client, adm_emp_username, "Admin1!", slug)

    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Child", "last_name": "Att"},
        headers=auth(admin_token),
    )
    assert child_r.status_code == 201, child_r.text
    child_id = child_r.json()["id"]

    return {
        "admin_token": admin_token,
        "admin_emp_token": admin_emp_token,  # school_admin WITH employee_id
        "teacher_token": teacher_token,
        "child_id": child_id,
        "slug": slug,
    }


# ---------------------------------------------------------------------------
# 1. GET /attendance/today
# ---------------------------------------------------------------------------

async def test_today_attendance(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    r = await client.get("/attendance/today", headers=auth(ctx["teacher_token"]))
    assert r.status_code == 200
    data = r.json()
    assert "records" in data
    # The endpoint returns a TodayAttendanceResponse with records + summary
    assert isinstance(data["records"], list)


# ---------------------------------------------------------------------------
# 2. POST /attendance/checkin
# ---------------------------------------------------------------------------

async def test_checkin_child(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    r = await client.post(
        "/attendance/checkin",
        json={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_token"]),
    )
    assert r.status_code == 200


# ---------------------------------------------------------------------------
# 3. POST /attendance/checkout (after checkin)
# ---------------------------------------------------------------------------

async def test_checkout_child(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)

    ci = await client.post(
        "/attendance/checkin",
        json={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_token"]),
    )
    assert ci.status_code == 200

    co = await client.post(
        "/attendance/checkout",
        json={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_token"]),
    )
    assert co.status_code == 200


# ---------------------------------------------------------------------------
# 4. POST /attendance/bulk
# ---------------------------------------------------------------------------

async def test_bulk_attendance(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    today = date.today().isoformat()

    r = await client.post(
        "/attendance/bulk",
        json={
            "date": today,
            "records": [{"child_id": ctx["child_id"], "status": "present"}],
        },
        headers=auth(ctx["admin_emp_token"]),  # needs school_admin + employee_id
    )
    assert r.status_code == 200


# ---------------------------------------------------------------------------
# 5. GET /attendance/summary
# ---------------------------------------------------------------------------

async def test_attendance_summary(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    # summary requires a ?month=YYYY-MM query parameter
    month = date.today().strftime("%Y-%m")
    r = await client.get(
        f"/attendance/summary?month={month}",
        headers=auth(ctx["teacher_token"]),
    )
    assert r.status_code == 200


# ---------------------------------------------------------------------------
# 6. GET /attendance/child/{child_id}
# ---------------------------------------------------------------------------

async def test_child_attendance_history(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    r = await client.get(
        f"/attendance/child/{ctx['child_id']}",
        headers=auth(ctx["teacher_token"]),
    )
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# ---------------------------------------------------------------------------
# 7. POST /attendance/bulk without 'date' field → 422
# ---------------------------------------------------------------------------

async def test_bulk_requires_date_field(client: AsyncClient, make_school):
    ctx = await _setup_school_with_teacher(client, make_school)
    r = await client.post(
        "/attendance/bulk",
        json={"records": [{"child_id": ctx["child_id"], "status": "present"}]},
        headers=auth(ctx["admin_token"]),
    )
    assert r.status_code == 422


# ---------------------------------------------------------------------------
# 8. No auth → 401 or 403
# ---------------------------------------------------------------------------

async def test_attendance_requires_auth(client: AsyncClient):
    r = await client.get("/attendance/today")
    assert r.status_code in (401, 403)
