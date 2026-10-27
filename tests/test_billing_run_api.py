# -*- coding: utf-8 -*-
"""Fee automation API: preview, generation, idempotency and mode parity.

The director's acceptance cases live here:

* the preview shows exact amounts without calling FinReg at all;
* "Gerar dívidas" issues fiscal documents through FinReg, never locally, for
  a FinReg-active school;
* pressing it twice in the same month yields one run and no duplicate charge;
* a shadow school gets draft plans queued through the outbox;
* an internal school gets the same amounts as local fiscal invoices;
* the modality inscription is charged once and only through FinReg.
"""
import calendar
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.config import settings
from app.models.billing import BillingRun, StudentFinanceProfile
from app.models.finance import InternalPaymentControl, Invoice
from app.models.finreg_integration import FinregBillingInstruction
from app.models.person import ChildGuardian
from app.services.billing_composer import advance_month
from app.services.billing_run import RUN_NOTE_PREFIX
from app.services.finreg import FakeFinregAdapter
from app.utils.agt import today_luanda
from tests.conftest import auth, uid


# ─── helpers ────────────────────────────────────────────────────────────────

def _first_of_month() -> date:
    return today_luanda().replace(day=1)


def _last_of_month(day: date) -> date:
    return date(day.year, day.month, calendar.monthrange(day.year, day.month)[1])


def _next_month(day: date) -> date:
    return advance_month(day.replace(day=1))


async def _scaffold(client: AsyncClient, make_school, prefix: str) -> dict:
    school, token, slug, _ = await make_school(prefix)
    headers = auth(token)
    first = _first_of_month()
    year_response = await client.post(
        "/schools/school-years",
        json={
            "year_label": f"SY-{uid()}",
            "start_date": first.isoformat(),
            "end_date": date(first.year + 1, 12, 31).isoformat(),
            "is_active": True,
        },
        headers=headers,
    )
    assert year_response.status_code == 201, year_response.text
    year = year_response.json()
    turma = (
        await client.post(
            "/academic/turmas",
            json={"name": f"Sala {uid()}", "level": "berçário"},
            headers=headers,
        )
    ).json()
    schedule = (
        await client.post(
            "/academic/schedules",
            json={"turma_id": turma["id"], "school_year_id": year["id"]},
            headers=headers,
        )
    ).json()
    return {
        "school": school,
        "school_id": uuid.UUID(school["id"]),
        "token": token,
        "headers": headers,
        "year": year,
        "schedule": schedule,
        "month": first.strftime("%Y-%m"),
        "first": first,
        "next_month": _next_month(first).strftime("%Y-%m"),
    }


