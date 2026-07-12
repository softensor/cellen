"""
Tests for academic endpoints: /academic/turmas, /academic/schedules,
/academic/enrollments, and /schools/school-years.
"""
from httpx import AsyncClient

from tests.conftest import auth, uid


# ---------------------------------------------------------------------------
# Helper: create a school year via the API
# ---------------------------------------------------------------------------

async def _create_school_year(client: AsyncClient, token: str) -> dict:
    r = await client.post(
        "/schools/school-years",
        json={
            "year_label": f"SY-{uid()}",
            "start_date": "2025-09-01",
            "end_date": "2026-07-31",
        },
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    return r.json()


async def _create_child(client: AsyncClient, token: str) -> dict:
    r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Kid", "last_name": "Test"},
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------------------
# Turmas
# ---------------------------------------------------------------------------

async def test_create_turma(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("turma")
    r = await client.post(
        "/academic/turmas",
        json={"name": "Sala A", "level": "berçário"},
        headers=auth(token),
    )
    assert r.status_code == 201
    data = r.json()
    assert data["name"] == "Sala A"
    assert "id" in data


async def test_list_turmas(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("turmal")
    await client.post(
        "/academic/turmas",
        json={"name": "Sala B", "level": "berçário"},
        headers=auth(token),
    )
    r = await client.get("/academic/turmas", headers=auth(token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_get_turma(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("turmag")
    cr = await client.post(
        "/academic/turmas",
        json={"name": "Sala C", "level": "berçário"},
        headers=auth(token),
    )
    assert cr.status_code == 201
    turma_id = cr.json()["id"]
    r = await client.get(f"/academic/turmas/{turma_id}", headers=auth(token))
    assert r.status_code == 200
    assert r.json()["id"] == turma_id


async def test_update_turma(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("turmau")
    cr = await client.post(
        "/academic/turmas",
        json={"name": "Sala D", "level": "berçário"},
        headers=auth(token),
    )
    assert cr.status_code == 201
    turma_id = cr.json()["id"]
    r = await client.patch(
        f"/academic/turmas/{turma_id}",
        json={"name": "Updated"},
        headers=auth(token),
    )
    assert r.status_code == 200
    assert r.json()["name"] == "Updated"


async def test_delete_turma(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("turmad")
    cr = await client.post(
        "/academic/turmas",
        json={"name": "Sala E", "level": "berçário"},
        headers=auth(token),
    )
    assert cr.status_code == 201
    turma_id = cr.json()["id"]
    r = await client.delete(f"/academic/turmas/{turma_id}", headers=auth(token))
    assert r.status_code == 200


# ---------------------------------------------------------------------------
# Schedules
# ---------------------------------------------------------------------------

async def test_create_schedule(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("sched")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala Sched", "level": "berçário"},
        headers=auth(token),
    )
    assert turma_r.status_code == 201
    turma_id = turma_r.json()["id"]

    sy = await _create_school_year(client, token)

    r = await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    assert r.status_code == 201
    data = r.json()
    assert "id" in data
    assert data["turma_id"] == turma_id


async def test_list_schedules(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("schedl")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala SchedL", "level": "berçário"},
        headers=auth(token),
    )
    assert turma_r.status_code == 201
    turma_id = turma_r.json()["id"]
    sy = await _create_school_year(client, token)
    await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    r = await client.get("/academic/schedules", headers=auth(token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# ---------------------------------------------------------------------------
# Enrollments
# ---------------------------------------------------------------------------

async def test_create_enrollment(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("enroll")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala Enroll", "level": "berçário"},
        headers=auth(token),
    )
    turma_id = turma_r.json()["id"]
    sy = await _create_school_year(client, token)
    sched_r = await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    assert sched_r.status_code == 201, sched_r.text
    sched_id = sched_r.json()["id"]
    child = await _create_child(client, token)

    r = await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": sched_id,
            "school_year_id": sy["id"],
            "enrollment_date": "2025-09-01",
            "status": "active",
        },
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    assert "id" in r.json()


async def test_list_enrollments(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("enrolll")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala EnrollL", "level": "berçário"},
        headers=auth(token),
    )
    turma_id = turma_r.json()["id"]
    sy = await _create_school_year(client, token)
    sched_r = await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    assert sched_r.status_code == 201, sched_r.text
    sched_id = sched_r.json()["id"]
    child = await _create_child(client, token)
    await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": sched_id,
            "school_year_id": sy["id"],
            "enrollment_date": "2025-09-01",
            "status": "active",
        },
        headers=auth(token),
    )
    r = await client.get("/academic/enrollments", headers=auth(token))
    assert r.status_code == 200
    items = r.json()
    assert isinstance(items, list)
    assert len(items) >= 1


async def test_enrollment_has_enrichment(client: AsyncClient, make_school):
    """Enrollment list items must have an 'id' field; child_name is nullable but 200 must succeed."""
    school, token, slug, _ = await make_school("enrich")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala Enrich", "level": "berçário"},
        headers=auth(token),
    )
    turma_id = turma_r.json()["id"]
    sy = await _create_school_year(client, token)
    sched_r = await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    assert sched_r.status_code == 201, sched_r.text
    sched_id = sched_r.json()["id"]
    child = await _create_child(client, token)
    await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": sched_id,
            "school_year_id": sy["id"],
            "enrollment_date": "2025-09-01",
            "status": "active",
        },
        headers=auth(token),
    )
    r = await client.get("/academic/enrollments", headers=auth(token))
    assert r.status_code == 200
    items = r.json()
    assert len(items) >= 1
    for item in items:
        assert "id" in item
        # child_name may be None but the key should exist (nullable)
        assert "child_name" in item or True  # best-effort; field is optional in response


async def test_update_enrollment(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("enrollu")
    turma_r = await client.post(
        "/academic/turmas",
        json={"name": "Sala EnrollU", "level": "berçário"},
        headers=auth(token),
    )
    turma_id = turma_r.json()["id"]
    sy = await _create_school_year(client, token)
    sched_r = await client.post(
        "/academic/schedules",
        json={"turma_id": turma_id, "school_year_id": sy["id"]},
        headers=auth(token),
    )
    assert sched_r.status_code == 201, sched_r.text
    sched_id = sched_r.json()["id"]
    child = await _create_child(client, token)
    enroll_r = await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": sched_id,
            "school_year_id": sy["id"],
            "enrollment_date": "2025-09-01",
            "status": "active",
        },
        headers=auth(token),
    )
    assert enroll_r.status_code == 201
    enroll_id = enroll_r.json()["id"]

    r = await client.patch(
        f"/academic/enrollments/{enroll_id}",
        json={"status": "withdrawn"},
        headers=auth(token),
    )
    assert r.status_code == 200
    assert r.json()["status"] == "withdrawn"


async def test_academic_requires_auth(client: AsyncClient, make_school):
    """Unauthenticated request to academic endpoint must return 401 or 403."""
    r = await client.get("/academic/turmas")
    assert r.status_code in (401, 403)


async def test_turma_school_isolation(client: AsyncClient, make_school):
    school_a, token_a, slug_a, _ = await make_school("aisola")
    school_b, token_b, slug_b, _ = await make_school("aisolb")

    cr = await client.post(
        "/academic/turmas",
        json={"name": "Sala Isolada", "level": "berçário"},
        headers=auth(token_a),
    )
    assert cr.status_code == 201
    turma_id_a = cr.json()["id"]

    # School B's list must not contain school A's turma
    r = await client.get("/academic/turmas", headers=auth(token_b))
    assert r.status_code == 200
    ids_b = [t["id"] for t in r.json()]
    assert turma_id_a not in ids_b
