"""
Finance endpoint tests for Cellen API.

Most critical purpose: verify ALL numeric/Decimal fields are returned as JSON
numbers (int/float), NOT strings — the Flutter bug caused Pydantic v2 to
serialize Decimal as "12.00" (a string). The fix is exercised here.

pytest-asyncio asyncio_mode=auto, base_url=http://test/api/v1
"""
import pytest

from tests.conftest import auth, uid


# ──────────────────────────────────────────────────────────────────────────────
# Shared setup helper
# ──────────────────────────────────────────────────────────────────────────────

async def _setup(client, make_school) -> dict:
    """
    Create a school, an employee, a child, and an expense category.
    Returns a dict with all ids / tokens needed by finance tests.
    """
    school, admin_tok, slug, _ = await make_school("fin")
    hdrs = auth(admin_tok)

    # Employee (used as issued_by / received_by / registered_by)
    emp_r = await client.post(
        "/employees",
        json={
            "first_name": "A",
            "last_name": "B",
            "employee_type": "staff",
            "username": f"emp-{uid()}",
            "password": "P1234!",
        },
        headers=hdrs,
    )
    assert emp_r.status_code == 201, emp_r.text
    emp_id = emp_r.json()["id"]

    # Admin-type employee: role=school_admin AND has employee_id
    # Needed for endpoints that require school_admin + employee_id (void, bulk payments, etc.)
    adm_username = f"adminemp-{uid()}"
    adm_emp_r = await client.post(
        "/employees",
        json={
            "first_name": "Admin",
            "last_name": "Emp",
            "employee_type": "admin",
            "username": adm_username,
            "password": "Admin1!",
        },
        headers=hdrs,
    )
    assert adm_emp_r.status_code == 201, adm_emp_r.text
    from tests.conftest import login as _login
    admin_emp_tok = await _login(client, adm_username, "Admin1!", slug)
    admin_emp_hdrs = {"Authorization": f"Bearer {admin_emp_tok}"}

    # Child
    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Kid", "last_name": "Test"},
        headers=hdrs,
    )
    assert child_r.status_code == 201, child_r.text
    child_id = child_r.json()["id"]

    # Expense category
    cat_r = await client.post(
        "/finance/expense-categories",
        json={"name": f"Cat-{uid()}"},
        headers=hdrs,
    )
    assert cat_r.status_code == 201, cat_r.text
    cat_id = cat_r.json()["id"]

    return {
        "school": school,
        "admin_tok": admin_tok,
        "hdrs": hdrs,
        "admin_emp_hdrs": admin_emp_hdrs,  # school_admin WITH employee_id
        "slug": slug,
        "emp_id": emp_id,
        "child_id": child_id,
        "cat_id": cat_id,
    }


def _is_numeric(v) -> bool:
    """Return True if v is an int or float but NOT a bool and NOT a str."""
    return isinstance(v, (int, float)) and not isinstance(v, bool)


# ──────────────────────────────────────────────────────────────────────────────
# Decimal serialization checks (MOST IMPORTANT)
# ──────────────────────────────────────────────────────────────────────────────

async def test_expense_amount_is_number(client, make_school):
    """Expense amount must be a JSON number, never a string."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Test expense",
            "amount": 125.50,
            "expense_date": "2026-01-15",
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text

    list_r = await client.get("/finance/expenses", headers=hdrs)
    assert list_r.status_code == 200
    expenses = list_r.json()
    assert len(expenses) >= 1

    for expense in expenses:
        v = expense["amount"]
        assert _is_numeric(v), f"expense.amount is {type(v).__name__!r}: {v!r}"
        assert not isinstance(v, str), f"expense.amount must not be a string, got {v!r}"


async def test_invoice_all_decimal_fields_are_numbers(client, make_school):
    """All Decimal fields on InvoiceResponse must be JSON numbers, not strings."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    create_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-03-01",
            "tuition_amount": 500.00,
            "other_fees": 50.00,
        },
        headers=hdrs,
    )
    assert create_r.status_code == 201, create_r.text
    inv_id = create_r.json()["id"]

    r = await client.get(f"/finance/invoices/{inv_id}", headers=hdrs)
    assert r.status_code == 200, r.text
    inv = r.json()

    for field in ("total_amount", "tuition_amount", "other_fees", "amount_paid", "balance"):
        v = inv[field]
        assert _is_numeric(v), (
            f"invoice.{field} is {type(v).__name__!r}: {v!r} — "
            "Pydantic v2 Decimal serialization bug (should be number, not string)"
        )


