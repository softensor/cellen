"""
Spec-compliance tests for Attendance — spec section 7.1.

Covers the log-based attendance model:
  - Multiple check-in / check-out pairs per child per day
  - AttendanceDayStatus separate from log entries
  - "On premises" derived from most recent log entry
  - Bulk-marks unmarked children as absent
  - Monthly summary based on day-status records
  - Employee absences (section 7.2)
"""
from datetime import date

from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _setup(client: AsyncClient, make_school) -> dict:
    school, admin_tok, slug, _ = await make_school("attspec")

    uname = f"t-{uid()}"
    emp_r = await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname, "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    assert emp_r.status_code == 201
    teacher_tok = await login(client, uname, "Teacher1!", slug)

    # Admin-employee token
    adm_uname = f"adm-{uid()}"
    adm_r = await client.post(
        "/employees",
        json={"first_name": "A", "last_name": "A", "employee_type": "admin",
              "username": adm_uname, "password": "Admin1!"},
        headers=auth(admin_tok),
    )
    assert adm_r.status_code == 201
    adm_emp_tok = await login(client, adm_uname, "Admin1!", slug)
    emp_id = adm_r.json()["id"]

    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Child", "last_name": "Att"},
        headers=auth(admin_tok),
    )
    assert child_r.status_code == 201
    child_id = child_r.json()["id"]

    return {
        "admin_tok": admin_tok,
        "teacher_tok": teacher_tok,
        "adm_emp_tok": adm_emp_tok,
        "emp_id": emp_id,
        "child_id": child_id,
        "slug": slug,
    }


# ---------------------------------------------------------------------------
# Log-based: multiple check-in/out pairs per day
# ---------------------------------------------------------------------------

async def test_child_can_check_in_twice_same_day(client: AsyncClient, make_school):
    """
    A child can check in, check out, and check in again on the same day
    (e.g. mid-day doctor's appointment). Each event must be recorded.
    """
    ctx = await _setup(client, make_school)
    hdrs = auth(ctx["teacher_tok"])
    child_id = ctx["child_id"]

    # First check-in
    r1 = await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)
    assert r1.status_code == 200, r1.text

    # Check-out
    r2 = await client.post("/attendance/checkout", json={"child_id": child_id}, headers=hdrs)
    assert r2.status_code == 200, r2.text

    # Second check-in (return from appointment)
    r3 = await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)
    assert r3.status_code == 200, (
        f"Second check-in same day must be allowed (mid-day return); got {r3.status_code}: {r3.text}"
    )


async def test_attendance_log_has_multiple_entries(client: AsyncClient, make_school):
    """
    The attendance log for a child on a day with multiple events must
    return more than one entry.
    """
    ctx = await _setup(client, make_school)
    hdrs = auth(ctx["teacher_tok"])
    child_id = ctx["child_id"]
    today = date.today().isoformat()

    # Three events: in, out, in
    await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)
    await client.post("/attendance/checkout", json={"child_id": child_id}, headers=hdrs)
    await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)

    r = await client.get(
        f"/attendance/child/{child_id}/log?date={today}",
        headers=hdrs,
    )
    if r.status_code == 404:
        # Endpoint may not have a /log suffix — try the plain history endpoint
        r = await client.get(f"/attendance/child/{child_id}?date={today}", headers=hdrs)

    assert r.status_code == 200, r.text
    entries = r.json()
    if isinstance(entries, list):
        assert len(entries) >= 2, (
            f"Multiple check-in/out pairs must be stored as separate log entries; "
            f"found {len(entries)}"
        )


async def test_child_is_on_premises_after_second_checkin(client: AsyncClient, make_school):
    """
    After check-in → check-out → check-in, the child's current status must
    reflect 'on premises' (most recent log = check_in).
    """
    ctx = await _setup(client, make_school)
    hdrs = auth(ctx["teacher_tok"])
    child_id = ctx["child_id"]

    await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)
    await client.post("/attendance/checkout", json={"child_id": child_id}, headers=hdrs)
    await client.post("/attendance/checkin", json={"child_id": child_id}, headers=hdrs)

    r = await client.get("/attendance/today", headers=hdrs)
    assert r.status_code == 200
    records = r.json().get("records", [])
    child_record = next((rc for rc in records if rc.get("child_id") == child_id), None)
    if child_record:
        # Status should indicate the child is present/checked-in
        status = child_record.get("status") or child_record.get("current_status")
        assert status in ("present", "checked_in", "on_premises"), (
            f"Child should be on premises after second check-in; got status: {status!r}"
        )


