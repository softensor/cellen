"""
Tests for the /children endpoints.

Fixtures used (defined in conftest.py):
  client, make_school, auth, uid
"""
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ── helpers ───────────────────────────────────────────────────────────────────

async def _make_child(client: AsyncClient, admin_token: str, **overrides) -> dict:
    body = {
        "cedula": f"CDL{uid()}",
        "first_name": "Ana",
        "last_name": "Martins",
        **overrides,
    }
    r = await client.post("/children", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json()


async def _make_employee(client: AsyncClient, admin_token: str) -> dict:
    uname = f"emp-{uid()}"
    body = {
        "first_name": "Jorge",
        "last_name": "Silva",
        "employee_type": "teacher",
        "username": uname,
        "password": "Teacher1!",
    }
    r = await client.post("/employees", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    data = r.json()
    data["_username"] = uname
    return data


async def _make_guardian(client: AsyncClient, admin_token: str) -> tuple[dict, str]:
    """Returns (guardian_dict, username)."""
    uname = f"grd-{uid()}"
    body = {
        "first_name": "Maria",
        "last_name": "Costa",
        "username": uname,
        "password": "Parent1!",
        "nif": f"5{uid()[:8]}",
    }
    r = await client.post("/guardians", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json(), uname


async def _make_invoice(
    client: AsyncClient, admin_token: str, child_id: str, issued_by: str,
    guardian_id: str | None = None,
) -> dict:
    if guardian_id is None:
        # Create a guardian and link to child for billing
        grd, _ = await _make_guardian(client, admin_token)
        guardian_id = grd["id"]
        await client.post(
            f"/guardians/{guardian_id}/children",
            json={"child_id": child_id, "relationship_type": "mother", "is_primary_contact": True},
            headers=auth(admin_token),
        )
    body = {
        "billing_guardian_id": guardian_id,
        "child_id": child_id,
        "reference_month": "2025-01-01",
        "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 300.0}],
    }
    r = await client.post("/finance/invoices", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json()


# ── tests ─────────────────────────────────────────────────────────────────────

async def test_create_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    assert "id" in child
    assert child["is_active"] is True


async def test_list_children(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.get("/children", headers=auth(admin_tok))
    assert r.status_code == 200
    ids = [c["id"] for c in r.json()]
    assert child["id"] in ids


async def test_get_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.get(f"/children/{child['id']}", headers=auth(admin_tok))
    assert r.status_code == 200
    assert r.json()["id"] == child["id"]


async def test_update_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.patch(
        f"/children/{child['id']}",
        json={"first_name": "Updated"},
        headers=auth(admin_tok),
    )
    assert r.status_code == 200
    assert r.json()["first_name"] == "Updated"


async def test_soft_delete_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.delete(f"/children/{child['id']}", headers=auth(admin_tok))
    assert r.status_code == 200

    r_list = await client.get("/children", headers=auth(admin_tok))
    assert r_list.status_code == 200
    ids = [c["id"] for c in r_list.json()]
    assert child["id"] not in ids


async def test_child_height_is_number(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok, height=1.25)
    r = await client.get(f"/children/{child['id']}", headers=auth(admin_tok))
    assert r.status_code == 200
    height = r.json()["height"]
    assert isinstance(height, float), f"Expected float, got {type(height)}: {height!r}"


async def test_child_balance_is_number(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.get(f"/children/{child['id']}/balance", headers=auth(admin_tok))
    assert r.status_code == 200
    balance = r.json()["outstanding_balance"]
    assert isinstance(balance, (int, float)), (
        f"Expected numeric, got {type(balance)}: {balance!r}"
    )


async def test_child_invoices_empty(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.get(f"/children/{child['id']}/invoices", headers=auth(admin_tok))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_child_invoices_decimal_fields(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    emp = await _make_employee(client, admin_tok)
    await _make_invoice(client, admin_tok, child["id"], emp["id"])

    r = await client.get(f"/children/{child['id']}/invoices", headers=auth(admin_tok))
    assert r.status_code == 200
    invoices = r.json()
    assert len(invoices) >= 1
    inv = invoices[0]
    for field in ("gross_total", "amount_paid", "balance"):
        assert isinstance(inv[field], (int, float)), (
            f"{field} should be numeric, got {type(inv[field])}: {inv[field]!r}"
        )


async def test_child_cadernetas_empty_initially(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    r = await client.get(f"/children/{child['id']}/cadernetas", headers=auth(admin_tok))
    assert r.status_code == 200
    assert r.json() == []


async def test_child_cadernetas_after_create(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    emp = await _make_employee(client, admin_tok)

    cad_r = await client.post(
        "/cadernetas",
        json={
            "child_id": child["id"],
            "teacher_id": emp["id"],
            "report_date": "2025-03-15",
        },
        headers=auth(admin_tok),
    )
    assert cad_r.status_code == 201

    r = await client.get(f"/children/{child['id']}/cadernetas", headers=auth(admin_tok))
    assert r.status_code == 200
    assert len(r.json()) == 1


async def test_child_guardians(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    child = await _make_child(client, admin_tok)
    guardian, _ = await _make_guardian(client, admin_tok)

    link_r = await client.post(
        f"/guardians/{guardian['id']}/children",
        json={"child_id": child["id"], "relationship_type": "mother", "is_primary_contact": True},
        headers=auth(admin_tok),
    )
    assert link_r.status_code == 201

    r = await client.get(f"/children/{child['id']}/guardians", headers=auth(admin_tok))
    assert r.status_code == 200
    data = r.json()
    assert len(data) >= 1
    assert "relationship_type" in data[0]


async def test_school_isolation_child(client: AsyncClient, make_school):
    """Child created in school A must not be visible to school B admin."""
    _, admin_a, _, _ = await make_school("iso-a")
    _, admin_b, _, _ = await make_school("iso-b")

    child = await _make_child(client, admin_a)

    r = await client.get(f"/children/{child['id']}", headers=auth(admin_b))
    assert r.status_code == 404


async def test_teacher_can_list_children(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    emp = await _make_employee(client, admin_tok)
    teacher_tok = await login(client, emp["_username"], "Teacher1!", slug)

    r = await client.get("/children", headers=auth(teacher_tok))
    assert r.status_code == 200


async def test_teacher_cannot_create_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("ch")
    emp = await _make_employee(client, admin_tok)
    teacher_tok = await login(client, emp["_username"], "Teacher1!", slug)

    body = {"cedula": f"CDL{uid()}", "first_name": "X", "last_name": "Y"}
    r = await client.post("/children", json=body, headers=auth(teacher_tok))
    assert r.status_code == 403
