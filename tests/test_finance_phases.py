# -*- coding: utf-8 -*-
"""Phases 3-5: late-fee bands, dunning ladder and reference payments.

The director's own examples are the acceptance cases:

* 10% on days 10-30 of the current month, 15% from day 10 of the next;
* the fee is a top-up, never two full percentages on one document;
* a FinReg-active school gets a FinReg debit note and no local invoice;
* a re-run never issues a second multa;
* dunning sends each rung once, skips stale rungs, and records why a
  channel did not go out.
"""
import uuid
from datetime import date, timedelta
from decimal import Decimal

import httpx
import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.config import settings
from app.models.billing import DunningDelivery, LateFeeAssessment
from app.models.finance import Invoice, PaymentReference, Receipt
from app.models.finreg_integration import FinregBillingInstruction
from app.services.finreg import FakeFinregAdapter
from app.services.late_fees import (
    band_active_on,
    band_fee,
    band_window,
    resolve_active_band,
    validate_bands,
)
from app.services.billing_run import BillingError
from app.utils.agt import today_luanda
from tests.conftest import auth, uid

BANDS = [
    {
        "id": "current-10",
        "label": "10% até ao fim do mês",
        "anchor": "due_month",
        "start_day": 10,
        "end_day": None,
        "percent": 10,
    },
    {
        "id": "next-15",
        "label": "15% a partir do dia 10 do mês seguinte",
        "anchor": "next_month",
        "start_day": 10,
        "end_day": None,
        "percent": 15,
    },
]


# ─── pure band semantics ────────────────────────────────────────────────────


def test_director_bands_open_on_the_10th_of_each_month():
    due = date(2026, 1, 5)
    first = BANDS[0]
    second = BANDS[1]
    assert band_window(first, due) == (date(2026, 1, 10), date(2026, 1, 31))
    assert band_window(second, due) == (date(2026, 2, 10), date(2026, 2, 28))
    assert not band_active_on(first, due, date(2026, 1, 9))
    assert band_active_on(first, due, date(2026, 1, 20))
    assert not band_active_on(second, due, date(2026, 1, 20))
    assert band_active_on(second, due, date(2026, 2, 12))


def test_band_windows_clamp_to_short_months():
    due = date(2026, 1, 31)
    assert band_window(BANDS[1], due) == (date(2026, 2, 10), date(2026, 2, 28))
    capped = dict(BANDS[0], start_day=28, end_day=31)
    assert band_window(capped, date(2026, 2, 1)) == (
        date(2026, 2, 28),
        date(2026, 2, 28),
    )


def test_resolution_picks_the_highest_active_band():
    due = date(2026, 1, 5)
    assert resolve_active_band(BANDS, due, date(2026, 1, 9)) is None
    assert resolve_active_band(BANDS, due, date(2026, 1, 20))["id"] == "current-10"
    assert resolve_active_band(BANDS, due, date(2026, 2, 12))["id"] == "next-15"


def test_fee_uses_the_top_up_percent_and_honours_caps():
    plain = {"id": "b", "percent": 10}
    assert band_fee(plain, Decimal("100000"), Decimal("10")) == Decimal("10000.00")
    assert band_fee(plain, Decimal("100000"), Decimal("5")) == Decimal("5000.00")
    capped = dict(plain, min_amount=500, max_amount=3000)
    assert band_fee(capped, Decimal("1000"), Decimal("10")) == Decimal("500.00")
    assert band_fee(capped, Decimal("100000"), Decimal("10")) == Decimal("3000.00")


def test_band_validation_rejects_ambiguous_policy():
    with pytest.raises(BillingError) as duplicate:
        validate_bands([BANDS[0], BANDS[0]])
    assert duplicate.value.code == "late_fee_band_duplicate"
    with pytest.raises(BillingError) as inverted:
        validate_bands([dict(BANDS[0], start_day=20, end_day=5)])
    assert inverted.value.code == "late_fee_band_day"
    with pytest.raises(BillingError) as zero:
        validate_bands([dict(BANDS[0], percent=0)])
    assert zero.value.code == "late_fee_band_percent"


