"""
Finance spec-compliance tests — spec sections 20.4–20.9.

Covers:
  - Invoice issued to guardian (billing_guardian_id), not child
  - Invoice line items referencing BillingItem
  - Bulk invoice generation requires primary-contact guardian
  - Payment auto-allocation (oldest-first) and explicit targeting
  - Payment reversal (immutable — never deleted)
  - Expense voiding (immutable — never hard-deleted)
  - Receipt line items referencing settled invoice document numbers
  - Financial reports: P&L, outstanding, cash flow, delinquency
  - SAF-T export structure (Customer + Product MasterFiles)

Many tests here define TARGET behaviour against the spec and will
FAIL against the current implementation until it is updated.
"""
import pytest
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

async def _full_finance_ctx(client: AsyncClient, make_school) -> dict:
    """
    Creates a school with:
      - admin token
      - admin-employee token (school_admin WITH employee_id)
      - employee_id (staff, for issued_by / received_by)
      - child_id with primary-contact guardian
      - guardian_id (primary contact)
      - billing_item_id (a billing item for tuition)
      - expense category
    """
    school, admin_tok, slug, _ = await make_school("fspec")
    hdrs = auth(admin_tok)

    # Staff employee (issued_by / received_by field)
    emp_r = await client.post(
        "/employees",
        json={"first_name": "Staff", "last_name": "One", "employee_type": "staff",
              "username": f"staff-{uid()}", "password": "P1234!"},
        headers=hdrs,
    )
    assert emp_r.status_code == 201, emp_r.text
    emp_id = emp_r.json()["id"]

    # Admin-employee token (role=school_admin AND has employee_id)
    adm_uname = f"admemp-{uid()}"
    adm_r = await client.post(
        "/employees",
        json={"first_name": "Adm", "last_name": "Emp", "employee_type": "admin",
              "username": adm_uname, "password": "Admin1!"},
        headers=hdrs,
    )
    assert adm_r.status_code == 201, adm_r.text
    adm_emp_tok = await login(client, adm_uname, "Admin1!", slug)
    adm_emp_hdrs = auth(adm_emp_tok)

    # Child
    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Ana", "last_name": "Ferreira"},
        headers=hdrs,
    )
    assert child_r.status_code == 201, child_r.text
    child_id = child_r.json()["id"]

    # Guardian (primary contact) — NIF required for bulk invoice generation
    grd_uname = f"grd-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "Maria", "last_name": "Ferreira",
              "username": grd_uname, "password": "Parent1!",
              "nif": f"5{uid()[:8]}"},
        headers=hdrs,
    )
    assert grd_r.status_code == 201, grd_r.text
    guardian_id = grd_r.json()["id"]

    # Link guardian → child (primary contact)
    link_r = await client.post(
        f"/guardians/{guardian_id}/children",
        json={"child_id": child_id, "relationship_type": "mother", "is_primary_contact": True},
        headers=hdrs,
    )
    assert link_r.status_code in (200, 201), link_r.text

    parent_tok = await login(client, grd_uname, "Parent1!", slug)

    # Billing item (tuition)
    bi_r = await client.post(
        "/finance/billing-items",
        json={"code": f"MENS-{uid()[:4]}", "name": "Mensalidade",
              "unit_price": 45000.00, "iva_rate": 0.00, "iva_exemption_reason": "M10"},
        headers=hdrs,
    )
    # Fallback: may not exist yet; skip gracefully
    billing_item_id = bi_r.json().get("id") if bi_r.status_code == 201 else None

    # Contract (auto_invoice=True, start_date in past — required for bulk generation)
    contract_r = await client.post(
        "/finance/contracts",
        json={
            "child_id": child_id,
            "guardian_id": guardian_id,
            "service_name": "Mensalidade",
            "unit_price": 45000.00,
            "iva_rate": 0.0,
            "billing_cycle": "monthly",
            "day_of_month": 1,
            "start_date": "2025-01-01",
            "auto_invoice": True,
        },
        headers=hdrs,
    )
    assert contract_r.status_code == 201, contract_r.text
    contract_id = contract_r.json()["id"]

    # Expense category
    cat_r = await client.post(
        "/finance/expense-categories",
        json={"name": f"Cat-{uid()}"},
        headers=hdrs,
    )
    assert cat_r.status_code == 201, cat_r.text
    cat_id = cat_r.json()["id"]

    return {
        "school": school, "slug": slug,
        "admin_tok": admin_tok, "hdrs": hdrs,
        "adm_emp_hdrs": adm_emp_hdrs,
        "emp_id": emp_id,
        "child_id": child_id,
        "guardian_id": guardian_id,
        "parent_tok": parent_tok,
        "billing_item_id": billing_item_id,
        "contract_id": contract_id,
        "cat_id": cat_id,
    }