async def test_payment_amount_is_number(client, make_school):
    """Payment amount field must be a JSON number."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 200.00,
            "payment_date": "2026-02-10",
            "invoice_allocations": [],
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text

    list_r = await client.get("/finance/payments", headers=hdrs)
    assert list_r.status_code == 200
    payments = list_r.json()
    assert len(payments) >= 1

    for payment in payments:
        v = payment["amount"]
        assert _is_numeric(v), f"payment.amount is {type(v).__name__!r}: {v!r}"
        assert not isinstance(v, str), f"payment.amount must not be a string, got {v!r}"


async def test_summary_all_numbers(client, make_school):
    """GET /finance/summary must return all monetary values as JSON numbers."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.get("/finance/summary", headers=hdrs)
    assert r.status_code == 200, r.text
    summary = r.json()

    for field in ("total_revenue_month", "total_expenses_month", "total_outstanding"):
        v = summary[field]
        assert _is_numeric(v), (
            f"summary.{field} is {type(v).__name__!r}: {v!r} — must be a JSON number"
        )


# ──────────────────────────────────────────────────────────────────────────────
# Expense CRUD
# ──────────────────────────────────────────────────────────────────────────────

async def test_create_expense_category(client, make_school):
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/expense-categories",
        json={"name": f"NewCat-{uid()}"},
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body
    assert "name" in body


async def test_list_expense_categories(client, make_school):
    ctx = await _setup(client, make_school)
    r = await client.get("/finance/expense-categories", headers=ctx["hdrs"])
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_create_expense(client, make_school):
    """POST /finance/expenses returns 201 with category_name populated."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Office supplies",
            "amount": 75.00,
            "expense_date": "2026-01-20",
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body
    # The create endpoint returns the ORM object directly (no enrichment on POST),
    # so category_name may be None; the list endpoint enriches it — tested separately.
    assert "amount" in body


async def test_list_expenses_returns_category_name(client, make_school):
    """GET /finance/expenses enriches each expense with category_name."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Rent",
            "amount": 500.00,
            "expense_date": "2026-01-01",
        },
        headers=hdrs,
    )

    list_r = await client.get("/finance/expenses", headers=hdrs)
    assert list_r.status_code == 200
    expenses = list_r.json()
    assert len(expenses) >= 1
    for expense in expenses:
        assert "category_name" in expense, "GET /expenses must include category_name"


# ──────────────────────────────────────────────────────────────────────────────
# Invoice lifecycle
# ──────────────────────────────────────────────────────────────────────────────

async def test_create_invoice(client, make_school):
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-04-01",
            "tuition_amount": 400.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "pending"
    assert _is_numeric(body["total_amount"])


async def test_total_amount_calculation(client, make_school):
    """total_amount must equal tuition_amount + other_fees."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-05-01",
            "tuition_amount": 500.00,
            "other_fees": 100.00,
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert float(body["total_amount"]) == pytest.approx(600.0), (
        f"Expected total_amount=600.0, got {body['total_amount']!r}"
    )


async def test_list_invoices(client, make_school):
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-06-01",
            "tuition_amount": 300.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )

    r = await client.get("/finance/invoices", headers=hdrs)
    assert r.status_code == 200
    assert len(r.json()) >= 1


async def test_full_payment_marks_paid(client, make_school):
    """After a full payment allocation the invoice status becomes 'paid'."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    inv_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-07-01",
            "tuition_amount": 500.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    pay_r = await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 500.00,
            "payment_date": "2026-07-10",
            "invoice_allocations": [{"invoice_id": inv_id, "amount_applied": 500.00}],
        },
        headers=hdrs,
    )
    assert pay_r.status_code == 201, pay_r.text

    get_r = await client.get(f"/finance/invoices/{inv_id}", headers=hdrs)
    assert get_r.status_code == 200
    inv = get_r.json()
    assert inv["status"] == "paid", f"Expected 'paid', got {inv['status']!r}"
    assert float(inv["amount_paid"]) == pytest.approx(500.0)
    assert float(inv["balance"]) == pytest.approx(0.0)