# ─── scaffolding ────────────────────────────────────────────────────────────


async def _scaffold(client: AsyncClient, make_school, prefix: str) -> dict:
    school, token, slug, _ = await make_school(prefix)
    headers = auth(token)
    first = today_luanda().replace(day=1)
    year = (
        await client.post(
            "/schools/school-years",
            json={
                "year_label": f"SY-{uid()}",
                "start_date": first.isoformat(),
                "end_date": date(first.year + 1, 12, 31).isoformat(),
                "is_active": True,
            },
            headers=headers,
        )
    ).json()
    return {
        "school": school,
        "school_id": uuid.UUID(school["id"]),
        "headers": headers,
        "year": year,
        "first": first,
    }


async def _item(client: AsyncClient, ctx: dict, name: str, price) -> dict:
    response = await client.post(
        "/finance/billing-items",
        json={
            "code": f"{uid()}-{name[:3].upper()}",
            "name": name,
            "unit_price": price,
            "iva_rate": 0,
            "finreg_tax_option_code": "IVA_ISE",
            "iva_exemption_reason": "M10",
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _policy(client: AsyncClient, ctx: dict, **overrides) -> dict:
    body = {
        "school_year_id": ctx["year"]["id"],
        "default_tuition_billing_item_id": None,
        "default_enrollment_fee": None,
        "sibling_discount_pct": 5,
        "sibling_discount_min_children": 2,
        "sibling_discount_scope": "additional_children",
        "due_days": 5,
        "billing_day": 1,
        "auto_generate": False,
        "proration_policy": "pro_rata_days",
    }
    body.update(overrides)
    response = await client.put("/billing/fee-policy", json=body, headers=ctx["headers"])
    assert response.status_code == 200, response.text
    return response.json()


async def _family(client: AsyncClient, ctx: dict) -> dict:
    guardian = (
        await client.post(
            "/guardians",
            json={
                "first_name": "Maria",
                "last_name": f"Guard{uid()[:4]}",
                "email": f"g-{uid()}@example.com",
                "username": f"grd-{uid()}",
                "password": "Guardian1!",
            },
            headers=ctx["headers"],
        )
    ).json()
    child = (
        await client.post(
            "/children",
            json={"cedula": f"C{uid()}", "first_name": "Ana", "last_name": "Test"},
            headers=ctx["headers"],
        )
    ).json()
    link = await client.post(
        f"/guardians/{guardian['id']}/children",
        json={
            "child_id": child["id"],
            "relationship_type": "mother",
            "is_primary_contact": True,
        },
        headers=ctx["headers"],
    )
    assert link.status_code == 201, link.text
    return {"guardian": guardian, "child": child}


async def _invoice(client: AsyncClient, ctx: dict, family: dict, due: date, amount: int) -> dict:
    response = await client.post(
        "/finance/invoices",
        json={
            "billing_guardian_id": family["guardian"]["id"],
            "child_id": family["child"]["id"],
            "due_date": due.isoformat(),
            "reference_month": due.replace(day=1).isoformat(),
            "lines": [
                {"description": "Mensalidade", "quantity": 1, "unit_price": amount}
            ],
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _activate_finreg(client: AsyncClient, ctx: dict, mode: str) -> None:
    response = await client.put(
        "/finreg/connection",
        json={
            "finreg_company_id": str(uuid.uuid4()),
            "mode": mode,
            "kill_switch": False,
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 200, response.text


def _finreg_receivable(due: date, guardian_id: str, child_id: str, amount: float) -> dict:
    return {
        "as_of": today_luanda().isoformat(),
        "count": 1,
        "total_outstanding": amount,
        "rows": [
            {
                "document_id": str(uuid.uuid4()),
                "document_external_id": f"doc-{uid()}",
                "full_document_number": f"FT {uid()}/2026",
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
                "days_overdue": (today_luanda() - due).days,
                "bucket": "1-30",
                "school_context": {
                    "pupil_id": child_id,
                    "pupil_name": "Ana Test",
                },
                "lines": [],
            }
        ],
    }


# ─── late fees: internal parity ─────────────────────────────────────────────


@pytest.mark.asyncio
async def test_internal_late_fee_issues_one_nd_and_never_duplicates(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "late-internal")
    item = await _item(client, ctx, "Multa", 0)
    await _policy(
        client,
        ctx,
        late_fee_enabled=True,
        late_fee_billing_item_id=item["id"],
        late_fee_base="outstanding",
        late_fee_bands=BANDS,
    )
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 50000)

    dry = await client.post(
        "/billing/late-fees/assess",
        json={"dry_run": True},
        headers=ctx["headers"],
    )
    assert dry.status_code == 200, dry.text
    preview = dry.json()
    assert preview["preview_only"] is True
    assert preview["created"][0]["incremental_percent"] == 10
    assert preview["created"][0]["fee_amount"] == 5000
    assert (
        await db.execute(
            select(func.count())
            .select_from(LateFeeAssessment)
            .where(LateFeeAssessment.school_id == ctx["school_id"])
        )
    ).scalar_one() == 0

    assessed = await client.post(
        "/billing/late-fees/assess", json={}, headers=ctx["headers"]
    )
    assert assessed.status_code == 200, assessed.text
    result = assessed.json()
    assert result["totals"]["count"] == 1
    assert result["created"][0]["fee_amount"] == 5000

    assessments = (
        await db.execute(
            select(LateFeeAssessment).where(
                LateFeeAssessment.school_id == ctx["school_id"]
            )
        )
    ).scalars().all()
    assert len(assessments) == 1
    assessment = assessments[0]
    assert assessment.status == "issued"
    assert assessment.internal_invoice_id is not None
    assert Decimal(assessment.fee_amount) == Decimal("5000.00")

    nd = await db.get(Invoice, assessment.internal_invoice_id)
    assert nd is not None and nd.document_type == "ND"
    assert nd.corrected_invoice_id == uuid.UUID(invoice["id"])

    again = await client.post(
        "/billing/late-fees/assess", json={}, headers=ctx["headers"]
    )
    assert again.status_code == 200, again.text
    assert again.json()["totals"]["count"] == 0
    assert again.json()["skipped"][0]["reason"] == "already_assessed"
    total_nd = (
        await db.execute(
            select(func.count())
            .select_from(Invoice)
            .where(Invoice.school_id == ctx["school_id"], Invoice.document_type == "ND")
        )
    ).scalar_one()
    assert total_nd == 1


# ─── late fees: FinReg path ─────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_finreg_late_fee_queues_one_debit_note_and_no_local_invoice(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "late-finreg")
    await _activate_finreg(client, ctx, "fake")
    item = await _item(client, ctx, "Multa", 0)
    await _policy(
        client,
        ctx,
        late_fee_enabled=True,
        late_fee_billing_item_id=item["id"],
        late_fee_base="outstanding",
        late_fee_bands=BANDS,
    )
    family = await _family(client, ctx)
    adapter = FakeFinregAdapter(
        outcomes={
            "GET receivables": _finreg_receivable(
                ctx["first"],
                family["guardian"]["id"],
                family["child"]["id"],
                50000.0,
            )
        }
    )

    from app.services.late_fees import assess_late_fees

    first = await assess_late_fees(
        db, school_id=ctx["school_id"], adapter=adapter
    )
    assert first["totals"]["count"] == 1
    instruction = (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == ctx["school_id"],
                FinregBillingInstruction.command_type == "late_fee",
            )
        )
    ).scalar_one()
    assert instruction.status == "confirmed"
    assert instruction.finreg_document_id is not None
    assessment = (
        await db.execute(
            select(LateFeeAssessment).where(
                LateFeeAssessment.school_id == ctx["school_id"]
            )
        )
    ).scalar_one()
    assert assessment.status == "issued"
    assert assessment.finreg_debit_note_id == instruction.finreg_document_id
    local_docs = (
        await db.execute(
            select(func.count())
            .select_from(Invoice)
            .where(Invoice.school_id == ctx["school_id"])
        )
    ).scalar_one()
    assert local_docs == 0

    second = await assess_late_fees(
        db, school_id=ctx["school_id"], adapter=adapter
    )
    assert second["totals"]["count"] == 0
    assert second["skipped"][0]["reason"] == "already_assessed"
    instructions = (
        await db.execute(
            select(func.count())
            .select_from(FinregBillingInstruction)
            .where(
                FinregBillingInstruction.school_id == ctx["school_id"],
                FinregBillingInstruction.command_type == "late_fee",
            )
        )
    ).scalar_one()
    assert instructions == 1


def test_the_late_fee_body_carries_the_host_identity_finreg_requires():
    """The fake adapter must not hide a contract mismatch.

    FinReg's ``POST /integrations/receivables/{id}/debit-note`` requires
    ``external_id`` so a retry maps to the note already issued. The body is
    built once and sent unchanged by both adapters.
    """
    from app.models.finance import BillingItem
    from app.services.late_fees import _finreg_payload

    source_id = uuid.uuid4()
    assessment = LateFeeAssessment(
        id=uuid.uuid4(),
        school_id=uuid.uuid4(),
        source_kind="finreg_document",
        source_id=source_id,
        band_id="current-10",
        band_percent=Decimal("10"),
        incremental_percent=Decimal("10"),
        base_amount=Decimal("50000"),
        fee_amount=Decimal("5000"),
        status="pending",
        document_number="FT 2026/7",
    )
    item = BillingItem(
        id=uuid.uuid4(),
        school_id=assessment.school_id,
        code="MULTA",
        name="Multa por atraso",
        iva_rate=Decimal("14"),
        finreg_tax_option_code="IVA-REG",
    )
    payload = _finreg_payload(
        {"document_id": str(source_id)},
        assessment,
        item,
        actor_reference="test",
    )
    body = payload["debit_note"]
    assert body["external_id"] == str(assessment.id)
    assert body["net_amount"] == "5000"
    assert body["tax_rate"] == "14"
    assert payload["document_id"] == str(source_id)


@pytest.mark.asyncio
async def test_a_late_fee_policy_cannot_be_saved_without_a_fiscal_item(
    client: AsyncClient, make_school, db,
):
    """The director cannot arm a ladder that would fail at midnight."""
    ctx = await _scaffold(client, make_school, "late-noitem")
    refused = await client.put(
        "/billing/fee-policy",
        json={
            "school_year_id": ctx["year"]["id"],
            "late_fee_enabled": True,
            "late_fee_billing_item_id": None,
            "late_fee_bands": BANDS,
        },
        headers=ctx["headers"],
    )
    assert refused.status_code == 422, refused.text
    assert refused.json()["detail"]["code"] == "late_fee_item_missing"
    assert (
        await db.execute(
            select(func.count())
            .select_from(LateFeeAssessment)
            .where(LateFeeAssessment.school_id == ctx["school_id"])
        )
    ).scalar_one() == 0


# ─── dunning ────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_dunning_fires_the_latest_rung_once_and_skips_stale_ones(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "dunning")
    await _policy(
        client,
        ctx,
        dunning_enabled=True,
        dunning_schedule=[
            {"level": 1, "offset_days": 5, "channels": ["in_app"]},
            {"level": 2, "offset_days": 30, "channels": ["in_app", "sms"]},
        ],
        dunning_message_template=(
            "Olá {guardian_name}: {document_number} tem {amount} AOA vencidos."
        ),
    )
    family = await _family(client, ctx)
    due = today_luanda() - timedelta(days=40)
    await _invoice(client, ctx, family, due, 12000)

    from app.services.dunning import run_dunning

    preview = await run_dunning(db, school_id=ctx["school_id"], dry_run=True)
    assert preview["enabled"] is True
    assert len(preview["planned"]) == 1
    plan = preview["planned"][0]
    assert plan["level"] == 2
    assert plan["channels"] == ["in_app", "sms"]
    assert plan["superseded_levels"] == [1]
    assert "12 000.00" in plan["message"]
    assert (
        await db.execute(
            select(func.count())
            .select_from(DunningDelivery)
            .where(DunningDelivery.school_id == ctx["school_id"])
        )
    ).scalar_one() == 0

    first = await run_dunning(db, school_id=ctx["school_id"])
    assert first["sent"] == 1
    assert first["skipped"] == 1  # sms has no provider

    deliveries = (
        await db.execute(
            select(DunningDelivery).where(
                DunningDelivery.school_id == ctx["school_id"]
            )
        )
    ).scalars().all()
    by_key = {(row.offset_days, row.channel): row for row in deliveries}
    assert by_key[(5, "in_app")].status == "skipped"
    assert by_key[(5, "in_app")].error == "superseded"
    assert by_key[(30, "in_app")].status == "sent"
    assert by_key[(30, "sms")].status == "skipped"
    assert by_key[(30, "sms")].error == "sms_not_configured"
    assert "12 000.00" in by_key[(30, "in_app")].message_snapshot

    second = await run_dunning(db, school_id=ctx["school_id"])
    assert second["sent"] == 0
    assert (
        await db.execute(
            select(func.count())
            .select_from(DunningDelivery)
            .where(DunningDelivery.school_id == ctx["school_id"])
        )
    ).scalar_one() == len(deliveries)


@pytest.mark.asyncio
async def test_dunning_is_disabled_until_the_school_opts_in(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "dunning-off")

    from app.services.dunning import run_dunning

    result = await run_dunning(db, school_id=ctx["school_id"])
    assert result["enabled"] is False
    assert result["reason"] == "disabled"
    assert result["sent"] == 0


# ─── reference payments ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_principia_pay_refuses_an_amount_above_the_debt(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-amount")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    from app.services import principia_pay

    with pytest.raises(BillingError) as refused:
        await principia_pay.create_reference(
            db,
            school_id=ctx["school_id"],
            document_id=invoice["id"],
            amount=Decimal("10001"),
        )
    assert refused.value.code == "amount_exceeds_outstanding"


@pytest.mark.asyncio
async def test_parent_cannot_open_a_reference_on_someone_elses_debt(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-owner")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    other_guardian = (
        await client.post(
            "/guardians",
            json={
                "first_name": "Outro",
                "last_name": "Encarregado",
                "username": f"grd2-{uid()}",
                "password": "Guardian1!",
            },
            headers=ctx["headers"],
        )
    ).json()
    other_child = (
        await client.post(
            "/children",
            json={"cedula": f"C{uid()}", "first_name": "B", "last_name": "Test"},
            headers=ctx["headers"],
        )
    ).json()
    await client.post(
        f"/guardians/{other_guardian['id']}/children",
        json={
            "child_id": other_child["id"],
            "relationship_type": "father",
            "is_primary_contact": True,
        },
        headers=ctx["headers"],
    )

    from app.services import principia_pay

    with pytest.raises(BillingError) as refused:
        await principia_pay.create_reference(
            db,
            school_id=ctx["school_id"],
            document_id=invoice["id"],
            guardian_id=uuid.UUID(other_guardian["id"]),
        )
    assert refused.value.code == "debt_not_found"


@pytest.mark.asyncio
async def test_reference_create_and_settle_settles_the_local_invoice(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """Rail says paid -> local intake books the payment and marks the ref paid."""
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-settle")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    from app.services import principia_pay
    from app.services.principia_pay_client import Reference, RegisteredClient

    async def fake_register(base_url, product_token, source_system, **kwargs):
        return RegisteredClient(id="cli-test", api_key="pp_key", callback_secret="cb_secret")

    async def fake_create(self, **kwargs):
        return Reference(
            id="rail-1",
            provider="appypay",
            caller_reference=kwargs.get("caller_reference"),
            kind="reference",
            entity="00123",
            reference="987654321",
            redirect_url=None,
            amount=kwargs["amount"],
            currency="AOA",
            status="pending",
            expires_at=None,
            paid_at=None,
            created_at=today_luanda(),
            checkout_url="https://rail.test/checkout/1",
        )

    async def fake_get(self, reference_id):
        return Reference(
            id=reference_id,
            provider="appypay",
            caller_reference=None,
            kind="reference",
            entity="00123",
            reference="987654321",
            redirect_url=None,
            amount=Decimal("10000.00"),
            currency="AOA",
            status="paid",
            expires_at=None,
            paid_at=today_luanda(),
            created_at=today_luanda(),
        )

    monkeypatch.setattr(principia_pay, "register_client", fake_register)
    monkeypatch.setattr(principia_pay.PrincipiaPayClient, "create_reference", fake_create)
    monkeypatch.setattr(principia_pay.PrincipiaPayClient, "get_reference", fake_get)

    reference = await principia_pay.create_reference(
        db, school_id=ctx["school_id"], document_id=invoice["id"]
    )
    assert reference.provider == "principia_pay"
    assert reference.status == "active"
    assert reference.checkout_url == "https://rail.test/checkout/1"
    assert reference.reference == "987654321"

    settled = await principia_pay.refresh_reference(db, reference=reference)
    assert settled.status == "paid"
    assert settled.paid_amount == Decimal("10000.00")

    refreshed_invoice = await client.get(
        f"/finance/invoices/{invoice['id']}", headers=ctx["headers"]
    )
    assert refreshed_invoice.status_code == 200, refreshed_invoice.text
    assert refreshed_invoice.json()["status"] == "paid"

    receipt_count = (
        await db.execute(
            select(func.count())
            .select_from(Receipt)
            .where(Receipt.school_id == ctx["school_id"])
        )
    ).scalar_one()
    assert receipt_count == 1


@pytest.mark.asyncio
async def test_callback_rejects_a_bad_signature(monkeypatch, client, make_school, db):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-sig")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    from app.services import principia_pay
    from app.services.principia_pay_client import Reference, RegisteredClient

    async def fake_register(base_url, product_token, source_system, **kwargs):
        return RegisteredClient(id="cli-test", api_key="pp_key", callback_secret="cb_secret")

    async def fake_create(self, **kwargs):
        return Reference(
            id="rail-9", provider="appypay",
            caller_reference=kwargs.get("caller_reference"), kind="reference",
            entity="00123", reference="111222333", redirect_url=None,
            amount=kwargs["amount"], currency="AOA", status="pending",
            expires_at=None, paid_at=None, created_at=today_luanda(),
        )

    monkeypatch.setattr(principia_pay, "register_client", fake_register)
    monkeypatch.setattr(principia_pay.PrincipiaPayClient, "create_reference", fake_create)

    reference = await principia_pay.create_reference(
        db, school_id=ctx["school_id"], document_id=invoice["id"]
    )
    body = (
        '{"id":"evt-1","provider":"appypay","caller_reference":"%s",'
        '"external_session_id":"x","status":"paid","amount":"10000.00",'
        '"currency":"AOA","paid_at":null}' % reference.caller_reference
    ).encode()

    with pytest.raises(BillingError) as refused:
        await principia_pay.handle_callback(db, body=body, signature="deadbeef")
    assert refused.value.code == "invalid_signature"

    import hashlib
    import hmac

    good = hmac.new(b"cb_secret", body, hashlib.sha256).hexdigest()
    monkeypatch.setattr(
        principia_pay.PrincipiaPayClient,
        "get_reference",
        lambda self, reference_id: _paid_rail(reference_id),
    )
    result = await principia_pay.handle_callback(db, body=body, signature=good)
    assert result["status"] == "ok"
    assert result["reference_status"] == "paid"


# ─── debt filters and rail resilience ──────────────────────────────────────


@pytest.mark.asyncio
async def test_debts_bucket_filter_narrows_and_rejects_unknown_bucket(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "buckets")
    family = await _family(client, ctx)
    await _invoice(
        client, ctx, family, today_luanda() - timedelta(days=10), 10000
    )
    await _invoice(
        client, ctx, family, today_luanda() - timedelta(days=70), 20000
    )

    response = await client.get(
        "/billing/debts", params={"bucket": "bucket_0_30"}, headers=ctx["headers"]
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["bucket"] == "bucket_0_30"
    assert body["count"] == 1
    assert body["rows"][0]["bucket"] == "bucket_0_30"

    refused = await client.get(
        "/billing/debts", params={"bucket": "not-a-bucket"}, headers=ctx["headers"]
    )
    assert refused.status_code == 422
    assert refused.json()["detail"]["code"] == "invalid_bucket"


@pytest.mark.asyncio
async def test_a_non_uuid_guardian_id_is_a_clean_409(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """A legacy guardian id must not reach uuid.UUID() as an unhandled 500."""
    ctx = await _scaffold(client, make_school, "rail-legacy-owner")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    from app.services import principia_pay

    async def fake_open_debt(*args, **kwargs):
        return {
            "source": "internal",
            "document_id": invoice["id"],
            "document_number": "FT LEGACY/2026",
            "outstanding": 10000.0,
            "guardian_id": "legacy-guardian-7",
            "currency_code": "AOA",
        }

    monkeypatch.setattr(principia_pay, "_open_debt_row", fake_open_debt)

    with pytest.raises(BillingError) as refused:
        await principia_pay.create_reference(
            db, school_id=ctx["school_id"], document_id=invoice["id"]
        )
    assert refused.value.code == "debt_missing_guardian"
    assert refused.value.status_code == 409


@pytest.mark.asyncio
async def test_an_unreadable_rail_response_is_a_logged_502_and_stays_recoverable(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-parse")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 10000)

    from app.services import principia_pay
    from app.services.principia_pay_client import RegisteredClient

    async def fake_register(base_url, product_token, source_system, **kwargs):
        return RegisteredClient(
            id="cli-parse", api_key="pp_key", callback_secret="cb_secret"
        )

    async def broken_create(self, **kwargs):
        # What Reference.from_json raises when the rail omits a required key.
        raise KeyError("id")

    monkeypatch.setattr(principia_pay, "register_client", fake_register)
    monkeypatch.setattr(
        principia_pay.PrincipiaPayClient, "create_reference", broken_create
    )

    with pytest.raises(BillingError) as refused:
        await principia_pay.create_reference(
            db, school_id=ctx["school_id"], document_id=invoice["id"]
        )
    assert refused.value.code == "principia_pay_unavailable"
    assert refused.value.status_code == 502

    row = (
        await db.execute(
            select(PaymentReference).where(
                PaymentReference.school_id == ctx["school_id"]
            )
        )
    ).scalars().one()
    assert row.status == "creating"
    assert row.rail_status == "create_unknown"


@pytest.mark.asyncio
async def test_live_probe_earns_the_green_tick_and_records_a_dead_rail(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "rail-probe")

    from app.services import principia_pay
    from app.services.principia_pay_client import RegisteredClient

    async def fake_register(base_url, product_token, source_system, **kwargs):
        return RegisteredClient(
            id="cli-probe", api_key="pp_key", callback_secret="cb_secret"
        )

    monkeypatch.setattr(principia_pay, "register_client", fake_register)
    await principia_pay.ensure_connection(db, school_id=ctx["school_id"])

    async def reachable(self, *, caller_reference=None):
        assert caller_reference and caller_reference.startswith("cellen-probe-")
        return []

    monkeypatch.setattr(
        principia_pay.PrincipiaPayClient, "list_references", reachable
    )
    result = await principia_pay.probe_connection(db, school_id=ctx["school_id"])
    assert result["reachable"] is True
    assert result["registered"] is True
    assert isinstance(result["latency_ms"], int)

    async def dead(self, *, caller_reference=None):
        raise httpx.ConnectError("rail down")

    monkeypatch.setattr(principia_pay.PrincipiaPayClient, "list_references", dead)
    result = await principia_pay.probe_connection(db, school_id=ctx["school_id"])
    assert result["reachable"] is False
    assert "rail down" in result["probe_error"]

    endpoint = await client.get(
        "/billing/principia-pay/check", headers=ctx["headers"]
    )
    assert endpoint.status_code == 200, endpoint.text
    assert endpoint.json()["reachable"] is False


async def _paid_rail(reference_id: str):
    from app.services.principia_pay_client import Reference

    return Reference(
        id=reference_id, provider="appypay", caller_reference=None, kind="reference",
        entity="00123", reference="111222333", redirect_url=None,
        amount=Decimal("10000.00"), currency="AOA", status="paid",
        expires_at=None, paid_at=today_luanda(), created_at=today_luanda(),
    )
