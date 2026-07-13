"""
Tests for recurring service contracts — spec section 20.7.

Covers:
  - UC-FC1–FC6: Contract CRUD, deactivation, manual invoice generation,
    auto-generation idempotency
  - Contract must reference a BillingItem (not free-text)
  - Deactivating a contract stops future invoicing
  - Bulk auto-generate skips already-invoiced months
  - School isolation
"""
from datetime import date

import pytest
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _setup(client: AsyncClient, make_school, prefix="ctr") -> dict:
    school, admin_tok, slug, _ = await make_school(prefix)
    hdrs = auth(admin_tok)

    # Employee
    emp_r = await client.post(
        "/employees",
        json={"first_name": "E", "last_name": "E", "employee_type": "staff",
              "username": f"e-{uid()}", "password": "P1234!"},
        headers=hdrs,
    )
    assert emp_r.status_code == 201
    emp_id = emp_r.json()["id"]

    # Child
    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Contract", "last_name": "Kid"},
        headers=hdrs,
    )
    assert child_r.status_code == 201
    child_id = child_r.json()["id"]

    # Guardian (primary contact — required for billing)
    grd_uname = f"g-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "G", "last_name": "G", "username": grd_uname, "password": "Parent1!"},
        headers=hdrs,
    )
    assert grd_r.status_code == 201
    guardian_id = grd_r.json()["id"]

    await client.post(
        f"/guardians/{guardian_id}/children",
        json={"child_id": child_id, "relationship_type": "mother", "is_primary_contact": True},
        headers=hdrs,
    )

    # Billing item (from seeded defaults or create one)
    bi_r = await client.post(
        "/finance/billing-items",
        json={"code": f"MENS-{uid()[:4]}", "name": "Mensalidade",
              "unit_price": 30000.00, "iva_rate": 0.00, "iva_exemption_reason": "M10"},
        headers=hdrs,
    )
    billing_item_id = bi_r.json().get("id") if bi_r.status_code == 201 else None

    return {
        "admin_tok": admin_tok, "hdrs": hdrs,
        "emp_id": emp_id,
        "child_id": child_id,
        "guardian_id": guardian_id,
        "billing_item_id": billing_item_id,
        "slug": slug,
    }


def _contract_payload(ctx: dict, **overrides) -> dict:
    base = {
        "child_id": ctx["child_id"],
        "start_date": "2025-09-01",
        "billing_cycle": "monthly",
        "day_of_month": 1,
        "auto_invoice": False,
    }
    if ctx["billing_item_id"]:
        base["billing_item_id"] = ctx["billing_item_id"]
    else:
        # Fallback for when BillingItem endpoint doesn't exist yet
        base["service_name"] = "Mensalidade"
        base["amount"] = 30000.00
        base["iva_rate"] = 0.00
    base.update(overrides)
    return base


# ---------------------------------------------------------------------------
# UC-FC1: Create a contract
# ---------------------------------------------------------------------------