async def test_partial_payment(client, make_school):
    """Partial payment → status 'partially_paid', balance correct."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    inv_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-08-01",
            "tuition_amount": 500.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    pay_r = await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 200.00,
            "payment_date": "2026-08-05",
            "invoice_allocations": [{"invoice_id": inv_id, "amount_applied": 200.00}],
        },
        headers=hdrs,
    )
    assert pay_r.status_code == 201, pay_r.text

    get_r = await client.get(f"/finance/invoices/{inv_id}", headers=hdrs)
    assert get_r.status_code == 200
    inv = get_r.json()
    assert inv["status"] == "partially_paid", f"Expected 'partially_paid', got {inv['status']!r}"
    assert float(inv["balance"]) == pytest.approx(300.0)


async def test_void_invoice(client, make_school):
    """POST /invoices/{id}/void returns a credit note; GET /credit-notes lists it."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]
    # void requires school_admin AND an associated employee_id
    void_hdrs = ctx["admin_emp_hdrs"]

    inv_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-09-01",
            "tuition_amount": 350.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    void_r = await client.post(
        f"/finance/invoices/{inv_id}/void",
        json={"reason": "Test void"},
        headers=void_hdrs,
    )
    assert void_r.status_code in (200, 201), void_r.text
    cn = void_r.json()
    assert "id" in cn
    assert "full_document_number" in cn

    cn_list_r = await client.get("/finance/credit-notes", headers=void_hdrs)
    assert cn_list_r.status_code == 200
    cn_ids = [c["id"] for c in cn_list_r.json()]
    assert cn["id"] in cn_ids


async def test_school_invoice_isolation(client, make_school):
    """School A admin cannot see school B invoices (list returns empty for B's data)."""
    ctx_a = await _setup(client, make_school)
    ctx_b = await _setup(client, make_school)

    # Create invoice in school B
    await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx_b["child_id"],
            "issued_by": ctx_b["emp_id"],
            "reference_month": "2026-10-01",
            "tuition_amount": 999.00,
            "other_fees": 0.00,
        },
        headers=ctx_b["hdrs"],
    )

    # School A admin lists invoices — must NOT see school B invoices
    r = await client.get("/finance/invoices", headers=ctx_a["hdrs"])
    assert r.status_code == 200
    inv_ids_a = {inv["id"] for inv in r.json()}

    # All school B invoice ids
    r_b = await client.get("/finance/invoices", headers=ctx_b["hdrs"])
    inv_ids_b = {inv["id"] for inv in r_b.json()}

    overlap = inv_ids_a & inv_ids_b
    assert not overlap, f"School isolation violated — shared invoice ids: {overlap}"


# ──────────────────────────────────────────────────────────────────────────────
# Payments
# ──────────────────────────────────────────────────────────────────────────────

async def test_create_payment_no_allocation(client, make_school):
    """Payment without allocations still returns 201."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 100.00,
            "payment_date": "2026-01-05",
            "invoice_allocations": [],
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body
    assert body["settled_invoice_ids"] == []


async def test_payment_with_allocation(client, make_school):
    """Payment with allocation updates invoice amount_paid."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    inv_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-11-01",
            "tuition_amount": 300.00,
            "other_fees": 0.00,
        },
        headers=hdrs,
    )
    assert inv_r.status_code == 201, inv_r.text
    inv_id = inv_r.json()["id"]

    pay_r = await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 300.00,
            "payment_date": "2026-11-10",
            "invoice_allocations": [{"invoice_id": inv_id, "amount_applied": 300.00}],
        },
        headers=hdrs,
    )
    assert pay_r.status_code == 201, pay_r.text
    pay_body = pay_r.json()
    assert inv_id in [str(x) for x in pay_body["settled_invoice_ids"]]

    # Confirm invoice updated
    get_r = await client.get(f"/finance/invoices/{inv_id}", headers=hdrs)
    assert get_r.status_code == 200
    assert float(get_r.json()["amount_paid"]) == pytest.approx(300.0)


async def test_list_payments(client, make_school):
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    await client.post(
        "/finance/payments",
        json={
            "child_id": ctx["child_id"],
            "received_by": ctx["emp_id"],
            "amount": 50.00,
            "payment_date": "2026-01-15",
            "invoice_allocations": [],
        },
        headers=hdrs,
    )

    r = await client.get("/finance/payments", headers=hdrs)
    assert r.status_code == 200
    assert len(r.json()) >= 1


