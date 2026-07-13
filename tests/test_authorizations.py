"""
Tests for Authorization modules — spec sections 16.1 and 16.2.

Covers:
  - UC-PA1–PA3: Pickup authorizations CRUD
  - UC-TA1–TA4: Trip authorization workflow (create → parent responds)
  - Role restrictions: parent responds, admin/teacher manages
  - School isolation
  - Response finality (cannot change after response)
"""
from datetime import date, timedelta

from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _setup(client: AsyncClient, make_school, prefix="auth") -> dict:
    school, admin_tok, slug, _ = await make_school(prefix)
    hdrs = auth(admin_tok)

    # Teacher
    uname_t = f"t-{uid()}"
    emp_r = await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname_t, "password": "Teacher1!"},
        headers=hdrs,
    )
    assert emp_r.status_code == 201
    teacher_tok = await login(client, uname_t, "Teacher1!", slug)

    # Child
    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Kid", "last_name": "Auth"},
        headers=hdrs,
    )
    assert child_r.status_code == 201
    child_id = child_r.json()["id"]

    # Guardian (linked to child)
    uname_p = f"p-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "Parent", "last_name": "Auth", "username": uname_p, "password": "Parent1!"},
        headers=hdrs,
    )
    assert grd_r.status_code == 201
    guardian_id = grd_r.json()["id"]

    link_r = await client.post(
        f"/guardians/{guardian_id}/children",
        json={"child_id": child_id, "relationship_type": "mother", "is_primary_contact": True},
        headers=hdrs,
    )
    assert link_r.status_code in (200, 201)

    parent_tok = await login(client, uname_p, "Parent1!", slug)

    return {
        "admin_tok": admin_tok, "hdrs": hdrs,
        "teacher_tok": teacher_tok,
        "parent_tok": parent_tok,
        "child_id": child_id,
        "guardian_id": guardian_id,
        "slug": slug,
    }


# ============================================================================
# 16.1 PICKUP AUTHORIZATIONS
# ============================================================================

