"""Enrollment fees for Finreg-active schools.

The matrícula is a fiscal document: a Finreg school must have it issued by
Finreg, never by Cellen's local fiscal engine. These tests pin that boundary
and the settlement-driven activation of the pending enrollment.
"""

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.config import settings
from app.models.finance import InternalPaymentControl, Invoice
from app.models.finreg_integration import FinregBillingInstruction
from app.services.finreg_dispatch import reconcile_enrollment_fee_settlements
from tests.conftest import auth, uid
from tests.test_academic import _create_child_with_guardian, _create_school_year


class _SettlementStub:
    def __init__(self, settlement: dict):
        self.settlement = settlement
        self.paths: list[str] = []

    async def request(self, method, path, payload, **kwargs):
        self.paths.append(path)
        return self.settlement


async def _activate_finreg(client: AsyncClient, token: str, mode: str = "fake") -> None:
    response = await client.put(
        "/finreg/connection",
        json={
            "finreg_company_id": str(uuid.uuid4()),
            "mode": mode,
            "kill_switch": False,
        },
        headers=auth(token),
    )
    assert response.status_code == 200, response.text


async def _academic_setup(client: AsyncClient, token: str) -> dict:
    headers = auth(token)
    turma = (await client.post(
        "/academic/turmas",
        json={"name": "Sala Matrícula", "level": "primário"},
        headers=headers,
    )).json()
    year = await _create_school_year(client, token)
    schedule = (await client.post(
        "/academic/schedules",
        json={"turma_id": turma["id"], "school_year_id": year["id"]},
        headers=headers,
    )).json()
    child = await _create_child_with_guardian(client, token)
    return {"turma": turma, "year": year, "schedule": schedule, "child": child}


def _enrollment_body(ctx: dict, fee: str = "25000.00", status: str = "pending") -> dict:
    return {
        "child_id": ctx["child"]["id"],
        "schedule_id": ctx["schedule"]["id"],
        "school_year_id": ctx["year"]["id"],
        "status": status,
        "enrollment_fee": fee,
        "generate_invoice": True,
    }