async def _item(
    client: AsyncClient,
    ctx: dict,
    name: str,
    price,
    *,
    rate=0.0,
    tax_option="IVA_ISE",
    reason="M10",
) -> dict:
    response = await client.post(
        "/finance/billing-items",
        json={
            "code": f"{uid()}-{name[:3].upper()}",
            "name": name,
            "unit_price": price,
            "iva_rate": rate,
            "finreg_tax_option_code": tax_option,
            "iva_exemption_reason": reason,
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _policy(client: AsyncClient, ctx: dict, **overrides) -> dict:
    body = {
        "school_year_id": ctx["year"]["id"],
        "default_tuition_billing_item_id": ctx.get("tuition_item", {}).get("id"),
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
    response = await client.put(
        "/billing/fee-policy", json=body, headers=ctx["headers"]
    )
    assert response.status_code == 200, response.text
    return response.json()


async def _child(client: AsyncClient, ctx: dict, first_name: str) -> dict:
    response = await client.post(
        "/children",
        json={
            "cedula": f"C{uid()}",
            "first_name": first_name,
            "last_name": "Test",
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _guardian(client: AsyncClient, ctx: dict, first_name="Maria") -> dict:
    response = await client.post(
        "/guardians",
        json={
            "first_name": first_name,
            "last_name": f"Guard{uid()[:4]}",
            "nif": f"00{uid()[:8]}",
            "username": f"grd-{uid()}",
            "password": "Guardian1!",
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _link(
    client: AsyncClient,
    ctx: dict,
    guardian_id: str,
    child_id: str,
    *,
    primary: bool,
):
    return await client.post(
        f"/guardians/{guardian_id}/children",
        json={
            "child_id": child_id,
            "relationship_type": "mother",
            "is_primary_contact": primary,
        },
        headers=ctx["headers"],
    )


async def _enroll(
    client: AsyncClient,
    ctx: dict,
    child_id: str,
    *,
    fee=0,
    enrollment_date: date | None = None,
):
    return await client.post(
        "/academic/enrollments",
        json={
            "child_id": child_id,
            "schedule_id": ctx["schedule"]["id"],
            "school_year_id": ctx["year"]["id"],
            "status": "active",
            "enrollment_date": (enrollment_date or ctx["first"]).isoformat(),
            "enrollment_fee": fee,
        },
        headers=ctx["headers"],
    )


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


async def _family(
    client: AsyncClient,
    ctx: dict,
    *,
    siblings: bool = True,
) -> dict:
    """Two children of one guardian with tuition, transport and an activity."""
    guardian = await _guardian(client, ctx)
    ana = await _child(client, ctx, "Ana")
    links = {"ana": await _link(client, ctx, guardian["id"], ana["id"], primary=True)}
    assert links["ana"].status_code == 201, links["ana"].text
    children = {"ana": ana}
    if siblings:
        bruno = await _child(client, ctx, "Bruno")
        links["bruno"] = await _link(
            client, ctx, guardian["id"], bruno["id"], primary=False
        )
        assert links["bruno"].status_code == 201, links["bruno"].text
        children["bruno"] = bruno
    for child in children.values():
        enrolled = await _enroll(client, ctx, child["id"])
        assert enrolled.status_code == 201, enrolled.text
    return {"guardian": guardian, "children": children, "links": links}


async def _count(db, model, *conditions) -> int:
    query = select(func.count()).select_from(model)
    for condition in conditions:
        query = query.where(condition)
    return (await db.execute(query)).scalar_one()


def _students(preview: dict) -> dict:
    return {student["child_id"]: student for student in preview["students"]}


# ─── policy ─────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_fee_policy_starts_from_defaults_and_is_school_editable(
    client: AsyncClient, make_school,
):
    ctx = await _scaffold(client, make_school, "fee-policy")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)

    initial = await client.get("/billing/fee-policy", headers=ctx["headers"])
    assert initial.status_code == 200, initial.text
    policy = initial.json()["policy"]
    assert policy["is_default"] is True
    assert policy["sibling_discount_pct"] == 5.0
    assert policy["sibling_discount_min_children"] == 2
    assert policy["proration_policy"] == "pro_rata_days"

    updated = await _policy(
        client,
        ctx,
        sibling_discount_pct=7.5,
        sibling_discount_min_children=3,
        sibling_discount_scope="all_children",
        due_days=7,
        billing_day=10,
        auto_generate=True,
        proration_policy="full_month",
        default_enrollment_fee=30000,
    )
    saved = updated["policy"]
    assert saved["is_default"] is False
    assert saved["sibling_discount_pct"] == 7.5
    assert saved["sibling_discount_min_children"] == 3
    assert saved["sibling_discount_scope"] == "all_children"
    assert saved["due_days"] == 7
    assert saved["billing_day"] == 10
    assert saved["auto_generate"] is True
    assert saved["proration_policy"] == "full_month"
    assert saved["default_enrollment_fee"] == 30000.0

    reread = await client.get("/billing/fee-policy", headers=ctx["headers"])
    assert reread.json()["policy"]["sibling_discount_pct"] == 7.5

    refused = await client.put(
        "/billing/fee-policy",
        json={
            "school_year_id": ctx["year"]["id"],
            "default_tuition_billing_item_id": str(uuid.uuid4()),
        },
        headers=ctx["headers"],
    )
    assert refused.status_code == 422, refused.text


# ─── preview ────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_preview_shows_the_director_numbers_without_calling_finreg(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-preview")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    transport_item = await _item(client, ctx, "Transporte", 20000)
    ballet_item = await _item(client, ctx, "Balé", 15000)
    await _policy(client, ctx)
    family = await _family(client, ctx)
    ana, bruno = family["children"]["ana"], family["children"]["bruno"]

    route = (
        await client.post(
            "/billing/transport/routes",
            json={
                "name": f"Rota {uid()}",
                "monthly_price": 20000,
                "billing_item_id": transport_item["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    assigned = await client.post(
        f"/billing/transport/routes/{route['id']}/assign",
        json={"child_id": ana["id"], "start_date": ctx["first"].isoformat()},
        headers=ctx["headers"],
    )
    assert assigned.status_code == 201, assigned.text

    modality = (
        await client.post(
            "/billing/modalities",
            json={
                "name": f"Balé {uid()}",
                "inscription_fee": 0,
                "monthly_fee": 15000,
                "billing_item_id": ballet_item["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    enrolled = await client.post(
        f"/billing/modalities/{modality['id']}/enroll",
        json={"child_id": ana["id"], "start_date": ctx["first"].isoformat()},
        headers=ctx["headers"],
    )
    assert enrolled.status_code == 201, enrolled.text
    assert enrolled.json()["inscription"]["status"] == "not_charged"

    await _activate_finreg(client, ctx, "fake")

    async def _forbidden(*_args, **_kwargs):
        raise AssertionError("the preview must never call FinReg")

    monkeypatch.setattr(FakeFinregAdapter, "execute", _forbidden)

    response = await client.post(
        "/billing/runs/preview",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 200, response.text
    preview = response.json()
    assert preview["mode"] == "fake"
    assert preview["blockers"] == []
    assert preview["existing_run"] is None
    assert preview["run_date"] == ctx["first"].isoformat()
    assert preview["due_date"] == (ctx["first"] + timedelta(days=5)).isoformat()

    students = _students(preview)
    ana_preview, bruno_preview = students[ana["id"]], students[bruno["id"]]
    assert [line["service"] for line in ana_preview["lines"]] == [
        "tuition", "transport", "modality",
    ]
    assert [line["line_total"] for line in ana_preview["lines"][1:]] == [
        20000.0, 15000.0,
    ]
    assert ana_preview["subtotal"] == 135000.0
    assert bruno_preview["subtotal"] == 100000.0

    discounted = next(
        student for student in preview["students"]
        if student["sibling_discount_applied"]
    )
    full_price = next(
        student for student in preview["students"]
        if not student["sibling_discount_applied"]
    )
    assert discounted["sibling_index"] == 2
    assert discounted["family_size"] == 2
    assert discounted["lines"][0]["discount_pct"] == 5.0
    assert discounted["lines"][0]["discount_amount"] == 5000.0
    assert full_price["discount_total"] == 0.0
    # Whichever sibling is second pays 5% less on tuition; the other services
    # stay at catalogue price.
    assert ana_preview["total"] == (
        130000.0 if ana_preview["sibling_discount_applied"] else 135000.0
    )
    assert bruno_preview["total"] == (
        95000.0 if bruno_preview["sibling_discount_applied"] else 100000.0
    )

    assert preview["totals"]["students"] == 2
    assert preview["totals"]["lines"] == 4
    assert preview["totals"]["subtotal"] == 235000.0
    assert preview["totals"]["discount_total"] == 5000.0
    assert preview["totals"]["total"] == 230000.0
    assert preview["totals"]["families_with_discount"] == 1

    school_id = ctx["school_id"]
    assert await _count(db, FinregBillingInstruction,
                        FinregBillingInstruction.school_id == school_id) == 0
    assert await _count(db, Invoice, Invoice.school_id == school_id) == 0


# ─── generation ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_generate_in_fake_mode_confirms_one_instruction_per_student(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-run")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx)
    await _activate_finreg(client, ctx, "fake")

    generated = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert generated.status_code == 201, generated.text
    body = generated.json()
    assert body["created"] is True
    run = body["run"]
    assert run["mode"] == "fake"
    assert run["status"] == "completed"
    assert run["stats"]["generated"] == 2
    assert run["stats"]["queued"] == 0
    assert run["stats"]["failed"] == 0
    assert run["documents"] == []
    assert len(run["instructions"]) == 2
    assert all(item["status"] == "confirmed" for item in run["instructions"])
    assert all(item["finreg_document_id"] for item in run["instructions"])

    school_id = ctx["school_id"]
    assert await _count(db, Invoice, Invoice.school_id == school_id) == 0
    assert await _count(db, BillingRun, BillingRun.school_id == school_id) == 1

    instructions = list(
        (
            await db.execute(
                select(FinregBillingInstruction).where(
                    FinregBillingInstruction.school_id == school_id,
                    FinregBillingInstruction.command_type == "billing_run",
                )
            )
        ).scalars().all()
    )
    assert len(instructions) == 2
    by_child: dict[str, FinregBillingInstruction] = {}
    for instruction in instructions:
        payload = instruction.payload
        assert payload["billing_run_id"] == run["id"]
        assert payload["plan"]["template"]["generation_mode"] == "draft"
        assert payload["pause_after_run"] is True
        assert payload["billing_month"] == ctx["month"]
        by_child[payload["plan"]["context"]["pupil_id"]] = instruction

    discounted_child = next(
        student["child_id"] for student in _students(
            (await client.post(
                "/billing/runs/preview",
                json={
                    "billing_month": ctx["month"],
                    "school_year_id": ctx["year"]["id"],
                },
                headers=ctx["headers"],
            )).json()
        ).values()
        if student["sibling_discount_applied"]
    )
    discounted_line = by_child[discounted_child].payload["plan"]["template"]["lines"][0]
    assert discounted_line["discount_pct"] == "5.00"
    other_child = next(
        child_id for child_id in by_child if child_id != discounted_child
    )
    assert (
        by_child[other_child].payload["plan"]["template"]["lines"][0]["discount_pct"]
        == "0"
    )

    profile = (
        await client.get(
            f"/billing/students/{discounted_child}/profile",
            headers=ctx["headers"],
        )
    ).json()["profile"]
    assert profile["plan_stale"] is False
    assert profile["plan_revision"]
    assert profile["plan_next_run_date"] == advance_month(ctx["first"]).isoformat()

    # The same button, again, in the same month: same run, same documents.
    repeated = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert repeated.status_code == 201, repeated.text
    assert repeated.json()["created"] is False
    assert repeated.json()["run"]["id"] == run["id"]
    assert len(repeated.json()["run"]["instructions"]) == 2
    assert await _count(db, BillingRun, BillingRun.school_id == school_id) == 1
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == school_id,
    ) == 2


@pytest.mark.asyncio
async def test_shadow_mode_queues_draft_plans_instead_of_issuing(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-shadow")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "shadow")

    response = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    run = response.json()["run"]
    assert run["mode"] == "shadow"
    assert run["status"] == "running"
    assert run["stats"]["queued"] == 1
    assert run["stats"]["generated"] == 0
    assert run["instructions"][0]["status"] == "pending"

    rows = list(
        (
            await db.execute(
                select(FinregBillingInstruction).where(
                    FinregBillingInstruction.school_id == ctx["school_id"],
                )
            )
        ).scalars().all()
    )
    assert len(rows) == 1
    assert rows[0].command_type == "billing_run"
    assert rows[0].payload["plan"]["template"]["generation_mode"] == "draft"
    assert await _count(db, Invoice, Invoice.school_id == ctx["school_id"]) == 0

    repeated = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert repeated.json()["created"] is False
    assert repeated.json()["run"]["id"] == run["id"]
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == ctx["school_id"],
    ) == 1


@pytest.mark.asyncio
async def test_internal_mode_issues_the_same_amounts_as_local_invoices(
    client: AsyncClient, make_school, db,
):
    monkeypatch_settings = settings.FINREG_INTEGRATION_ENABLED
    assert monkeypatch_settings is False
    ctx = await _scaffold(client, make_school, "fee-internal")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    await _family(client, ctx)

    preview = (
        await client.post(
            "/billing/runs/preview",
            json={
                "billing_month": ctx["month"],
                "school_year_id": ctx["year"]["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    assert preview["mode"] == "internal"
    assert preview["blockers"] == []

    response = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    body = response.json()
    run = body["run"]
    assert body["created"] is True
    assert run["mode"] == "internal"
    assert run["status"] == "completed", run["stats"]
    assert run["stats"]["generated"] == 2
    assert run["instructions"] == []
    assert len(run["documents"]) == 2
    assert {document["gross_total"] for document in run["documents"]} == {
        100000.0, 95000.0,
    }

    school_id = ctx["school_id"]
    invoices = list(
        (
            await db.execute(
                select(Invoice).where(
                    Invoice.school_id == school_id,
                    Invoice.notes == f"{RUN_NOTE_PREFIX}{run['id']}",
                )
            )
        ).scalars().all()
    )
    assert len(invoices) == 2
    assert {float(invoice.gross_total) for invoice in invoices} == {
        100000.0, 95000.0,
    }
    # The fiscal signer is an employee, never the login account that pressed
    # the button (the two live in different tables).
    assert all(invoice.issued_by is None for invoice in invoices)
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == school_id,
    ) == 0

    repeated = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert repeated.json()["created"] is False
    assert repeated.json()["run"]["id"] == run["id"]
    assert await _count(db, Invoice, Invoice.school_id == school_id) == 2


@pytest.mark.asyncio
async def test_generation_fails_closed_on_missing_fiscal_treatment(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-tax")
    ctx["tuition_item"] = await _item(
        client, ctx, "Mensalidade", 100000, tax_option=None,
    )
    await _policy(client, ctx)
    await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")

    preview = (
        await client.post(
            "/billing/runs/preview",
            json={
                "billing_month": ctx["month"],
                "school_year_id": ctx["year"]["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    blocker_codes = {blocker["code"] for blocker in preview["blockers"]}
    assert "finreg_tax_option_missing" in blocker_codes

    response = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    run = response.json()["run"]
    assert response.status_code == 201, response.text
    assert run["status"] == "failed"
    assert run["stats"]["failed"] == 1
    assert run["stats"]["preflight_failed"] == 1
    assert run["stats"]["failures"][0]["code"] == "tax_option_missing"
    assert run["instructions"] == []
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == ctx["school_id"],
    ) == 0

    # Fixing the catalogue and pressing the same button again recovers the
    # failed run instead of needing a new month.
    fixed = await client.patch(
        f"/finance/billing-items/{ctx['tuition_item']['id']}",
        json={"finreg_tax_option_code": "IVA_ISE"},
        headers=ctx["headers"],
    )
    assert fixed.status_code == 200, fixed.text

    recovered = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    recovered_run = recovered.json()["run"]
    assert recovered.json()["created"] is False
    assert recovered_run["id"] == run["id"]
    assert recovered_run["status"] == "completed"
    assert recovered_run["stats"]["generated"] == 1
    assert len(recovered_run["instructions"]) == 1


# ─── modalities ─────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_modality_inscription_is_charged_once_through_finreg(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-modality")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    ballet_item = await _item(client, ctx, "Balé", 15000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    ana = family["children"]["ana"]
    await _activate_finreg(client, ctx, "fake")

    modality = (
        await client.post(
            "/billing/modalities",
            json={
                "name": f"Balé {uid()}",
                "inscription_fee": 5000,
                "monthly_fee": 15000,
                "billing_item_id": ballet_item["id"],
            },
            headers=ctx["headers"],
        )
    ).json()

    enrolled = await client.post(
        f"/billing/modalities/{modality['id']}/enroll",
        json={"child_id": ana["id"], "start_date": ctx["first"].isoformat()},
        headers=ctx["headers"],
    )
    assert enrolled.status_code == 201, enrolled.text
    enrollment = enrolled.json()["enrollment"]
    inscription = enrolled.json()["inscription"]
    assert inscription["mode"] == "finreg"
    assert inscription["status"] == "confirmed"
    assert inscription["invoice_id"] is None
    assert inscription["error"] is None

    school_id = ctx["school_id"]
    assert await _count(db, Invoice, Invoice.school_id == school_id) == 0
    instructions = list(
        (
            await db.execute(
                select(FinregBillingInstruction).where(
                    FinregBillingInstruction.school_id == school_id,
                    FinregBillingInstruction.command_type
                    == "modality_inscription_fee",
                )
            )
        ).scalars().all()
    )
    assert len(instructions) == 1
    instruction = instructions[0]
    assert instruction.finreg_document_id is not None
    assert instruction.idempotency_key == f"cellen-modality-fee-{enrollment['id']}"
    line = instruction.payload["draft"]["document"]["lines"][0]
    assert line["unit_price"] == "5000.00"
    assert line["tax_option_code"] == "IVA_ISE"

    duplicated = await client.post(
        f"/billing/modalities/{modality['id']}/enroll",
        json={"child_id": ana["id"], "start_date": ctx["first"].isoformat()},
        headers=ctx["headers"],
    )
    assert duplicated.status_code == 409, duplicated.text
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.command_type == "modality_inscription_fee",
    ) == 1

    preview = (
        await client.post(
            "/billing/runs/preview",
            json={
                "billing_month": ctx["month"],
                "school_year_id": ctx["year"]["id"],
                "child_id": ana["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    student = _students(preview)[ana["id"]]
    assert [line["service"] for line in student["lines"]] == [
        "tuition", "modality",
    ]
    assert student["lines"][1]["line_total"] == 15000.0

    summary = await client.get(
        f"/billing/students/{ana['id']}/summary",
        headers=ctx["headers"],
    )
    assert summary.status_code == 200, summary.text
    assert len(summary.json()["modalities"]) == 1
    assert summary.json()["preview"]["students"][0]["total"] == 115000.0

    ended = await client.post(
        f"/billing/modality-enrollments/{enrollment['id']}/end",
        json={
            "end_date": _last_of_month(ctx["first"]).isoformat(),
            "status": "ended",
        },
        headers=ctx["headers"],
    )
    assert ended.status_code == 200, ended.text
    assert ended.json()["status"] == "ended"

    following = (
        await client.post(
            "/billing/runs/preview",
            json={
                "billing_month": ctx["next_month"],
                "school_year_id": ctx["year"]["id"],
                "child_id": ana["id"],
            },
            headers=ctx["headers"],
        )
    ).json()
    following_student = _students(following)[ana["id"]]
    assert [line["service"] for line in following_student["lines"]] == ["tuition"]


# ─── guardians and profiles ─────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_guardian_links_keep_the_billing_profile_in_step(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "fee-guardians")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    child = await _child(client, ctx, "Ana")
    first_guardian = await _guardian(client, ctx, "Maria")
    second_guardian = await _guardian(client, ctx, "Paulo")
    third_guardian = await _guardian(client, ctx, "Carla")

    # The first link becomes the billing contact automatically.
    linked = await _link(
        client, ctx, first_guardian["id"], child["id"], primary=False
    )
    assert linked.status_code == 201, linked.text
    first_link = (
        await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.child_id == uuid.UUID(child["id"]),
                ChildGuardian.guardian_id == uuid.UUID(first_guardian["id"]),
            )
        )
    ).scalar_one()
    assert first_link.is_primary_contact is True

    enrolled = await _enroll(client, ctx, child["id"])
    assert enrolled.status_code == 201, enrolled.text

    second_link = await _link(
        client, ctx, second_guardian["id"], child["id"], primary=False
    )
    assert second_link.status_code == 201, second_link.text

    profile_response = await client.get(
        f"/billing/students/{child['id']}/profile",
        headers=ctx["headers"],
    )
    assert profile_response.status_code == 200, profile_response.text
    profile = profile_response.json()["profile"]
    assert profile["is_virtual"] is False
    assert profile["billing_guardian_id"] == first_guardian["id"]
    assert profile["status"] == "active"

    refused = await _link(
        client, ctx, third_guardian["id"], child["id"], primary=True
    )
    assert refused.status_code == 422, refused.text

    unlinked = await client.delete(
        f"/guardians/{first_guardian['id']}/children/{child['id']}",
        headers=ctx["headers"],
    )
    assert unlinked.status_code == 200, unlinked.text

    after = (
        await client.get(
            f"/billing/students/{child['id']}/profile",
            headers=ctx["headers"],
        )
    ).json()["profile"]
    assert after["billing_guardian_id"] == second_guardian["id"]
    assert after["plan_stale"] is True

    profile_row = (
        await db.execute(
            select(StudentFinanceProfile).where(
                StudentFinanceProfile.school_id == ctx["school_id"],
                StudentFinanceProfile.child_id == uuid.UUID(child["id"]),
            )
        )
    ).scalar_one()
    assert str(profile_row.billing_guardian_id) == second_guardian["id"]
    assert profile_row.plan_stale is True


# ─── default matrícula ──────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_policy_default_enrollment_fee_applies_when_the_form_is_silent(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "fee-matricula")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx, default_enrollment_fee=25000)
    child = await _child(client, ctx, "Ana")
    guardian = await _guardian(client, ctx)
    linked = await _link(
        client, ctx, guardian["id"], child["id"], primary=True
    )
    assert linked.status_code == 201, linked.text

    silent = await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": ctx["schedule"]["id"],
            "school_year_id": ctx["year"]["id"],
            "status": "active",
            "enrollment_date": ctx["first"].isoformat(),
        },
        headers=ctx["headers"],
    )
    assert silent.status_code == 201, silent.text
    enrollment = silent.json()
    assert float(enrollment["enrollment_fee"]) == 25000.0
    assert enrollment["status"] == "pending"
    assert enrollment["payment_control_mode"] == "internal"

    controls = list(
        (
            await db.execute(
                select(InternalPaymentControl).where(
                    InternalPaymentControl.enrollment_id
                    == uuid.UUID(enrollment["id"])
                )
            )
        ).scalars().all()
    )
    assert len(controls) == 1
    assert float(controls[0].amount) == 25000.0
    assert controls[0].category == "enrollment"

    # An explicit zero still means "this enrollment has no matrícula".
    other_child = await _child(client, ctx, "Bruno")
    other_link = await _link(
        client, ctx, guardian["id"], other_child["id"], primary=True
    )
    assert other_link.status_code == 201, other_link.text
    explicit_zero = await _enroll(client, ctx, other_child["id"], fee=0)
    assert explicit_zero.status_code == 201, explicit_zero.text
    assert float(explicit_zero.json()["enrollment_fee"]) == 0.0
    assert explicit_zero.json()["status"] == "active"
    assert await _count(
        db,
        InternalPaymentControl,
        InternalPaymentControl.enrollment_id
        == uuid.UUID(explicit_zero.json()["id"]),
    ) == 0


# ─── plan rebuild ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_rebuild_plans_is_idempotent_and_picks_up_policy_changes(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "fee-rebuild")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    await _family(client, ctx)
    await _activate_finreg(client, ctx, "fake")
    school_id = ctx["school_id"]

    first = await client.post(
        "/billing/rebuild-plans",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert first.status_code == 200, first.text
    assert first.json()["confirmed"] == 2
    assert first.json()["unchanged"] == 0
    assert first.json()["failed"] == 0
    upserts = await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.command_type == "billing_plan_upsert",
    )
    assert upserts == 2

    # The same composition against the same revision is a no-op; a double
    # click after a policy edit must not churn FinReg plans either.
    second = await client.post(
        "/billing/rebuild-plans",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert second.json()["confirmed"] == 0
    assert second.json()["unchanged"] == 2
    assert await _count(
        db,
        FinregBillingInstruction,
        FinregBillingInstruction.school_id == school_id,
        FinregBillingInstruction.command_type == "billing_plan_upsert",
    ) == 2

    changed = await client.put(
        "/billing/fee-policy",
        json={
            "school_year_id": ctx["year"]["id"],
            "default_tuition_billing_item_id": ctx["tuition_item"]["id"],
            "sibling_discount_pct": 10,
            "sibling_discount_min_children": 2,
            "sibling_discount_scope": "additional_children",
            "due_days": 5,
            "billing_day": 1,
            "auto_generate": False,
            "proration_policy": "pro_rata_days",
        },
        headers=ctx["headers"],
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["policy"]["sibling_discount_pct"] == 10.0

    third = await client.post(
        "/billing/rebuild-plans",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert third.status_code == 200, third.text
    assert third.json()["confirmed"] == 2
    assert third.json()["unchanged"] == 0
    rows = list(
        (
            await db.execute(
                select(FinregBillingInstruction)
                .where(
                    FinregBillingInstruction.school_id == school_id,
                    FinregBillingInstruction.command_type == "billing_plan_upsert",
                )
                .order_by(FinregBillingInstruction.created_at)
            )
        ).scalars().all()
    )
    # Only the discounted child's plan changed; the other plan keeps its
    # revision and reuses its confirmed instruction instead of churning.
    assert len(rows) == 3
    newest_pcts = {
        line["discount_pct"]
        for line in rows[-1].payload["plan"]["template"]["lines"]
    }
    assert "10.00" in newest_pcts
    first_revisions = {
        row.payload["plan_external_id"]: row.payload["plan_revision"]
        for row in rows[:2]
    }
    assert rows[2].payload["plan_external_id"] in first_revisions
    assert (
        first_revisions[rows[2].payload["plan_external_id"]]
        != rows[2].payload["plan_revision"]
    )