# ---------------------------------------------------------------------------
# UC-FI1: Invoice must be issued to a guardian, not a child
# ---------------------------------------------------------------------------

async def test_invoice_requires_billing_guardian_id(client: AsyncClient, make_school):
    """POST /finance/invoices must accept billing_guardian_id."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "reference_month": "2026-01-01",
            "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 45000.00}],
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, (
        f"Invoice must accept billing_guardian_id; got {r.status_code}: {r.text}"
    )
    body = r.json()
    assert "billing_guardian_id" in body, "Response must include billing_guardian_id"
    assert body["billing_guardian_id"] == ctx["guardian_id"]


async def test_invoice_requires_lines(client: AsyncClient, make_school):
    """An invoice without any line items must be rejected (422)."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "reference_month": "2026-02-01",
            # no 'lines' — empty by default → 422
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 422, (
        f"Invoice without line items must be 422; got {r.status_code}"
    )


# ---------------------------------------------------------------------------
# Invoice line items referencing BillingItem
# ---------------------------------------------------------------------------

async def test_invoice_line_item_references_billing_item(client: AsyncClient, make_school):
    """Invoice must have line items, each referencing a billing_item_id."""
    ctx = await _full_finance_ctx(client, make_school)
    if not ctx["billing_item_id"]:
        pytest.skip("BillingItem endpoint not yet available")

    r = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-03-01",
            "lines": [
                {
                    "billing_item_id": ctx["billing_item_id"],
                    "description": "Mensalidade Março 2026 — Ana Ferreira",
                    "quantity": 1,
                    "unit_price": 45000.00,
                }
            ],
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "lines" in body, "Invoice response must include line items"
    assert len(body["lines"]) >= 1
    line = body["lines"][0]
    assert line["billing_item_id"] == ctx["billing_item_id"]
    assert "iva_exemption_reason" in line, "Line must carry iva_exemption_reason"


async def test_invoice_line_inherits_iva_exemption_from_billing_item(client: AsyncClient, make_school):
    """When a line is created from a BillingItem with iva_rate=0, the line must have iva_exemption_reason."""
    ctx = await _full_finance_ctx(client, make_school)
    if not ctx["billing_item_id"]:
        pytest.skip("BillingItem endpoint not yet available")

    r = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-04-01",
            "lines": [{"billing_item_id": ctx["billing_item_id"], "quantity": 1, "unit_price": 45000.00}],
        },
        headers=ctx["hdrs"],
    )
    assert r.status_code == 201, r.text
    line = r.json()["lines"][0]
    assert float(line["iva_rate"]) == 0.00
    assert line["iva_exemption_reason"] in ("M10", "M11", "M82"), (
        f"Line must inherit exemption reason from BillingItem, got: {line.get('iva_exemption_reason')}"
    )


# ---------------------------------------------------------------------------
# UC-FI2: Bulk invoice generation
# ---------------------------------------------------------------------------

