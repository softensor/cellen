"""
Tests for the /parent/* endpoints.

Fixtures used (defined in conftest.py):
  client, make_school, auth, uid
"""
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ── helpers ───────────────────────────────────────────────────────────────────

async def _make_child(client: AsyncClient, admin_token: str, **overrides) -> dict:
    body = {
        "cedula": f"CDL{uid()}",
        "first_name": "Pedro",
        "last_name": "Sousa",
        **overrides,
    }
    r = await client.post("/children", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json()


async def _make_employee(client: AsyncClient, admin_token: str) -> tuple[dict, str]:
    """Returns (employee_dict, username)."""
    uname = f"emp-{uid()}"
    body = {
        "first_name": "Diana",
        "last_name": "Lopes",
        "employee_type": "teacher",
        "username": uname,
        "password": "Teacher1!",
    }
    r = await client.post("/employees", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json(), uname


async def _make_guardian_and_login(
    client: AsyncClient, admin_token: str, slug: str
) -> tuple[dict, str]:
    """Creates a guardian, links nothing, returns (guardian_dict, parent_token)."""
    uname = f"grd-{uid()}"
    body = {
        "first_name": "Helena",
        "last_name": "Pires",
        "username": uname,
        "password": "Parent1!",
    }
    r = await client.post("/guardians", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    guardian = r.json()
    parent_tok = await login(client, uname, "Parent1!", slug)
    return guardian, parent_tok


async def _link_guardian_to_child(
    client: AsyncClient, admin_token: str, guardian_id: str, child_id: str
) -> None:
    r = await client.post(
        f"/guardians/{guardian_id}/children",
        json={"child_id": child_id, "relationship_type": "mother", "is_primary_contact": True},
        headers=auth(admin_token),
    )
    assert r.status_code == 201, r.text


async def _make_invoice(
    client: AsyncClient, admin_token: str, child_id: str, issued_by: str
) -> dict:
    body = {
        "child_id": child_id,
        "issued_by": issued_by,
        "reference_month": "2025-02-01",
        "tuition_amount": 250.0,
    }
    r = await client.post("/finance/invoices", json=body, headers=auth(admin_token))
    assert r.status_code == 201, r.text
    return r.json()


async def _make_caderneta(
    client: AsyncClient, token: str, child_id: str, teacher_id: str
) -> dict:
    r = await client.post(
        "/cadernetas",
        json={"child_id": child_id, "teacher_id": teacher_id, "report_date": "2025-04-10"},
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    return r.json()


# ── tests ─────────────────────────────────────────────────────────────────────

async def test_parent_children(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    child = await _make_child(client, admin_tok)
    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], child["id"])

    r = await client.get("/parent/children", headers=auth(parent_tok))
    assert r.status_code == 200
    ids = [c["id"] for c in r.json()]
    assert child["id"] in ids


async def test_parent_children_excludes_unlinked(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    linked_child = await _make_child(client, admin_tok)
    unlinked_child = await _make_child(client, admin_tok)

    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], linked_child["id"])
    # unlinked_child is NOT linked

    r = await client.get("/parent/children", headers=auth(parent_tok))
    assert r.status_code == 200
    ids = [c["id"] for c in r.json()]
    assert linked_child["id"] in ids
    assert unlinked_child["id"] not in ids


async def test_parent_cadernetas(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    child = await _make_child(client, admin_tok)
    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], child["id"])

    r = await client.get("/parent/cadernetas", headers=auth(parent_tok))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_parent_invoices(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    child = await _make_child(client, admin_tok)
    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], child["id"])

    r = await client.get("/parent/invoices", headers=auth(parent_tok))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_parent_invoice_fields_are_numbers(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    child = await _make_child(client, admin_tok)
    emp, _ = await _make_employee(client, admin_tok)
    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], child["id"])
    await _make_invoice(client, admin_tok, child["id"], emp["id"])

    r = await client.get("/parent/invoices", headers=auth(parent_tok))
    assert r.status_code == 200
    invoices = r.json()
    assert len(invoices) >= 1
    inv = invoices[0]
    for field in ("total_amount", "amount_paid", "balance"):
        assert isinstance(inv[field], (int, float)), (
            f"{field} should be numeric, got {type(inv[field])}: {inv[field]!r}"
        )


async def test_parent_cannot_list_all_children(client: AsyncClient, make_school):
    """GET /children requires teacher+ role; parent should get 403."""
    school, admin_tok, slug, _ = await make_school("par")
    _, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)

    r = await client.get("/children", headers=auth(parent_tok))
    assert r.status_code == 403


async def test_parent_cannot_create_child(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    _, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)

    body = {"cedula": f"CDL{uid()}", "first_name": "X", "last_name": "Y"}
    r = await client.post("/children", json=body, headers=auth(parent_tok))
    assert r.status_code == 403


async def test_parent_can_see_child_cadernetas(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("par")
    child = await _make_child(client, admin_tok)
    emp, _ = await _make_employee(client, admin_tok)
    guardian, parent_tok = await _make_guardian_and_login(client, admin_tok, slug)
    await _link_guardian_to_child(client, admin_tok, guardian["id"], child["id"])
    await _make_caderneta(client, admin_tok, child["id"], emp["id"])

    r = await client.get(f"/children/{child['id']}/cadernetas", headers=auth(parent_tok))
    assert r.status_code == 200
    assert len(r.json()) >= 1


async def test_parent_cannot_access_other_school(client: AsyncClient, make_school):
    """
    A parent whose JWT carries school A's school_id cannot use it as a school B token.
    The /parent/children endpoint uses get_school_id from the JWT, which is school A's id.
    School B's children are completely invisible because school_id filtering applies.
    We verify that the parent token issued for school A cannot list school B children.
    """
    _, admin_a, slug_a, _ = await make_school("par-iso-a")
    _, admin_b, slug_b, _ = await make_school("par-iso-b")

    child_b = await _make_child(client, admin_b)

    # Create parent in school A and link to nothing in school B
    guardian_a, parent_tok_a = await _make_guardian_and_login(client, admin_a, slug_a)

    # Using school A token — school_id in JWT is school A's — child_b won't be visible
    r = await client.get("/parent/children", headers=auth(parent_tok_a))
    assert r.status_code == 200
    ids = [c["id"] for c in r.json()]
    assert child_b["id"] not in ids, (
        "School A parent token must not expose school B children"
    )