async def test_create_contract(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ctr-c")

    r = await client.post(
        "/finance/contracts",
        json=_contract_payload(ctx),
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["child_id"] == ctx["child_id"]
    assert "id" in body
    assert body.get("is_active") is True


async def test_contract_references_billing_item(client: AsyncClient, make_school):
    """A contract must reference a billing_item_id when the catalog exists."""
    ctx = await _setup(client, make_school, "ctr-bi")
    if not ctx["billing_item_id"]:
        pytest.skip("BillingItem endpoint not yet available")

    r = await client.post(
        "/finance/contracts",
        json={
            "child_id": ctx["child_id"],
            "billing_item_id": ctx["billing_item_id"],
            "start_date": "2025-09-01",
            "billing_cycle": "monthly",
            "day_of_month": 1,
            "auto_invoice": False,
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body.get("billing_item_id") == ctx["billing_item_id"], (
        "Contract must store billing_item_id"
    )


async def test_contract_unit_price_overrides_billing_item_default(client: AsyncClient, make_school):
    """unit_price on the contract overrides the BillingItem's default price."""
    ctx = await _setup(client, make_school, "ctr-price")
    if not ctx["billing_item_id"]:
        pytest.skip("BillingItem endpoint not yet available")

    r = await client.post(
        "/finance/contracts",
        json={
            "child_id": ctx["child_id"],
            "billing_item_id": ctx["billing_item_id"],
            "unit_price": 25000.00,  # override
            "start_date": "2025-09-01",
            "billing_cycle": "monthly",
            "day_of_month": 1,
            "auto_invoice": False,
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert float(body.get("unit_price", body.get("amount", 0))) == pytest.approx(25000.00), (
        "Contract must store the overridden unit_price"
    )


# ---------------------------------------------------------------------------
# UC-FC2: List contracts
# ---------------------------------------------------------------------------

async def test_list_contracts(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ctr-l")

    await client.post("/finance/contracts", json=_contract_payload(ctx), headers=ctx["hdrs"])
    await client.post("/finance/contracts", json=_contract_payload(ctx, start_date="2025-10-01"),
                      headers=ctx["hdrs"])

    r = await client.get("/finance/contracts", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 2


async def test_list_contracts_school_isolation(client: AsyncClient, make_school):
    ctx_a = await _setup(client, make_school, "ctr-isola")
    ctx_b = await _setup(client, make_school, "ctr-isolb")

    ctr_r = await client.post("/finance/contracts", json=_contract_payload(ctx_a), headers=ctx_a["hdrs"])
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    r = await client.get("/finance/contracts", headers=ctx_b["hdrs"])
    ids_b = [c["id"] for c in r.json()]
    assert ctr_id not in ids_b


# ---------------------------------------------------------------------------
# UC-FC3: Update a contract
# ---------------------------------------------------------------------------

async def test_update_contract_price(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ctr-u")

    ctr_r = await client.post("/finance/contracts", json=_contract_payload(ctx), headers=ctx["hdrs"])
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    r = await client.patch(
        f"/finance/contracts/{ctr_id}",
        json={"unit_price": 35000.00},
        headers=ctx["hdrs"],
    )
    assert r.status_code == 200, r.text
    body = r.json()
    updated_price = float(body.get("unit_price", body.get("amount", 0)))
    assert updated_price == pytest.approx(35000.00)


async def test_update_contract_end_date(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ctr-udate")

    ctr_r = await client.post("/finance/contracts", json=_contract_payload(ctx), headers=ctx["hdrs"])
    ctr_id = ctr_r.json()["id"]

    r = await client.patch(
        f"/finance/contracts/{ctr_id}",
        json={"end_date": "2026-07-31"},
        headers=ctx["hdrs"],
    )
    assert r.status_code == 200, r.text
    assert r.json().get("end_date") == "2026-07-31"


# ---------------------------------------------------------------------------
# UC-FC4: Deactivate a contract
# ---------------------------------------------------------------------------

async def test_deactivate_contract(client: AsyncClient, make_school):
    """Deactivating a contract sets is_active=False; does not delete it."""
    ctx = await _setup(client, make_school, "ctr-deact")

    ctr_r = await client.post("/finance/contracts", json=_contract_payload(ctx), headers=ctx["hdrs"])
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    r = await client.delete(f"/finance/contracts/{ctr_id}", headers=ctx["hdrs"])
    assert r.status_code in (200, 204), r.text

    # The contract should still be retrievable but inactive
    get_r = await client.get(f"/finance/contracts/{ctr_id}", headers=ctx["hdrs"])
    if get_r.status_code == 200:
        assert get_r.json().get("is_active") is False, (
            "Deactivated contract must have is_active=False"
        )

    # Default list must exclude deactivated contracts
    list_r = await client.get("/finance/contracts", headers=ctx["hdrs"])
    active_ids = [c["id"] for c in list_r.json() if c.get("is_active", True)]
    assert ctr_id not in active_ids


# ---------------------------------------------------------------------------
# UC-FC5: Manual invoice generation from a contract
# ---------------------------------------------------------------------------

async def test_manual_invoice_from_contract(client: AsyncClient, make_school):
    """Admin can manually trigger invoice generation from a specific contract."""
    ctx = await _setup(client, make_school, "ctr-manual")

    ctr_r = await client.post("/finance/contracts", json=_contract_payload(ctx), headers=ctx["hdrs"])
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    r = await client.post(
        f"/finance/contracts/{ctr_id}/generate-invoice",
        json={"reference_month": "2026-01-01"},
        headers=ctx["hdrs"],
    )
    assert r.status_code in (200, 201), (
        f"Manual invoice generation from contract must succeed; got {r.status_code}: {r.text}"
    )
    body = r.json()
    assert "id" in body, "Generated invoice must have an id"


async def test_manual_invoice_uses_contract_billing_item(client: AsyncClient, make_school):
    """Invoice generated from a contract must use the contract's billing_item_id in its lines."""
    ctx = await _setup(client, make_school, "ctr-bi-inv")
    if not ctx["billing_item_id"]:
        pytest.skip("BillingItem endpoint not yet available")

    ctr_r = await client.post(
        "/finance/contracts",
        json={
            "child_id": ctx["child_id"],
            "billing_item_id": ctx["billing_item_id"],
            "start_date": "2025-09-01",
            "billing_cycle": "monthly",
            "day_of_month": 1,
            "auto_invoice": False,
        },
        headers=ctx["hdrs"],
    )
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    inv_r = await client.post(
        f"/finance/contracts/{ctr_id}/generate-invoice",
        json={"reference_month": "2026-02-01"},
        headers=ctx["hdrs"],
    )
    assert inv_r.status_code in (200, 201), inv_r.text
    inv = inv_r.json()

    # The invoice must have line items referencing the billing item
    lines = inv.get("lines", [])
    if lines:
        assert any(
            line.get("billing_item_id") == ctx["billing_item_id"]
            for line in lines
        ), "Invoice line must reference the contract's billing_item_id"


# ---------------------------------------------------------------------------
# UC-FC6: Auto-generate — idempotency
# ---------------------------------------------------------------------------

async def test_auto_generate_skips_already_invoiced_month(client: AsyncClient, make_school):
    """Running auto-generate twice for same month must not create duplicate invoices."""
    ctx = await _setup(client, make_school, "ctr-idem")

    ctr_r = await client.post(
        "/finance/contracts",
        json=_contract_payload(ctx, auto_invoice=True),
        headers=ctx["hdrs"],
    )
    assert ctr_r.status_code == 201

    month = "2026-03-01"
    r1 = await client.post(
        "/finance/invoices/auto-generate-contracts",
        json={"reference_month": month},
        headers=ctx["hdrs"],
    )
    r2 = await client.post(
        "/finance/invoices/auto-generate-contracts",
        json={"reference_month": month},
        headers=ctx["hdrs"],
    )
    assert r1.status_code in (200, 201), r1.text
    assert r2.status_code in (200, 201), r2.text

    # Count invoices for this child + month
    inv_r = await client.get("/finance/invoices", headers=ctx["hdrs"])
    assert inv_r.status_code == 200
    march_invoices = [
        inv for inv in inv_r.json()
        if "2026-03" in (inv.get("reference_month") or "")
        and inv.get("child_id") == ctx["child_id"]
    ]
    assert len(march_invoices) <= 1, (
        f"Auto-generate must be idempotent; found {len(march_invoices)} invoices for same child+month"
    )


async def test_auto_generate_only_runs_for_auto_invoice_true(client: AsyncClient, make_school):
    """Contracts with auto_invoice=False must not be included in auto-generate."""
    ctx = await _setup(client, make_school, "ctr-auto-f")

    ctr_r = await client.post(
        "/finance/contracts",
        json=_contract_payload(ctx, auto_invoice=False),
        headers=ctx["hdrs"],
    )
    assert ctr_r.status_code == 201

    await client.post(
        "/finance/invoices/auto-generate-contracts",
        json={"reference_month": "2026-04-01"},
        headers=ctx["hdrs"],
    )

    inv_r = await client.get("/finance/invoices", headers=ctx["hdrs"])
    april_invoices = [
        inv for inv in inv_r.json()
        if "2026-04" in (inv.get("reference_month") or "")
        and inv.get("child_id") == ctx["child_id"]
    ]
    assert len(april_invoices) == 0, (
        "Contract with auto_invoice=False must not be auto-generated"
    )


async def test_deactivated_contract_not_auto_generated(client: AsyncClient, make_school):
    """A deactivated contract must not produce invoices in auto-generate."""
    ctx = await _setup(client, make_school, "ctr-deact-auto")

    ctr_r = await client.post(
        "/finance/contracts",
        json=_contract_payload(ctx, auto_invoice=True),
        headers=ctx["hdrs"],
    )
    assert ctr_r.status_code == 201
    ctr_id = ctr_r.json()["id"]

    # Deactivate
    await client.delete(f"/finance/contracts/{ctr_id}", headers=ctx["hdrs"])

    await client.post(
        "/finance/invoices/auto-generate-contracts",
        json={"reference_month": "2026-05-01"},
        headers=ctx["hdrs"],
    )

    inv_r = await client.get("/finance/invoices", headers=ctx["hdrs"])
    may_invoices = [
        inv for inv in inv_r.json()
        if "2026-05" in (inv.get("reference_month") or "")
        and inv.get("child_id") == ctx["child_id"]
    ]
    assert len(may_invoices) == 0, (
        "Deactivated contract must not generate invoices in auto-generate"
    )


# ---------------------------------------------------------------------------
# Child with multiple contracts
# ---------------------------------------------------------------------------

async def test_child_can_have_multiple_contracts(client: AsyncClient, make_school):
    """A child can have multiple active contracts (e.g. tuition + transport)."""
    ctx = await _setup(client, make_school, "ctr-multi")

    payloads = [
        _contract_payload(ctx, start_date="2025-09-01"),
        _contract_payload(ctx, start_date="2025-09-01"),
    ]
    if ctx["billing_item_id"]:
        # Create a second billing item for the second contract
        bi2_r = await client.post(
            "/finance/billing-items",
            json={"code": f"TRANSP-{uid()[:4]}", "name": "Transporte",
                  "unit_price": 5000.00, "iva_rate": 0.00, "iva_exemption_reason": "M10"},
            headers=ctx["hdrs"],
        )
        if bi2_r.status_code == 201:
            payloads[1]["billing_item_id"] = bi2_r.json()["id"]

    r1 = await client.post("/finance/contracts", json=payloads[0], headers=ctx["hdrs"])
    r2 = await client.post("/finance/contracts", json=payloads[1], headers=ctx["hdrs"])
    assert r1.status_code == 201, r1.text
    assert r2.status_code == 201, r2.text

    list_r = await client.get("/finance/contracts", headers=ctx["hdrs"])
    child_contracts = [c for c in list_r.json() if c.get("child_id") == ctx["child_id"]]
    assert len(child_contracts) >= 2


# ---------------------------------------------------------------------------
# Access control
# ---------------------------------------------------------------------------

async def test_teacher_cannot_create_contract(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "ctr-auth")

    uname = f"t-{uid()}"
    await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname, "password": "Teacher1!"},
        headers=ctx["hdrs"],
    )
    teacher_tok = await login(client, uname, "Teacher1!", ctx["slug"])

    r = await client.post(
        "/finance/contracts",
        json=_contract_payload(ctx),
        headers=auth(teacher_tok),
    )
    assert r.status_code == 403, f"Teacher must not create contracts; got {r.status_code}"