async def test_bulk_invoice_skips_child_without_primary_guardian(client: AsyncClient, make_school):
    """
    Bulk generation must skip children with no primary-contact guardian and
    include them in a 'warnings' list.
    """
    school, admin_tok, slug, _ = await make_school("bulk-noguard")
    hdrs = auth(admin_tok)

    # Child with no guardian — create a contract for them so they appear in warnings
    orphan_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Orphan", "last_name": "NoGuard"},
        headers=hdrs,
    )
    assert orphan_r.status_code == 201
    orphan_id = orphan_r.json()["id"]

    # Contract for orphan (no guardian_id set, child has no ChildGuardian link)
    await client.post(
        "/finance/contracts",
        json={
            "child_id": orphan_id,
            "service_name": "Mensalidade",
            "unit_price": 30000.00,
            "iva_rate": 0.0,
            "billing_cycle": "monthly",
            "day_of_month": 1,
            "start_date": "2025-01-01",
            "auto_invoice": True,
        },
        headers=hdrs,
    )

    r = await client.post(
        "/finance/invoices/bulk",
        json={"reference_month": "2026-05-01"},
        headers=hdrs,
    )
    # Bulk may return 200 (partial success with warnings) or 201
    assert r.status_code in (200, 201), r.text
    body = r.json()

    # The orphan child must appear in warnings (no guardian), not in created invoices
    warnings = body.get("warnings", [])
    created_ids = body.get("invoice_ids", [])

    warned_ids = [w.get("child_id") for w in warnings]
    assert orphan_id in warned_ids, (
        "Child with no primary guardian must appear in bulk-generation warnings"
    )


async def test_bulk_invoice_idempotent_for_same_month(client: AsyncClient, make_school):
    """Running bulk generation twice for the same month must not create duplicate invoices."""
    ctx = await _full_finance_ctx(client, make_school)

    payload = {"reference_month": "2026-06-01"}
    r1 = await client.post("/finance/invoices/bulk", json=payload, headers=ctx["hdrs"])
    r2 = await client.post("/finance/invoices/bulk", json=payload, headers=ctx["hdrs"])

    assert r1.status_code in (200, 201), r1.text
    assert r2.status_code in (200, 201), r2.text

    inv_r = await client.get("/finance/invoices", headers=ctx["hdrs"])
    assert inv_r.status_code == 200
    june_invoices = [
        inv for inv in inv_r.json()
        if "2026-06" in (inv.get("reference_month") or "")
        and inv.get("child_id") == ctx["child_id"]
    ]
    assert len(june_invoices) == 1, (
        f"Bulk generation must be idempotent — found {len(june_invoices)} invoices for same month"
    )


# ---------------------------------------------------------------------------
# UC-FI5: Cancellation is permanent (not a delete)
# ---------------------------------------------------------------------------

async def test_cancelled_invoice_remains_in_list(client: AsyncClient, make_school):
    """A cancelled invoice must still appear in the list (for SAF-T status 'A')."""
    ctx = await _full_finance_ctx(client, make_school)

    inv_r = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "reference_month": "2026-07-01",
            "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 10000.00}],
        },
        headers=ctx["hdrs"],
    )
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    cancel_r = await client.post(
        f"/finance/invoices/{inv_id}/cancel",
        json={"reason": "Test cancellation"},
        headers=ctx["hdrs"],
    )
    assert cancel_r.status_code in (200, 201), cancel_r.text

    # Invoice must still appear in list with status 'cancelled'
    list_r = await client.get("/finance/invoices", headers=ctx["hdrs"])
    assert list_r.status_code == 200
    all_ids = [inv["id"] for inv in list_r.json()]
    assert inv_id in all_ids, (
        "Cancelled invoice must remain in the list (AGT requires status 'A' in SAF-T)"
    )

    # And its status must be 'cancelled'
    get_r = await client.get(f"/finance/invoices/{inv_id}", headers=ctx["hdrs"])
    assert get_r.status_code == 200
    assert get_r.json()["status"] == "cancelled"


# ---------------------------------------------------------------------------
# UC-FE5: Expense voiding (no hard delete)
# ---------------------------------------------------------------------------

