# -*- coding: utf-8 -*-
"""Phase 2 read models: debts, service report and the finance dashboard.

The director's questions are "who owes what, per student and per service"
and "how much did each service bill this period". Both answers come from
whichever engine owns the school; in FinReg mode FinReg computes every
balance and Cellen only maps the school vocabulary onto it.
"""
import uuid
from datetime import date, timedelta

import pytest

from app.core.config import settings
from app.models.billing import BillingRun
from app.services.billing_run import current_billing_month
from app.services.debt_control import dashboard, list_debts, service_report
from app.services.finreg import FakeFinregAdapter
from app.utils.agt import today_luanda
from tests.test_finance_phases import (
    _activate_finreg,
    _family,
    _item,
    _scaffold,
)


def _receivable(
    *,
    guardian_id: str,
    child_id: str,
    child_name: str,
    document_number: str,
    due: date,
    amount: float,
    lines: list[dict],
    bucket: str,
) -> dict:
    return {
        "document_id": str(uuid.uuid4()),
        "document_external_id": f"doc-{uuid.uuid4().hex[:8]}",
        "full_document_number": document_number,
        "document_type": "FT",
        "document_status": "finalized",
        "document_date": due.isoformat(),
        "due_date": due.isoformat(),
        "customer_external_id": guardian_id,
        "customer_name": "Maria Guard",
        "currency_code": "AOA",
        "gross_total": amount,
        "credited_total": 0.0,
        "paid_total": 0.0,
        "outstanding_amount": amount,
        "days_overdue": max((today_luanda() - due).days, 0),
        "bucket": bucket,
        "school_context": {"pupil_id": child_id, "pupil_name": child_name},
        "lines": lines,
    }


def _line(product_id: str, description: str, amount: float) -> dict:
    return {
        "product_external_id": product_id,
        "description": description,
        "quantity": 1.0,
        "net_amount": amount,
        "tax_amount": 0.0,
        "gross_amount": amount,
    }


@pytest.mark.asyncio
async def test_debts_group_by_student_and_by_school_service(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "debt-read")
    await _activate_finreg(client, ctx, "fake")
    family = await _family(client, ctx)
    tuition = await _item(client, ctx, "Propina", 0)
    transport = await _item(client, ctx, "Transporte", 0)

    past = today_luanda() - timedelta(days=15)
    future = today_luanda() + timedelta(days=10)
    payload = {
        "as_of": today_luanda().isoformat(),
        "count": 2,
        "total_outstanding": 140000.0,
        "rows": [
            _receivable(
                guardian_id=family["guardian"]["id"],
                child_id=family["child"]["id"],
                child_name="Ana Test",
                document_number="FT 2026/1",
                due=past,
                amount=100000.0,
                bucket="bucket_0_30",
                lines=[_line(tuition["id"], "Propina de Outubro", 100000.0)],
            ),
            _receivable(
                guardian_id=family["guardian"]["id"],
                child_id=family["child"]["id"],
                child_name="Ana Test",
                document_number="FT 2026/2",
                due=future,
                amount=40000.0,
                bucket="current",
                lines=[
                    _line(transport["id"], "Transporte de Outubro", 40000.0)
                ],
            ),
        ],
    }
    adapter = FakeFinregAdapter(outcomes={"GET receivables": payload})

    result = await list_debts(db, school_id=ctx["school_id"], adapter=adapter)

    assert result["mode"] == "fake"
    assert result["count"] == 2
    assert result["total_outstanding"] == 140000.0
    assert result["total_overdue"] == 100000.0
    assert len(result["rows"]) == 2
    first = result["rows"][0]
    assert first["student_id"] == family["child"]["id"]
    assert first["student_name"] == "Ana Test"
    assert first["guardian_id"] == family["guardian"]["id"]
    assert first["services"][0]["service_label"] == "Propina"
    assert first["services"][0]["outstanding_amount"] == 100000.0

    # One student, two documents: the director sees a single row per child.
    assert len(result["by_student"]) == 1
    assert result["by_student"][0]["outstanding"] == 140000.0
    assert result["by_student"][0]["overdue"] == 100000.0
    assert result["by_student"][0]["documents"] == 2
    services = {row["service_label"]: row for row in result["by_service"]}
    assert services["Propina"]["outstanding"] == 100000.0
    assert services["Transporte"]["outstanding"] == 40000.0
    assert result["by_bucket"]["current"] == 40000.0
    assert result["by_bucket"]["bucket_0_30"] == 100000.0