async def test_create_pickup_authorization(client: AsyncClient, make_school):
    """Admin or parent can add an authorized pickup person for a child."""
    ctx = await _setup(client, make_school, "pa-c")

    r = await client.post(
        "/pickup-authorizations",
        json={
            "child_id": ctx["child_id"],
            "authorized_person_name": "Avó Maria",
            "mobile": "923456789",
            "relationship": "grandmother",
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["authorized_person_name"] == "Avó Maria"
    assert body["mobile"] == "923456789"
    assert "id" in body


async def test_list_pickup_authorizations(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "pa-l")

    await client.post(
        "/pickup-authorizations",
        json={"child_id": ctx["child_id"], "authorized_person_name": "Tio João",
              "mobile": "912345678", "relationship": "uncle"},
        headers=ctx["hdrs"],
    )

    r = await client.get("/pickup-authorizations", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 1


async def test_update_pickup_authorization(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "pa-u")

    pa_r = await client.post(
        "/pickup-authorizations",
        json={"child_id": ctx["child_id"], "authorized_person_name": "Old Name",
              "mobile": "900000000", "relationship": "other"},
        headers=ctx["hdrs"],
    )
    assert pa_r.status_code == 201
    pa_id = pa_r.json()["id"]

    r = await client.patch(
        f"/pickup-authorizations/{pa_id}",
        json={"authorized_person_name": "Updated Name"},
        headers=ctx["hdrs"],
    )
    assert r.status_code == 200, r.text
    assert r.json()["authorized_person_name"] == "Updated Name"


async def test_delete_pickup_authorization(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "pa-d")

    pa_r = await client.post(
        "/pickup-authorizations",
        json={"child_id": ctx["child_id"], "authorized_person_name": "Delete Me",
              "mobile": "911111111", "relationship": "other"},
        headers=ctx["hdrs"],
    )
    assert pa_r.status_code == 201
    pa_id = pa_r.json()["id"]

    del_r = await client.delete(f"/pickup-authorizations/{pa_id}", headers=ctx["hdrs"])
    assert del_r.status_code == 200, del_r.text


async def test_multiple_pickup_persons_per_child(client: AsyncClient, make_school):
    """A child can have multiple authorized pickup persons."""
    ctx = await _setup(client, make_school, "pa-multi")

    for name in ["Avó Ana", "Tio Pedro", "Vizinha Clara"]:
        r = await client.post(
            "/pickup-authorizations",
            json={"child_id": ctx["child_id"], "authorized_person_name": name,
                  "mobile": f"9{uid()[:8]}", "relationship": "other"},
            headers=ctx["hdrs"],
        )
        assert r.status_code == 201, r.text

    r = await client.get("/pickup-authorizations", headers=ctx["hdrs"])
    assert r.status_code == 200
    count = sum(1 for pa in r.json() if pa.get("child_id") == ctx["child_id"])
    assert count >= 3, f"Must have at least 3 pickup persons; found {count}"


async def test_teacher_can_view_pickup_authorizations(client: AsyncClient, make_school):
    """Teachers can view authorized pickup persons."""
    ctx = await _setup(client, make_school, "pa-t")

    await client.post(
        "/pickup-authorizations",
        json={"child_id": ctx["child_id"], "authorized_person_name": "Viewable",
              "mobile": "922222222", "relationship": "other"},
        headers=ctx["hdrs"],
    )

    r = await client.get("/pickup-authorizations", headers=auth(ctx["teacher_tok"]))
    assert r.status_code == 200, (
        f"Teachers must be able to view pickup authorizations; got {r.status_code}"
    )


async def test_pickup_authorization_school_isolation(client: AsyncClient, make_school):
    ctx_a = await _setup(client, make_school, "pa-isola")
    ctx_b = await _setup(client, make_school, "pa-isolb")

    pa_r = await client.post(
        "/pickup-authorizations",
        json={"child_id": ctx_a["child_id"], "authorized_person_name": "School A Person",
              "mobile": "933333333", "relationship": "other"},
        headers=ctx_a["hdrs"],
    )
    pa_id = pa_r.json()["id"]

    r = await client.get("/pickup-authorizations", headers=ctx_b["hdrs"])
    ids_b = [pa["id"] for pa in r.json()]
    assert pa_id not in ids_b


# ============================================================================
# 16.2 TRIP AUTHORIZATIONS
# ============================================================================

async def test_admin_creates_trip_authorization(client: AsyncClient, make_school):
    """Admin creates a trip authorization request for a child."""
    ctx = await _setup(client, make_school, "ta-c")
    trip_date = (date.today() + timedelta(days=7)).isoformat()

    r = await client.post(
        "/trip-authorizations",
        json={
            "child_id": ctx["child_id"],
            "destination": "Museu Nacional de Angola",
            "trip_date": trip_date,
            "description": "Visita de estudo ao museu",
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["destination"] == "Museu Nacional de Angola"
    assert body.get("parent_response") in (None, "pending"), (
        f"New trip must be pending; got: {body.get('parent_response')}"
    )


async def test_trip_starts_as_pending(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ta-pend")
    trip_date = (date.today() + timedelta(days=5)).isoformat()

    r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Zoo", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201
    assert r.json().get("parent_response") in (None, "pending")


async def test_parent_can_approve_trip(client: AsyncClient, make_school):
    """UC-TA2: Parent approves a trip authorization."""
    ctx = await _setup(client, make_school, "ta-appr")
    trip_date = (date.today() + timedelta(days=3)).isoformat()

    trip_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Beach Trip", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    assert trip_r.status_code == 201
    trip_id = trip_r.json()["id"]

    r = await client.post(
        f"/trip-authorizations/{trip_id}/respond",
        json={"response": "approved"},
        headers=auth(ctx["parent_tok"]),
    )
    assert r.status_code == 200, (
        f"Parent must be able to approve a trip; got {r.status_code}: {r.text}"
    )
    body = r.json()
    assert body["parent_response"] == "approved"
    assert body.get("response_date") is not None


async def test_parent_can_deny_trip(client: AsyncClient, make_school):
    """Parent denies a trip authorization."""
    ctx = await _setup(client, make_school, "ta-deny")
    trip_date = (date.today() + timedelta(days=4)).isoformat()

    trip_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Farm Visit", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    trip_id = trip_r.json()["id"]

    r = await client.post(
        f"/trip-authorizations/{trip_id}/respond",
        json={"response": "denied"},
        headers=auth(ctx["parent_tok"]),
    )
    assert r.status_code == 200, r.text
    assert r.json()["parent_response"] == "denied"


async def test_trip_response_is_final(client: AsyncClient, make_school):
    """Once a parent has responded, they cannot change their answer."""
    ctx = await _setup(client, make_school, "ta-final")
    trip_date = (date.today() + timedelta(days=6)).isoformat()

    trip_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Park", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    trip_id = trip_r.json()["id"]

    # First response: approve
    r1 = await client.post(
        f"/trip-authorizations/{trip_id}/respond",
        json={"response": "approved"},
        headers=auth(ctx["parent_tok"]),
    )
    assert r1.status_code == 200

    # Second response: try to change to denied
    r2 = await client.post(
        f"/trip-authorizations/{trip_id}/respond",
        json={"response": "denied"},
        headers=auth(ctx["parent_tok"]),
    )
    assert r2.status_code in (400, 409, 422), (
        f"Trip response must be final — changing it must be rejected; got {r2.status_code}"
    )


async def test_unrelated_parent_cannot_respond_to_trip(client: AsyncClient, make_school):
    """A parent can only respond to trip requests for their own children."""
    ctx = await _setup(client, make_school, "ta-other-par")
    trip_date = (date.today() + timedelta(days=2)).isoformat()

    # Create a trip for child in ctx
    trip_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Museum", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    trip_id = trip_r.json()["id"]

    # Create a second, unrelated guardian
    uname2 = f"p2-{uid()}"
    grd2_r = await client.post(
        "/guardians",
        json={"first_name": "Other", "last_name": "Parent", "username": uname2, "password": "Parent1!"},
        headers=ctx["hdrs"],
    )
    assert grd2_r.status_code == 201
    other_parent_tok = await login(client, uname2, "Parent1!", ctx["slug"])

    r = await client.post(
        f"/trip-authorizations/{trip_id}/respond",
        json={"response": "approved"},
        headers=auth(other_parent_tok),
    )
    assert r.status_code in (403, 404), (
        f"Unrelated parent must not be able to respond to another child's trip; got {r.status_code}"
    )


async def test_admin_can_cancel_pending_trip(client: AsyncClient, make_school):
    """UC-TA4: Admin can cancel a pending trip authorization."""
    ctx = await _setup(client, make_school, "ta-cancel")
    trip_date = (date.today() + timedelta(days=8)).isoformat()

    trip_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Science Fair", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )
    trip_id = trip_r.json()["id"]

    r = await client.delete(f"/trip-authorizations/{trip_id}", headers=ctx["hdrs"])
    assert r.status_code in (200, 204), r.text


async def test_list_trip_authorizations(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ta-l")
    trip_date = (date.today() + timedelta(days=9)).isoformat()

    await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Aquarium", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )

    r = await client.get("/trip-authorizations", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 1


async def test_trip_school_isolation(client: AsyncClient, make_school):
    ctx_a = await _setup(client, make_school, "ta-isola")
    ctx_b = await _setup(client, make_school, "ta-isolb")
    trip_date = (date.today() + timedelta(days=10)).isoformat()

    ta_r = await client.post(
        "/trip-authorizations",
        json={"child_id": ctx_a["child_id"], "destination": "School A trip", "trip_date": trip_date},
        headers=ctx_a["hdrs"],
    )
    ta_id = ta_r.json()["id"]

    r = await client.get("/trip-authorizations", headers=ctx_b["hdrs"])
    ids_b = [t["id"] for t in r.json()]
    assert ta_id not in ids_b


async def test_teacher_can_view_trip_authorizations(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ta-tv")
    trip_date = (date.today() + timedelta(days=5)).isoformat()

    await client.post(
        "/trip-authorizations",
        json={"child_id": ctx["child_id"], "destination": "Library", "trip_date": trip_date},
        headers=ctx["hdrs"],
    )

    r = await client.get("/trip-authorizations", headers=auth(ctx["teacher_tok"]))
    assert r.status_code == 200, (
        f"Teacher must be able to view trip authorizations; got {r.status_code}"
    )