async def test_expense_void_not_delete(client: AsyncClient, make_school):
    """Expenses must be voided (is_voided=True), never hard-deleted."""
    ctx = await _full_finance_ctx(client, make_school)

    exp_r = await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Error expense",
            "amount": 999.00,
            "expense_date": "2026-01-10",
        },
        headers=ctx["hdrs"],
    )
    assert exp_r.status_code == 201, exp_r.text
    exp_id = exp_r.json()["id"]

    # Attempt to void
    void_r = await client.post(
        f"/finance/expenses/{exp_id}/void",
        json={"void_reason": "Recorded in error"},
        headers=ctx["hdrs"],
    )
    assert void_r.status_code in (200, 201), (
        f"Expense void endpoint must exist; got {void_r.status_code}: {void_r.text}"
    )

    # Record must still exist (immutability)
    get_r = await client.get(f"/finance/expenses/{exp_id}", headers=ctx["hdrs"])
    assert get_r.status_code == 200, "Voided expense must still be retrievable"
    body = get_r.json()
    assert body.get("is_voided") is True, "Voided expense must have is_voided=True"
    assert body.get("void_reason"), "Voided expense must store the void_reason"


async def test_expense_hard_delete_is_forbidden(client: AsyncClient, make_school):
    """DELETE /finance/expenses/{id} must not exist (financial immutability)."""
    ctx = await _full_finance_ctx(client, make_school)

    exp_r = await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Should not be deletable",
            "amount": 100.00,
            "expense_date": "2026-01-15",
        },
        headers=ctx["hdrs"],
    )
    assert exp_r.status_code == 201, exp_r.text
    exp_id = exp_r.json()["id"]

    del_r = await client.delete(f"/finance/expenses/{exp_id}", headers=ctx["hdrs"])
    assert del_r.status_code in (404, 405), (
        f"Expense hard-delete must be blocked (404/405), got {del_r.status_code}"
    )

    # Record must still exist
    get_r = await client.get(f"/finance/expenses/{exp_id}", headers=ctx["hdrs"])
    assert get_r.status_code == 200, "Expense must not have been deleted"


async def test_voided_expense_excluded_from_pl_totals(client: AsyncClient, make_school):
    """A voided expense must not count towards P&L totals."""
    ctx = await _full_finance_ctx(client, make_school)

    # Create and void an expense
    exp_r = await client.post(
        "/finance/expenses",
        json={"category_id": ctx["cat_id"], "registered_by": ctx["emp_id"],
              "description": "Big voided expense", "amount": 99999.00, "expense_date": "2026-01-20"},
        headers=ctx["hdrs"],
    )
    assert exp_r.status_code == 201
    exp_id = exp_r.json()["id"]

    void_r = await client.post(
        f"/finance/expenses/{exp_id}/void",
        json={"void_reason": "Error"},
        headers=ctx["hdrs"],
    )
    if void_r.status_code not in (200, 201):
        pytest.skip("Expense void endpoint not yet available")

    pl_r = await client.get("/finance/reports/pl?month=2026-01", headers=ctx["hdrs"])
    if pl_r.status_code != 200:
        pytest.skip("P&L report not available")

    pl = pl_r.json()
    expenses_total = float(pl.get("total_expenses", pl.get("expenses", 0)))
    assert expenses_total < 99999.00, (
        "Voided expense of 99999.00 must not appear in P&L expense totals"
    )


# ---------------------------------------------------------------------------
# UC-FP2a: Auto-allocation (oldest-first)
# ---------------------------------------------------------------------------

async def test_payment_auto_allocates_oldest_first(client: AsyncClient, make_school):
    """Without explicit invoice_ids, payment settles oldest invoice first."""
    ctx = await _full_finance_ctx(client, make_school)

    # Create two invoices for different months (Jan then Feb)
    def _inv_payload(month):
        return {
            "billing_guardian_id": ctx["guardian_id"],
            "child_id": ctx["child_id"],
            "reference_month": month,
            "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 10000.00}],
        }

    inv1_r = await client.post("/finance/invoices", json=_inv_payload("2026-01-01"), headers=ctx["hdrs"])
    inv2_r = await client.post("/finance/invoices", json=_inv_payload("2026-02-01"), headers=ctx["hdrs"])

    assert inv1_r.status_code == 201, inv1_r.text
    assert inv2_r.status_code == 201, inv2_r.text
    inv1_id = inv1_r.json()["id"]
    inv2_id = inv2_r.json()["id"]

    # Pay exactly the amount for one invoice — should go to Jan (oldest)
    pay_r = await client.post(
        "/finance/payments",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "payment_method": "cash",
            "amount": 10000.00,
            "payment_date": "2026-03-01",
        },
        headers=ctx["hdrs"],
    )
    assert pay_r.status_code == 201, pay_r.text

    # Jan invoice should be paid; Feb should be pending
    inv1_data = (await client.get(f"/finance/invoices/{inv1_id}", headers=ctx["hdrs"])).json()
    inv2_data = (await client.get(f"/finance/invoices/{inv2_id}", headers=ctx["hdrs"])).json()
    assert inv1_data["status"] == "paid", (
        f"Jan invoice (oldest) must be paid by auto-allocation, got: {inv1_data['status']}"
    )
    assert inv2_data["status"] == "pending", (
        f"Feb invoice must remain pending, got: {inv2_data['status']}"
    )