@pytest.mark.asyncio
async def test_finreg_enrollment_fee_is_issued_by_finreg_not_locally(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    school, token, _slug, _ = await make_school("fee-finreg")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")
    ctx = await _academic_setup(client, token)

    created = await client.post(
        "/academic/enrollments", json=_enrollment_body(ctx), headers=headers,
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["status"] == "pending"
    assert body["fee_invoice_id"] is None
    assert body["fee_instruction_id"]
    assert body["fee_instruction_status"] == "confirmed"
    assert body["payment_control_mode"] == "finreg"

    school_id = uuid.UUID(school["id"])
    local_invoices = (await db.execute(
        select(func.count(Invoice.id)).where(Invoice.school_id == school_id)
    )).scalar_one()
    assert local_invoices == 0
    controls = (await db.execute(
        select(func.count(InternalPaymentControl.id)).where(
            InternalPaymentControl.enrollment_id == uuid.UUID(body["id"])
        )
    )).scalar_one()
    assert controls == 0

    instruction = (await db.execute(
        select(FinregBillingInstruction).where(
            FinregBillingInstruction.id == uuid.UUID(body["fee_instruction_id"])
        )
    )).scalar_one()
    assert instruction.command_type == "enrollment_fee"
    assert instruction.finreg_document_id is not None
    draft = instruction.payload["draft"]["document"]
    assert draft["client_request_id"] == body["fee_instruction_id"]
    line = draft["lines"][0]
    assert line["tax_option_code"] == "IVA_ISE"
    assert line["unit_price"] == "25000.00"

    listed = await client.get("/academic/enrollments", headers=headers)
    assert listed.status_code == 200, listed.text
    row = next(item for item in listed.json() if item["id"] == body["id"])
    assert row["fee_instruction_status"] == "confirmed"


@pytest.mark.asyncio
async def test_finreg_enrollment_fee_fails_closed_without_governed_tax(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _ = await make_school("fee-tax")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")
    ctx = await _academic_setup(client, token)

    items = (await client.get("/finance/billing-items", headers=headers)).json()
    matricula = next(item for item in items if item["code"] == "MATRICULA")
    assert matricula["finreg_tax_option_code"] == "IVA_ISE"
    cleared = await client.patch(
        f"/finance/billing-items/{matricula['id']}",
        json={"finreg_tax_option_code": None},
        headers=headers,
    )
    assert cleared.status_code == 200, cleared.text

    refused = await client.post(
        "/academic/enrollments", json=_enrollment_body(ctx), headers=headers,
    )
    assert refused.status_code == 422, refused.text
    assert "tratamento fiscal" in refused.json()["detail"]

    enrollments = await client.get("/academic/enrollments", headers=headers)
    assert enrollments.json() == []


@pytest.mark.asyncio
async def test_finreg_enrollment_fee_requires_primary_guardian(
    client: AsyncClient, make_school, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _ = await make_school("fee-guardian")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")

    turma = (await client.post(
        "/academic/turmas",
        json={"name": "Sala Sem Encarregado", "level": "primário"},
        headers=headers,
    )).json()
    year = await _create_school_year(client, token)
    schedule = (await client.post(
        "/academic/schedules",
        json={"turma_id": turma["id"], "school_year_id": year["id"]},
        headers=headers,
    )).json()
    child = (await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Kid", "last_name": "Solo"},
        headers=headers,
    )).json()

    refused = await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": schedule["id"],
            "school_year_id": year["id"],
            "status": "pending",
            "enrollment_fee": "25000.00",
        },
        headers=headers,
    )
    assert refused.status_code == 422, refused.text
    assert "encarregado principal" in refused.json()["detail"]


@pytest.mark.asyncio
async def test_settled_fee_activates_pending_enrollment(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _ = await make_school("fee-settled")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")
    ctx = await _academic_setup(client, token)
    body = (await client.post(
        "/academic/enrollments", json=_enrollment_body(ctx), headers=headers,
    )).json()
    assert body["status"] == "pending"

    # Settlement is read only for pilot/live; the fake-mode instruction keeps
    # its identity and document id, so the connection can be promoted first.
    await _activate_finreg(client, token, mode="pilot")

    adapter = _SettlementStub({
        "settled": True, "outstanding_amount": 0, "paid_amount": 25000,
    })
    activated = await reconcile_enrollment_fee_settlements(db, adapter=adapter)
    assert activated >= 1
    assert f"documents/{body['fee_instruction_id']}/settlement" in adapter.paths

    refreshed = await client.get(
        f"/academic/enrollments/{body['id']}", headers=headers,
    )
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["status"] == "active"


@pytest.mark.asyncio
async def test_partial_fee_settlement_keeps_enrollment_pending(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _ = await make_school("fee-partial")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")
    ctx = await _academic_setup(client, token)
    body = (await client.post(
        "/academic/enrollments", json=_enrollment_body(ctx), headers=headers,
    )).json()
    await _activate_finreg(client, token, mode="pilot")

    adapter = _SettlementStub({
        "settled": False, "outstanding_amount": 5000, "paid_amount": 20000,
    })
    await reconcile_enrollment_fee_settlements(db, adapter=adapter)
    assert f"documents/{body['fee_instruction_id']}/settlement" in adapter.paths

    refreshed = await client.get(
        f"/academic/enrollments/{body['id']}", headers=headers,
    )
    assert refreshed.json()["status"] == "pending"


@pytest.mark.asyncio
async def test_fake_mode_is_not_polled_for_settlement(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _ = await make_school("fee-fake")
    headers = auth(token)
    await _activate_finreg(client, token, mode="fake")
    ctx = await _academic_setup(client, token)
    body = (await client.post(
        "/academic/enrollments", json=_enrollment_body(ctx), headers=headers,
    )).json()

    adapter = _SettlementStub({"settled": True})
    await reconcile_enrollment_fee_settlements(db, adapter=adapter)
    # Other schools' pending fees may be polled, never this school's.
    assert f"documents/{body['fee_instruction_id']}/settlement" not in adapter.paths
    refreshed = await client.get(
        f"/academic/enrollments/{body['id']}", headers=headers,
    )
    assert refreshed.json()["status"] == "pending"


@pytest.mark.asyncio
async def test_platform_seed_carries_governed_tax_option(
    client: AsyncClient, make_school,
):
    _school, token, _slug, _ = await make_school("fee-seed")
    items = (await client.get("/finance/billing-items", headers=auth(token))).json()
    by_code = {item["code"]: item for item in items}
    assert by_code["MATRICULA"]["finreg_tax_option_code"] == "IVA_ISE"
    assert by_code["EXTRAS"]["finreg_tax_option_code"] == "IVA_ISE"