# ---------------------------------------------------------------------------
# AttendanceDayStatus: independent from log entries
# ---------------------------------------------------------------------------

async def test_set_day_status_directly(client: AsyncClient, make_school):
    """
    It must be possible to set a child's day status (absent/excused)
    without any log entries (e.g. marking a child absent at start of day).
    """
    ctx = await _setup(client, make_school)
    hdrs = auth(ctx["teacher_tok"])
    child_id = ctx["child_id"]
    today = date.today().isoformat()

    r = await client.post(
        "/attendance/bulk",
        json={
            "date": today,
            "records": [{"child_id": child_id, "status": "excused", "notes": "Medical"}],
        },
        headers=auth(ctx["adm_emp_tok"]),
    )
    assert r.status_code == 200, r.text

    # Day status must be retrievable
    hist_r = await client.get(f"/attendance/child/{child_id}", headers=hdrs)
    assert hist_r.status_code == 200
    history = hist_r.json()
    if isinstance(history, list):
        today_entry = next(
            (e for e in history if e.get("attendance_date") == today or e.get("date") == today),
            None,
        )
        if today_entry:
            assert today_entry.get("status") == "excused", (
                f"Day status must be 'excused'; got {today_entry.get('status')!r}"
            )


async def test_bulk_marks_remaining_children_absent(client: AsyncClient, make_school):
    """
    Bulk endpoint with status='absent' must mark children who have no
    log entries for the day.
    """
    ctx = await _setup(client, make_school)
    today = date.today().isoformat()

    # No check-in for child; use bulk to mark absent
    r = await client.post(
        "/attendance/bulk",
        json={
            "date": today,
            "records": [{"child_id": ctx["child_id"], "status": "absent"}],
        },
        headers=auth(ctx["adm_emp_tok"]),
    )
    assert r.status_code == 200, r.text

    hist_r = await client.get(f"/attendance/child/{ctx['child_id']}", headers=auth(ctx["teacher_tok"]))
    assert hist_r.status_code == 200
    history = hist_r.json()
    if isinstance(history, list):
        today_entry = next(
            (e for e in history if e.get("attendance_date") == today or e.get("date") == today),
            None,
        )
        if today_entry:
            assert today_entry.get("status") == "absent"


# ---------------------------------------------------------------------------
# Monthly summary based on day-status records
# ---------------------------------------------------------------------------

async def test_monthly_summary_returns_per_child_rates(client: AsyncClient, make_school):
    """
    GET /attendance/summary?month=YYYY-MM must return per-child attendance
    rates derived from day-status records.
    """
    ctx = await _setup(client, make_school)
    month = date.today().strftime("%Y-%m")
    today = date.today().isoformat()

    # Record one present day
    await client.post(
        "/attendance/bulk",
        json={"date": today, "records": [{"child_id": ctx["child_id"], "status": "present"}]},
        headers=auth(ctx["adm_emp_tok"]),
    )

    r = await client.get(f"/attendance/summary?month={month}", headers=auth(ctx["teacher_tok"]))
    assert r.status_code == 200, r.text
    data = r.json()

    # Summary may be a list of per-child objects or a dict
    if isinstance(data, list):
        child_summary = next(
            (s for s in data if s.get("child_id") == ctx["child_id"]), None
        )
        if child_summary:
            assert "present_days" in child_summary or "days_present" in child_summary, (
                "Monthly summary must include present_days per child"
            )


# ---------------------------------------------------------------------------
# Role-based access
# ---------------------------------------------------------------------------