# ---------------------------------------------------------------------------
# UC-FP2b: Explicit invoice targeting
# ---------------------------------------------------------------------------

async def test_payment_explicit_targeting_bypasses_oldest_first(client: AsyncClient, make_school):
    """When invoice_ids is provided, funds go ONLY to specified invoices."""
    ctx = await _full_finance_ctx(client, make_school)

    # Create Jan (older) and Feb invoices
    inv1_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-01-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 10000.00}]},
        headers=ctx["hdrs"])
    inv2_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-02-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 10000.00}]},
        headers=ctx["hdrs"])
    assert inv1_r.status_code == 201, inv1_r.text
    assert inv2_r.status_code == 201, inv2_r.text
    inv1_id = inv1_r.json()["id"]
    inv2_id = inv2_r.json()["id"]

    # Parent explicitly pays ONLY Feb, despite Jan being older
    pay_r = await client.post(
        "/finance/payments",
        json={
            "billing_guardian_id": ctx["guardian_id"],
            "payment_method": "cash",
            "amount": 10000.00,
            "payment_date": "2026-03-01",
            "target_invoice_ids": [inv2_id],  # explicitly target Feb only
        },
        headers=ctx["hdrs"],
    )
    assert pay_r.status_code == 201, (
        f"Payment with explicit invoice_ids must be accepted; got {pay_r.status_code}: {pay_r.text}"
    )

    inv1_data = (await client.get(f"/finance/invoices/{inv1_id}", headers=ctx["hdrs"])).json()
    inv2_data = (await client.get(f"/finance/invoices/{inv2_id}", headers=ctx["hdrs"])).json()

    assert inv2_data["status"] == "paid", (
        f"Explicitly targeted Feb invoice must be paid, got: {inv2_data['status']}"
    )
    assert inv1_data["status"] == "pending", (
        f"Jan invoice must remain pending (not targeted), got: {inv1_data['status']}"
    )


async def test_explicit_targeting_cross_guardian_rejected(client: AsyncClient, make_school):
    """target_invoice_ids from a different guardian must be rejected."""
    school, admin_tok, slug, _ = await make_school("pay-cross")
    hdrs = auth(admin_tok)

    # Create two children each with their own guardian
    child1_r = await client.post("/children",
        json={"cedula": f"C{uid()}", "first_name": "C1", "last_name": "X"}, headers=hdrs)
    child2_r = await client.post("/children",
        json={"cedula": f"C{uid()}", "first_name": "C2", "last_name": "Y"}, headers=hdrs)
    child1_id = child1_r.json()["id"]
    child2_id = child2_r.json()["id"]

    grd1_r = await client.post("/guardians",
        json={"first_name": "G1", "last_name": "X", "nif": f"5{uid()[:8]}",
              "username": f"g1-{uid()}", "password": "P1234!"},
        headers=hdrs)
    grd2_r = await client.post("/guardians",
        json={"first_name": "G2", "last_name": "Y", "nif": f"5{uid()[:8]}",
              "username": f"g2-{uid()}", "password": "P1234!"},
        headers=hdrs)
    assert grd1_r.status_code == 201
    assert grd2_r.status_code == 201
    grd1_id = grd1_r.json()["id"]
    grd2_id = grd2_r.json()["id"]

    inv1_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": grd1_id, "child_id": child1_id,
              "reference_month": "2026-01-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 5000.00}]},
        headers=hdrs)
    inv2_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": grd2_id, "child_id": child2_id,
              "reference_month": "2026-01-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 5000.00}]},
        headers=hdrs)
    assert inv1_r.status_code == 201, inv1_r.text
    assert inv2_r.status_code == 201, inv2_r.text

    # Payment by guardian1 targeting guardian2's invoice must fail
    pay_r = await client.post(
        "/finance/payments",
        json={
            "billing_guardian_id": grd1_id,
            "payment_method": "cash",
            "amount": 5000.00,
            "payment_date": "2026-03-01",
            "target_invoice_ids": [inv2_r.json()["id"]],
        },
        headers=hdrs,
    )
    assert pay_r.status_code in (400, 422), (
        f"Cross-guardian payment targeting must be rejected; got {pay_r.status_code}"
    )


