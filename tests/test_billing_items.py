"""
Tests for the Service Catalog (BillingItem) — spec section 20.2.

A BillingItem represents a catalogued service the school sells.
Every invoice line item must reference one; free-text descriptions
are derived from it, not the source of truth.

These tests define the TARGET behaviour. Many will fail until the
BillingItem model and /finance/billing-items endpoints are built.
"""
from httpx import AsyncClient

from tests.conftest import auth, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _make_billing_item(client: AsyncClient, token: str, **overrides) -> dict:
    body = {
        "code": f"TEST-{uid()[:6]}",
        "name": f"Item {uid()[:6]}",
        "unit_price": 500.00,
        "iva_rate": 0.00,
        "iva_exemption_reason": "M10",
        **overrides,
    }
    r = await client.post("/finance/billing-items", json=body, headers=auth(token))
    assert r.status_code == 201, r.text
    return r.json()


# ---------------------------------------------------------------------------
# UC-FSC1: Create a billing item
# ---------------------------------------------------------------------------

async def test_create_billing_item(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("bi-c")
    code = f"MENS-{uid()[:6]}"
    r = await client.post(
        "/finance/billing-items",
        json={
            "code": code,
            "name": "Mensalidade Berçário",
            "unit_price": 45000.00,
            "iva_rate": 0.00,
            "iva_exemption_reason": "M10",
        },
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["code"] == code
    assert body["name"] == "Mensalidade Berçário"
    assert body["iva_exemption_reason"] == "M10"
    assert float(body["unit_price"]) == 45000.00
    assert float(body["iva_rate"]) == 0.00
    assert body["is_active"] is True


async def test_billing_item_code_is_immutable_after_create(client: AsyncClient, make_school):
    """Once a billing item is created, its code must not be changeable (stable SAF-T identifier)."""
    _, token, _, _ = await make_school("bi-imm")
    item = await _make_billing_item(client, token, code="STABLE-CODE")

    r = await client.patch(
        f"/finance/billing-items/{item['id']}",
        json={"code": "CHANGED-CODE"},
        headers=auth(token),
    )
    # Either 422 (validation error) or the code is silently ignored
    if r.status_code == 200:
        assert r.json()["code"] == "STABLE-CODE", (
            "Billing item code must be immutable; PATCH must not change it"
        )
    else:
        assert r.status_code == 422, r.text


async def test_billing_item_code_unique_within_school(client: AsyncClient, make_school):
    """Duplicate code within the same school must be rejected."""
    _, token, _, _ = await make_school("bi-dup")
    code = f"DUPL-{uid()[:6]}"
    await _make_billing_item(client, token, code=code)

    r = await client.post(
        "/finance/billing-items",
        json={
            "code": code,
            "name": "Another item with same code",
            "unit_price": 100.00,
            "iva_rate": 0.00,
            "iva_exemption_reason": "M10",
        },
        headers=auth(token),
    )
    assert r.status_code in (400, 409, 422), (
        f"Expected error for duplicate code, got {r.status_code}: {r.text}"
    )


async def test_billing_item_code_can_repeat_across_schools(client: AsyncClient, make_school):
    """The same code in two different schools is allowed (isolation)."""
    _, token_a, _, _ = await make_school("bi-xa")
    _, token_b, _, _ = await make_school("bi-xb")
    code = f"SHARED-{uid()[:6]}"

    r_a = await client.post(
        "/finance/billing-items",
        json={"code": code, "name": "Item A", "unit_price": 100.00, "iva_rate": 0.00, "iva_exemption_reason": "M10"},
        headers=auth(token_a),
    )
    r_b = await client.post(
        "/finance/billing-items",
        json={"code": code, "name": "Item B", "unit_price": 200.00, "iva_rate": 0.00, "iva_exemption_reason": "M10"},
        headers=auth(token_b),
    )
    assert r_a.status_code == 201, r_a.text
    assert r_b.status_code == 201, r_b.text


# ---------------------------------------------------------------------------
# UC-FSC2: List billing items
# ---------------------------------------------------------------------------

async def test_list_billing_items(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("bi-l")
    await _make_billing_item(client, token)
    await _make_billing_item(client, token)

    r = await client.get("/finance/billing-items", headers=auth(token))
    assert r.status_code == 200, r.text
    items = r.json()
    assert isinstance(items, list)
    assert len(items) >= 2


async def test_list_billing_items_school_isolation(client: AsyncClient, make_school):
    _, token_a, _, _ = await make_school("bi-isola")
    _, token_b, _, _ = await make_school("bi-isolb")

    item_a = await _make_billing_item(client, token_a)

    r = await client.get("/finance/billing-items", headers=auth(token_b))
    assert r.status_code == 200
    ids_b = [i["id"] for i in r.json()]
    assert item_a["id"] not in ids_b


# ---------------------------------------------------------------------------
# UC-FSC3: Update a billing item
# ---------------------------------------------------------------------------

async def test_update_billing_item_name_and_price(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("bi-u")
    item = await _make_billing_item(client, token)

    r = await client.patch(
        f"/finance/billing-items/{item['id']}",
        json={"name": "Updated Name", "unit_price": 999.00},
        headers=auth(token),
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["name"] == "Updated Name"
    assert float(body["unit_price"]) == 999.00


# ---------------------------------------------------------------------------
# UC-FSC4: Deactivate a billing item
# ---------------------------------------------------------------------------

async def test_deactivate_billing_item(client: AsyncClient, make_school):
    """Admin can deactivate a billing item (soft delete — sets is_active=False)."""
    _, token, _, _ = await make_school("bi-d")
    item = await _make_billing_item(client, token)

    r = await client.patch(
        f"/finance/billing-items/{item['id']}",
        json={"is_active": False},
        headers=auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["is_active"] is False

    # Deactivated items should not appear in the default list
    list_r = await client.get("/finance/billing-items", headers=auth(token))
    active_ids = [i["id"] for i in list_r.json() if i.get("is_active", True)]
    assert item["id"] not in active_ids


async def test_cannot_hard_delete_billing_item(client: AsyncClient, make_school):
    """Billing items must never be hard-deleted — no DELETE endpoint."""
    _, token, _, _ = await make_school("bi-nd")
    item = await _make_billing_item(client, token)

    r = await client.delete(f"/finance/billing-items/{item['id']}", headers=auth(token))
    # Must be 404 (endpoint doesn't exist) or 405 (method not allowed)
    assert r.status_code in (404, 405, 422), (
        f"Billing items must not support hard delete, got {r.status_code}"
    )


# ---------------------------------------------------------------------------
# Seeded defaults
# ---------------------------------------------------------------------------

async def test_school_creation_seeds_default_billing_items(client: AsyncClient, make_school):
    """A newly created school must have pre-seeded default billing items."""
    _, token, _, _ = await make_school("bi-seed")

    r = await client.get("/finance/billing-items", headers=auth(token))
    assert r.status_code == 200
    items = r.json()
    codes = {i["code"] for i in items}

    expected_codes = {"MENS-BERC", "MENS-CRECHE", "MENS-JARDIN", "MATRICULA", "EXTRAS"}
    missing = expected_codes - codes
    assert not missing, (
        f"School must be seeded with default billing items. Missing codes: {missing}"
    )


async def test_seeded_billing_items_have_m10_exemption(client: AsyncClient, make_school):
    """All seeded education billing items must have iva_exemption_reason=M10."""
    _, token, _, _ = await make_school("bi-m10")

    r = await client.get("/finance/billing-items", headers=auth(token))
    assert r.status_code == 200
    for item in r.json():
        if float(item.get("iva_rate", 0)) == 0.0:
            assert item.get("iva_exemption_reason") in ("M10", "M11", "M82"), (
                f"Item {item['code']} has 0% IVA but no valid exemption reason: "
                f"{item.get('iva_exemption_reason')!r}"
            )


# ---------------------------------------------------------------------------
# AGT requirement: 0% IVA must always have exemption reason
# ---------------------------------------------------------------------------

async def test_zero_iva_requires_exemption_reason(client: AsyncClient, make_school):
    """Creating a billing item with iva_rate=0 and no exemption reason must be rejected."""
    _, token, _, _ = await make_school("bi-no-exempt")

    r = await client.post(
        "/finance/billing-items",
        json={
            "code": f"NO-EXEMPT-{uid()[:6]}",
            "name": "Bad Item",
            "unit_price": 100.00,
            "iva_rate": 0.00,
            # intentionally omitting iva_exemption_reason
        },
        headers=auth(token),
    )
    assert r.status_code == 422, (
        f"0% IVA without exemption reason must be rejected (AGT requirement), got {r.status_code}"
    )


# ---------------------------------------------------------------------------
# Access control
# ---------------------------------------------------------------------------

async def test_teacher_cannot_create_billing_item(client: AsyncClient, make_school):
    from tests.conftest import login
    _, admin_token, slug, _ = await make_school("bi-auth")

    uname = f"t-{uid()}"
    await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname, "password": "Teacher1!"},
        headers=auth(admin_token),
    )
    teacher_token = await login(client, uname, "Teacher1!", slug)

    r = await client.post(
        "/finance/billing-items",
        json={"code": "T-ITEM", "name": "Teacher Item", "unit_price": 1.00,
              "iva_rate": 0.00, "iva_exemption_reason": "M10"},
        headers=auth(teacher_token),
    )
    assert r.status_code == 403


async def test_unauthenticated_cannot_list_billing_items(client: AsyncClient, make_school):
    r = await client.get("/finance/billing-items")
    assert r.status_code in (401, 403)