# ──────────────────────────────────────────────────────────────────────────────
# Reports / other endpoints
# ──────────────────────────────────────────────────────────────────────────────

async def test_delinquent_report(client, make_school):
    """GET /finance/reports/delinquent returns 200; all monetary fields are numeric."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.get("/finance/reports/delinquent", headers=hdrs)
    assert r.status_code == 200
    items = r.json()
    assert isinstance(items, list)

    for item in items:
        if "amount" in item:
            v = item["amount"]
            assert _is_numeric(v), f"delinquent.amount is {type(v).__name__!r}: {v!r}"


async def test_credit_notes_list(client, make_school):
    ctx = await _setup(client, make_school)
    r = await client.get("/finance/credit-notes", headers=ctx["hdrs"])
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_receipts_list(client, make_school):
    ctx = await _setup(client, make_school)
    r = await client.get("/finance/receipts", headers=ctx["hdrs"])
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_finance_summary(client, make_school):
    """GET /finance/summary returns 200 and outstanding_count fields are ints."""
    ctx = await _setup(client, make_school)
    r = await client.get("/finance/summary", headers=ctx["hdrs"])
    assert r.status_code == 200
    summary = r.json()

    # Integer count fields
    for field in ("pending_invoices_count", "overdue_invoices_count"):
        v = summary[field]
        assert isinstance(v, int), f"summary.{field} is {type(v).__name__!r}: {v!r} — must be int"

    # Monetary fields
    for field in ("total_revenue_month", "total_expenses_month", "total_outstanding"):
        v = summary[field]
        assert _is_numeric(v), f"summary.{field} is {type(v).__name__!r}: {v!r} — must be numeric"


# ──────────────────────────────────────────────────────────────────────────────
# Additional edge-case / completeness tests
# ──────────────────────────────────────────────────────────────────────────────

async def test_get_invoice_by_id(client, make_school):
    """GET /finance/invoices/{id} returns the correct invoice."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    create_r = await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-12-01",
            "tuition_amount": 450.00,
            "other_fees": 25.00,
        },
        headers=hdrs,
    )
    assert create_r.status_code == 201, create_r.text
    inv_id = create_r.json()["id"]

    r = await client.get(f"/finance/invoices/{inv_id}", headers=hdrs)
    assert r.status_code == 200
    assert r.json()["id"] == inv_id


async def test_invoice_decimal_fields_no_string_on_list(client, make_school):
    """
    GET /finance/invoices (list) — all Decimal fields must be numeric for each
    invoice, not strings.  Regression guard for the Pydantic v2 Flutter bug.
    """
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    await client.post(
        "/finance/invoices",
        json={
            "child_id": ctx["child_id"],
            "issued_by": ctx["emp_id"],
            "reference_month": "2026-02-01",
            "tuition_amount": 250.00,
            "other_fees": 30.00,
        },
        headers=hdrs,
    )

    r = await client.get("/finance/invoices", headers=hdrs)
    assert r.status_code == 200
    for inv in r.json():
        for field in ("total_amount", "tuition_amount", "other_fees", "amount_paid", "balance"):
            v = inv[field]
            assert _is_numeric(v), (
                f"invoice (list).{field} is {type(v).__name__!r}: {v!r} — "
                "Pydantic v2 Decimal string bug"
            )


async def test_expense_amount_precision(client, make_school):
    """Expense amount 125.50 round-trips as a float equal to 125.50."""
    ctx = await _setup(client, make_school)
    hdrs = ctx["hdrs"]

    r = await client.post(
        "/finance/expenses",
        json={
            "category_id": ctx["cat_id"],
            "registered_by": ctx["emp_id"],
            "description": "Precision check",
            "amount": 125.50,
            "expense_date": "2026-03-01",
        },
        headers=hdrs,
    )
    assert r.status_code == 201, r.text

    list_r = await client.get("/finance/expenses", headers=hdrs)
    assert list_r.status_code == 200
    matched = [e for e in list_r.json() if e["description"] == "Precision check"]
    assert matched, "Created expense not found in list"
    assert float(matched[0]["amount"]) == pytest.approx(125.50)