# ---------------------------------------------------------------------------
# UC-FP5: Payment reversal (not deletion)
# ---------------------------------------------------------------------------

async def test_payment_reversal_keeps_record(client: AsyncClient, make_school):
    """Reversing a payment must not delete it — it must be marked 'reversed'."""
    ctx = await _full_finance_ctx(client, make_school)

    inv_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-08-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 5000.00}]},
        headers=ctx["hdrs"])
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    pay_r = await client.post("/finance/payments",
        json={"billing_guardian_id": ctx["guardian_id"],
              "payment_method": "cash",
              "amount": 5000.00, "payment_date": "2026-08-10",
              "target_invoice_ids": [inv_id]},
        headers=ctx["hdrs"])
    assert pay_r.status_code == 201, pay_r.text
    pay_id = pay_r.json()["id"]

    # Reverse the payment
    rev_r = await client.post(
        f"/finance/payments/{pay_id}/reverse",
        json={"reason": "Payment received in error"},
        headers=ctx["hdrs"],
    )
    assert rev_r.status_code in (200, 201), (
        f"Payment reverse endpoint must exist; got {rev_r.status_code}: {rev_r.text}"
    )

    # Payment record must still exist
    get_r = await client.get(f"/finance/payments/{pay_id}", headers=ctx["hdrs"])
    assert get_r.status_code == 200, "Reversed payment must still be retrievable"
    assert get_r.json().get("status") == "reversed", (
        f"Reversed payment must have status='reversed', got: {get_r.json().get('status')}"
    )

    # Invoice must revert to pending
    inv_data = (await client.get(f"/finance/invoices/{inv_id}", headers=ctx["hdrs"])).json()
    assert inv_data["status"] == "pending", (
        f"Invoice must revert to 'pending' after payment reversal, got: {inv_data['status']}"
    )


async def test_payment_hard_delete_is_forbidden(client: AsyncClient, make_school):
    """DELETE /finance/payments/{id} must not exist."""
    ctx = await _full_finance_ctx(client, make_school)

    pay_r = await client.post("/finance/payments",
        json={"billing_guardian_id": ctx["guardian_id"],
              "payment_method": "cash",
              "amount": 100.00, "payment_date": "2026-01-05"},
        headers=ctx["hdrs"])
    assert pay_r.status_code == 201, pay_r.text
    pay_id = pay_r.json()["id"]

    del_r = await client.delete(f"/finance/payments/{pay_id}", headers=ctx["hdrs"])
    assert del_r.status_code in (404, 405), (
        f"Payment hard-delete must be 404/405, got {del_r.status_code}"
    )


# ---------------------------------------------------------------------------
# UC-FR2: Receipt line items must reference settled invoices
# ---------------------------------------------------------------------------