@pytest.mark.asyncio
async def test_the_overdue_and_service_filters_use_finreg_balances(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "debt-filter")
    await _activate_finreg(client, ctx, "fake")
    family = await _family(client, ctx)
    tuition = await _item(client, ctx, "Propina", 0)
    adapter = FakeFinregAdapter(
        outcomes={
            "GET receivables": {
                "as_of": today_luanda().isoformat(),
                "count": 1,
                "total_outstanding": 75000.0,
                "rows": [
                    _receivable(
                        guardian_id=family["guardian"]["id"],
                        child_id=family["child"]["id"],
                        child_name="Ana Test",
                        document_number="FT 2026/9",
                        due=today_luanda() - timedelta(days=5),
                        amount=75000.0,
                        bucket="bucket_0_30",
                        lines=[_line(tuition["id"], "Propina", 75000.0)],
                    )
                ],
            }
        }
    )

    overdue = await list_debts(
        db, school_id=ctx["school_id"], overdue_only=True, adapter=adapter
    )
    assert overdue["overdue_only"] is True
    assert overdue["count"] == 1, "the adapter already filtered; balance stays FinReg's"

    service = await list_debts(
        db, school_id=ctx["school_id"], service=str(tuition["id"]), adapter=adapter
    )
    assert service["count"] == 1
    missing = await list_debts(
        db, school_id=ctx["school_id"], service="Balé", adapter=adapter
    )
    assert missing["count"] == 0
    assert missing["total_outstanding"] == 0.0


@pytest.mark.asyncio
async def test_service_report_labels_finreg_rows_with_school_terms(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "svc-report")
    await _activate_finreg(client, ctx, "fake")
    tuition = await _item(client, ctx, "Propina", 0)
    adapter = FakeFinregAdapter(
        outcomes={
            "GET reports/sales-by-product": [
                {
                    "product_id": str(uuid.uuid4()),
                    "product_external_id": tuition["id"],
                    "description": "Propina Outubro",
                    "total_qty": 12.0,
                    "total_net": 1200000.0,
                    "total_tax": 0.0,
                    "total_gross": 1200000.0,
                }
            ]
        }
    )

    today = today_luanda()
    report = await service_report(
        db,
        school_id=ctx["school_id"],
        date_from=today.replace(day=1),
        date_to=today,
        adapter=adapter,
    )

    assert report["mode"] == "fake"
    assert report["services"][0]["service"] == tuition["id"]
    assert report["services"][0]["service_label"] == "Propina"
    assert report["services"][0]["quantity"] == 12.0
    assert report["totals"]["gross_total"] == 1200000.0


@pytest.mark.asyncio
async def test_the_dashboard_combines_debts_sales_and_collections(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "dash-read")
    await _activate_finreg(client, ctx, "fake")
    family = await _family(client, ctx)
    tuition = await _item(client, ctx, "Propina", 0)
    adapter = FakeFinregAdapter(
        outcomes={
            "GET receivables": {
                "as_of": today_luanda().isoformat(),
                "count": 1,
                "total_outstanding": 50000.0,
                "rows": [
                    _receivable(
                        guardian_id=family["guardian"]["id"],
                        child_id=family["child"]["id"],
                        child_name="Ana Test",
                        document_number="FT 2026/3",
                        due=today_luanda() - timedelta(days=2),
                        amount=50000.0,
                        bucket="bucket_0_30",
                        lines=[_line(tuition["id"], "Propina", 50000.0)],
                    )
                ],
            },
            "GET reports/sales-summary": {
                "period": {},
                "invoice_count": 9,
                "total_net": 800000.0,
                "total_tax": 0.0,
                "total_gross": 800000.0,
            },
            "GET reports/collections-summary": {
                "period": {},
                "payment_count": 4,
                "total_collected": 300000.0,
                "by_method": [],
            },
        }
    )

    result = await dashboard(db, school_id=ctx["school_id"], adapter=adapter)

    assert result["mode"] == "fake"
    assert result["debts"]["total_outstanding"] == 50000.0
    assert result["debts"]["total_overdue"] == 50000.0
    assert result["sales"]["invoice_count"] == 9
    assert result["sales"]["total_gross"] == 800000.0
    assert result["collections"]["payment_count"] == 4
    assert result["collections"]["total_collected"] == 300000.0
    # No run and no policy row: the month reads as "not generated" with the
    # virtual defaults (billing day 1, five due days).
    month = result["month"]
    assert month["billing_month"] == current_billing_month()
    assert month["generated"] is False
    assert month["status"] is None
    assert month["students"] is None
    assert month["failed"] is None
    assert month["total"] is None
    assert month["auto_generate"] is False
    expected_due = today_luanda().replace(day=1) + timedelta(days=5)
    assert month["due_date"] == expected_due.isoformat()


@pytest.mark.asyncio
async def test_the_dashboard_month_reflects_the_generation_run(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "dash-month")
    await _activate_finreg(client, ctx, "fake")
    due = (today_luanda() + timedelta(days=12)).isoformat()
    db.add(
        BillingRun(
            school_id=ctx["school_id"],
            school_year_id=uuid.UUID(ctx["year"]["id"]),
            billing_month=current_billing_month(),
            status="completed",
            mode="fake",
            stats={
                "students": 22,
                "generated": 22,
                "failed": 0,
                "totals": {"total": 5610000.0},
                "due_date": due,
                "policy": {"auto_generate": True},
            },
        )
    )
    await db.commit()

    result = await dashboard(
        db, school_id=ctx["school_id"], adapter=FakeFinregAdapter()
    )

    month = result["month"]
    assert month["billing_month"] == current_billing_month()
    assert month["generated"] is True
    assert month["status"] == "completed"
    assert month["students"] == 22
    assert month["failed"] == 0
    assert month["total"] == 5610000.0
    assert month["due_date"] == due
    # No policy row exists; the run's snapshot is the only record of the flag.
    assert month["auto_generate"] is True