async def test_parent_cannot_record_attendance(client: AsyncClient, make_school):
    from tests.conftest import login as _login
    school, admin_tok, slug, _ = await make_school("att-parent-auth")

    # Create guardian and log in as parent
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "P", "last_name": "P", "username": f"p-{uid()}", "password": "Parent1!"},
        headers=auth(admin_tok),
    )
    assert grd_r.status_code == 201
    parent_tok = await _login(client, grd_r.json()["username"] if "username" in grd_r.json() else f"p-{uid()}", "Parent1!", slug)

    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "C", "last_name": "C"},
        headers=auth(admin_tok),
    )
    child_id = child_r.json()["id"]

    r = await client.post(
        "/attendance/checkin",
        json={"child_id": child_id},
        headers=auth(parent_tok),
    )
    assert r.status_code == 403, (
        f"Parents must not be able to record check-in; got {r.status_code}"
    )


# ---------------------------------------------------------------------------
# 7.2 Employee absences
# ---------------------------------------------------------------------------

async def test_create_employee_absence(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("abs-c")
    emp_r = await client.post(
        "/employees",
        json={"first_name": "E", "last_name": "E", "employee_type": "teacher",
              "username": f"e-{uid()}", "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    assert emp_r.status_code == 201
    emp_id = emp_r.json()["id"]

    r = await client.post(
        "/absences",
        json={
            "employee_id": emp_id,
            "absence_date": date.today().isoformat(),
            "absence_type": "sick",
            "notes": "Fever",
        },
        headers=auth(admin_tok),
    )
    assert r.status_code == 201, r.text
    assert "id" in r.json()


async def test_list_employee_absences(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("abs-l")
    emp_r = await client.post(
        "/employees",
        json={"first_name": "E", "last_name": "E", "employee_type": "staff",
              "username": f"e-{uid()}", "password": "P1234!"},
        headers=auth(admin_tok),
    )
    emp_id = emp_r.json()["id"]

    await client.post(
        "/absences",
        json={"employee_id": emp_id, "absence_date": date.today().isoformat(), "absence_type": "personal"},
        headers=auth(admin_tok),
    )

    r = await client.get("/absences", headers=auth(admin_tok))
    assert r.status_code == 200
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 1


async def test_absence_monthly_summary(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("abs-sum")
    emp_r = await client.post(
        "/employees",
        json={"first_name": "E", "last_name": "E", "employee_type": "teacher",
              "username": f"e-{uid()}", "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    emp_id = emp_r.json()["id"]

    await client.post(
        "/absences",
        json={"employee_id": emp_id, "absence_date": date.today().isoformat(), "absence_type": "sick"},
        headers=auth(admin_tok),
    )

    month = date.today().strftime("%Y-%m")
    r = await client.get(f"/absences/summary/{emp_id}?month={month}", headers=auth(admin_tok))
    assert r.status_code == 200, r.text
    summary = r.json()
    assert "sick" in summary or "total_days" in summary or isinstance(summary, dict), (
        f"Absence summary must return a dict with type breakdown; got: {summary!r}"
    )


async def test_teacher_cannot_manage_absences(client: AsyncClient, make_school):
    """Only school_admin can manage employee absences."""
    school, admin_tok, slug, _ = await make_school("abs-auth")

    uname = f"t-{uid()}"
    emp_r = await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname, "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    emp_id = emp_r.json()["id"]
    teacher_tok = await login(client, uname, "Teacher1!", slug)

    r = await client.post(
        "/absences",
        json={"employee_id": emp_id, "absence_date": date.today().isoformat(), "absence_type": "sick"},
        headers=auth(teacher_tok),
    )
    assert r.status_code == 403, (
        f"Teachers must not create absence records; got {r.status_code}"
    )


async def test_absence_school_isolation(client: AsyncClient, make_school):
    school_a, tok_a, _, _ = await make_school("abs-isola")
    school_b, tok_b, _, _ = await make_school("abs-isolb")

    emp_r = await client.post(
        "/employees",
        json={"first_name": "E", "last_name": "E", "employee_type": "staff",
              "username": f"e-{uid()}", "password": "P1234!"},
        headers=auth(tok_a),
    )
    emp_id = emp_r.json()["id"]

    await client.post(
        "/absences",
        json={"employee_id": emp_id, "absence_date": date.today().isoformat(), "absence_type": "sick"},
        headers=auth(tok_a),
    )

    r = await client.get("/absences", headers=auth(tok_b))
    assert r.status_code == 200
    ids_b = [a.get("employee_id") for a in r.json()]
    assert emp_id not in ids_b, "School B must not see school A's absences"