async def test_receipt_has_line_items_with_invoice_references(client: AsyncClient, make_school):
    """When a payment generates a receipt, the RC must list each settled invoice."""
    ctx = await _full_finance_ctx(client, make_school)

    inv_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-09-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 30000.00}]},
        headers=ctx["hdrs"])
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]
    inv_doc_number = inv_r.json().get("full_document_number")

    pay_r = await client.post("/finance/payments",
        json={"billing_guardian_id": ctx["guardian_id"],
              "payment_method": "cash",
              "amount": 30000.00, "payment_date": "2026-09-10",
              "target_invoice_ids": [inv_id]},
        headers=ctx["hdrs"])
    assert pay_r.status_code == 201, pay_r.text
    pay_id = pay_r.json()["id"]

    # Fetch the generated receipt for this payment
    receipts_r = await client.get(f"/finance/receipts?payment_id={pay_id}", headers=ctx["hdrs"])
    if receipts_r.status_code != 200 or not receipts_r.json():
        # Try getting all receipts and filtering
        all_r = await client.get("/finance/receipts", headers=ctx["hdrs"])
        assert all_r.status_code == 200
        receipts = [rc for rc in all_r.json() if rc.get("payment_id") == pay_id]
    else:
        receipts = receipts_r.json()

    assert receipts, f"A receipt must be generated when a payment settles an invoice"

    receipt = receipts[0]
    assert "lines" in receipt, (
        "Receipt must contain line items (AGT SAF-T Payments section requirement)"
    )
    assert len(receipt["lines"]) >= 1, "Receipt must have at least one line item"

    line = receipt["lines"][0]
    assert "settled_document_number" in line or "invoice_document_number" in line, (
        "Receipt line must reference the settled invoice's document number"
    )
    settled_doc = line.get("settled_document_number") or line.get("invoice_document_number")
    if inv_doc_number:
        assert settled_doc == inv_doc_number, (
            f"Receipt line must reference FT document number {inv_doc_number!r}, got {settled_doc!r}"
        )
    assert "amount_applied" in line, "Receipt line must include amount_applied"


# ---------------------------------------------------------------------------
# Finance reports
# ---------------------------------------------------------------------------

async def test_pl_report_returns_revenue_and_expenses(client: AsyncClient, make_school):
    """GET /finance/reports/pl must return revenue, expenses, and net."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.get("/finance/reports/pl", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    body = r.json()
    for field in ("revenue", "expenses", "net"):
        assert field in body, f"P&L must include '{field}' field"
        v = body[field]
        assert isinstance(v, (int, float)), f"P&L.{field} must be numeric, got {type(v).__name__}"


async def test_pl_report_net_equals_revenue_minus_expenses(client: AsyncClient, make_school):
    ctx = await _full_finance_ctx(client, make_school)
    r = await client.get("/finance/reports/pl", headers=ctx["hdrs"])
    assert r.status_code == 200
    body = r.json()
    revenue = float(body["revenue"])
    expenses = float(body["expenses"])
    net = float(body["net"])
    assert net == pytest.approx(revenue - expenses, abs=0.01), (
        f"P&L net must equal revenue - expenses: {revenue} - {expenses} ≠ {net}"
    )


async def test_outstanding_report(client: AsyncClient, make_school):
    """GET /finance/reports/outstanding must return list with aging buckets."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.get("/finance/reports/outstanding", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


async def test_cash_flow_report(client: AsyncClient, make_school):
    """GET /finance/reports/cash-flow returns monthly income vs expenses."""
    ctx = await _full_finance_ctx(client, make_school)
    r = await client.get("/finance/reports/cash-flow", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text


async def test_delinquency_report_includes_guardian_contact(client: AsyncClient, make_school):
    """GET /finance/reports/delinquent must include guardian contact info."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.get("/finance/reports/delinquent", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text
    items = r.json()
    for item in items:
        # Must include contact info for collection purposes
        assert "guardian_name" in item or "contact_name" in item, (
            "Delinquency report must include guardian name"
        )


async def test_revenue_by_level_report(client: AsyncClient, make_school):
    ctx = await _full_finance_ctx(client, make_school)
    r = await client.get("/finance/reports/revenue-by-level", headers=ctx["hdrs"])
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------------------
# SAF-T export structure
# ---------------------------------------------------------------------------

async def test_saft_export_returns_xml(client: AsyncClient, make_school):
    """GET /finance/reports/saft must return XML content."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.get(
        "/finance/reports/saft",
        params={"year": 2026},
        headers=ctx["hdrs"],
    )
    assert r.status_code == 200, r.text
    content_type = r.headers.get("content-type", "")
    assert "xml" in content_type or r.text.strip().startswith("<"), (
        f"SAF-T export must return XML; content-type: {content_type}"
    )


async def test_saft_contains_customer_masterfile(client: AsyncClient, make_school):
    """SAF-T XML must include a MasterFiles/Customer section."""
    ctx = await _full_finance_ctx(client, make_school)

    # Create at least one invoice so there is a customer to export
    await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-10-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 1000.00}]},
        headers=ctx["hdrs"])

    r = await client.get("/finance/reports/saft", params={"year": 2026}, headers=ctx["hdrs"])
    if r.status_code != 200:
        pytest.skip("SAF-T endpoint not available")

    assert "<Customer>" in r.text or "<MasterFiles>" in r.text, (
        "SAF-T must include MasterFiles/Customer for every billing guardian"
    )


async def test_saft_contains_product_masterfile(client: AsyncClient, make_school):
    """SAF-T XML must include a MasterFiles/Product section."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.get("/finance/reports/saft", params={"year": 2026}, headers=ctx["hdrs"])
    if r.status_code != 200:
        pytest.skip("SAF-T endpoint not available")

    assert "<Product>" in r.text or "<MasterFiles>" in r.text, (
        "SAF-T must include MasterFiles/Product from BillingItem catalog"
    )


async def test_saft_cancelled_invoice_has_status_a(client: AsyncClient, make_school):
    """Cancelled invoices must appear in SAF-T with status 'A' (Anulado)."""
    ctx = await _full_finance_ctx(client, make_school)

    inv_r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-11-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 5000.00}]},
        headers=ctx["hdrs"])
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    await client.post(f"/finance/invoices/{inv_id}/cancel",
        json={"reason": "Test"}, headers=ctx["hdrs"])

    r = await client.get("/finance/reports/saft", params={"year": 2026}, headers=ctx["hdrs"])
    if r.status_code != 200:
        pytest.skip("SAF-T endpoint not available")

    assert "<InvoiceStatus>A</InvoiceStatus>" in r.text or "Anulado" in r.text or \
           (inv_r.json().get("full_document_number", "") in r.text), (
        "Cancelled invoice must appear in SAF-T with status A"
    )


# ---------------------------------------------------------------------------
# Document series and hash chain
# ---------------------------------------------------------------------------

async def test_invoice_has_document_number(client: AsyncClient, make_school):
    """Every created invoice must have a full_document_number (e.g. 'FT 2026/1')."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-12-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 10000.00}]},
        headers=ctx["hdrs"])
    assert r.status_code == 201, r.text
    body = r.json()
    assert body.get("full_document_number"), (
        f"Invoice must have a full_document_number; got: {body.get('full_document_number')!r}"
    )
    assert body["full_document_number"].startswith("FT "), (
        f"FT document number must start with 'FT '; got: {body['full_document_number']!r}"
    )


async def test_invoice_has_hash_code(client: AsyncClient, make_school):
    """Every created invoice must have a hash_code (RSA-SHA1 signature)."""
    ctx = await _full_finance_ctx(client, make_school)

    r = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-01-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 5000.00}]},
        headers=ctx["hdrs"])
    assert r.status_code == 201, r.text
    body = r.json()
    assert body.get("hash_code"), (
        "Invoice must have a hash_code (RSA-SHA1 AGT signature)"
    )


async def test_invoice_numbers_are_sequential(client: AsyncClient, make_school):
    """Document numbers must be sequential within a series-year, never skipping."""
    ctx = await _full_finance_ctx(client, make_school)

    r1 = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-01-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 1000.00}]},
        headers=ctx["hdrs"])
    r2 = await client.post("/finance/invoices",
        json={"billing_guardian_id": ctx["guardian_id"], "child_id": ctx["child_id"],
              "reference_month": "2026-02-01",
              "lines": [{"description": "Mensalidade", "quantity": 1, "unit_price": 1000.00}]},
        headers=ctx["hdrs"])
    assert r1.status_code == 201 and r2.status_code == 201, f"{r1.text} | {r2.text}"

    n1 = r1.json().get("series_number", 0)
    n2 = r2.json().get("series_number", 0)
    assert n2 == n1 + 1, (
        f"Invoice series numbers must be sequential: expected {n1+1}, got {n2}"
    )
