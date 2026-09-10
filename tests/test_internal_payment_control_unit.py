"""Focused checks for the non-fiscal payment boundary."""

import asyncio
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from httpx import AsyncClient

from app.core.config import settings
from app.models.finance import InternalPaymentControl
from app.services.payment_control import finreg_is_active
from tests.conftest import auth, login, uid
from tests.test_academic import _create_child_with_guardian, _create_school_year


class _Result:
    def __init__(self, value):
        self.value = value

    def scalar_one_or_none(self):
        return self.value


class _Session:
    def __init__(self, value):
        self.value = value

    async def execute(self, _statement):
        return _Result(self.value)


def test_internal_payment_model_has_no_fiscal_document_fields():
    columns = set(InternalPaymentControl.__table__.columns.keys())
    assert {"amount", "status", "proof_url", "payment_method", "reviewed_at"} <= columns
    assert not ({"series_number", "full_document_number", "hash_code", "transmission_status"} & columns)


def test_finreg_mode_requires_global_and_school_activation():
    school_id = uuid.uuid4()
    active = SimpleNamespace(mode="live", kill_switch=False)
    killed = SimpleNamespace(mode="live", kill_switch=True)
    with patch("app.services.payment_control.settings.FINREG_INTEGRATION_ENABLED", True):
        assert asyncio.run(finreg_is_active(_Session(active), school_id)) is True
        assert asyncio.run(finreg_is_active(_Session(killed), school_id)) is False
        assert asyncio.run(finreg_is_active(_Session(None), school_id)) is False
    with patch("app.services.payment_control.settings.FINREG_INTEGRATION_ENABLED", False):
        assert asyncio.run(finreg_is_active(_Session(active), school_id)) is False


def test_ui_switches_exclusively_between_finreg_and_internal_control():
    root = Path.cwd()
    host = (root / "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart").read_text()
    internal = (root / "mobile/lib/features/admin/finance/internal_payments_screen.dart").read_text()
    academic = (root / "app/routers/academic.py").read_text()
    assert "return const InternalPaymentsScreen();" in host
    assert "Registo interno sem valor fiscal" in internal
    assert "InternalPaymentControl(" in academic
    assert "generate_invoice = finreg_active" in academic


def test_migration_recovers_pending_non_invoiced_enrollments():
    migration = Path("alembic/versions/0030_internal_payment_controls.py").read_text()
    assert "enrollment_fee > 0 AND fee_invoice_id IS NULL" in migration
    assert "ON CONFLICT (enrollment_id) DO NOTHING" in migration


@pytest.mark.asyncio
async def test_manual_internal_payment_proof_and_review(
    client: AsyncClient, make_school, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", False)
    _school, token, _slug, _username = await make_school("internal-pay")
    headers = auth(token)

    created = await client.post(
        "/finance/internal-payments",
        json={"description": "Passeio escolar", "amount": "12500.00"},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    payment_id = created.json()["id"]
    assert created.json()["is_fiscal_document"] is False

    uploaded = await client.post(
        "/finance/internal-payments/proof",
        files={"file": ("comprovativo.png", b"proof", "image/png")},
        headers=headers,
    )
    assert uploaded.status_code == 200, uploaded.text
    submitted = await client.patch(
        f"/finance/internal-payments/{payment_id}/submit",
        json={
            "proof_url": uploaded.json()["url"],
            "payment_method": "transfer",
            "payment_date": "2026-09-10",
        },
        headers=headers,
    )
    assert submitted.status_code == 200, submitted.text
    assert submitted.json()["status"] == "proof_submitted"

    reviewed = await client.patch(
        f"/finance/internal-payments/{payment_id}/review",
        json={"action": "confirm"},
        headers=headers,
    )
    assert reviewed.status_code == 200, reviewed.text
    assert reviewed.json()["status"] == "paid"


@pytest.mark.asyncio
async def test_internal_control_is_blocked_when_finreg_is_active(
    client: AsyncClient, make_school, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _school, token, _slug, _username = await make_school("finreg-exclusive")
    headers = auth(token)
    configured = await client.put(
        "/finreg/connection",
        json={"finreg_company_id": str(uuid.uuid4()), "mode": "fake", "kill_switch": False},
        headers=headers,
    )
    assert configured.status_code == 200, configured.text
    mode = await client.get("/finance/internal-payments/mode", headers=headers)
    assert mode.json() == {"mode": "finreg", "finreg_active": True}
    blocked = await client.post(
        "/finance/internal-payments",
        json={"description": "Não permitido", "amount": "100.00"},
        headers=headers,
    )
    assert blocked.status_code == 409


@pytest.mark.asyncio
async def test_enrollment_fee_uses_internal_control_and_activates_after_review(
    client: AsyncClient, make_school, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", False)
    _school, token, _slug, _username = await make_school("enrollment-pay")
    headers = auth(token)
    turma = (await client.post(
        "/academic/turmas",
        json={"name": "Sala Pagamentos", "level": "primário"},
        headers=headers,
    )).json()
    year = await _create_school_year(client, token)
    schedule = (await client.post(
        "/academic/schedules",
        json={"turma_id": turma["id"], "school_year_id": year["id"]},
        headers=headers,
    )).json()
    child = await _create_child_with_guardian(client, token)

    enrolled = await client.post(
        "/academic/enrollments",
        json={
            "child_id": child["id"],
            "schedule_id": schedule["id"],
            "school_year_id": year["id"],
            "status": "pending",
            "enrollment_fee": "25000.00",
            "generate_invoice": True,
        },
        headers=headers,
    )
    assert enrolled.status_code == 201, enrolled.text
    assert enrolled.json()["fee_invoice_id"] is None

    controls = await client.get("/finance/internal-payments", headers=headers)
    assert controls.status_code == 200, controls.text
    control = next(row for row in controls.json() if row["enrollment_id"] == enrolled.json()["id"])
    assert control["status"] == "pending"

    uploaded = await client.post(
        "/finance/internal-payments/proof",
        files={"file": ("matricula.pdf", b"proof", "application/pdf")},
        headers=headers,
    )
    submitted = await client.patch(
        f"/finance/internal-payments/{control['id']}/submit",
        json={
            "proof_url": uploaded.json()["url"],
            "payment_method": "multicaixa",
            "payment_date": "2026-09-10",
        },
        headers=headers,
    )
    assert submitted.status_code == 200, submitted.text
    confirmed = await client.patch(
        f"/finance/internal-payments/{control['id']}/review",
        json={"action": "confirm", "note": "Validado pela tesouraria"},
        headers=headers,
    )
    assert confirmed.status_code == 200, confirmed.text

    enrollments = await client.get("/academic/enrollments", headers=headers)
    current = next(row for row in enrollments.json() if row["id"] == enrolled.json()["id"])
    assert current["status"] == "active"
    assert current["internal_payment_status"] == "paid"


@pytest.mark.asyncio
async def test_parent_receives_charge_and_school_confirms_parent_proof(
    client: AsyncClient, make_school, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", False)
    _school, admin_token, slug, _username = await make_school("parent-internal")
    headers = auth(admin_token)
    child = (await client.post(
        "/children",
        json={"cedula": f"PAY{uid()}", "first_name": "Cliente", "last_name": "Teste"},
        headers=headers,
    )).json()
    parent_username = f"payer-{uid()}"
    guardian = (await client.post(
        "/guardians",
        json={
            "first_name": "Encarregado",
            "last_name": "Teste",
            "username": parent_username,
            "password": "Parent123!",
        },
        headers=headers,
    )).json()
    linked = await client.post(
        f"/guardians/{guardian['id']}/children",
        json={
            "child_id": child["id"],
            "relationship_type": "legal_guardian",
            "is_primary_contact": True,
        },
        headers=headers,
    )
    assert linked.status_code == 201, linked.text
    parent_token = await login(client, parent_username, "Parent123!", slug)
    parent_headers = auth(parent_token)

    charge = await client.post(
        "/finance/internal-payments",
        json={
            "child_id": child["id"],
            "description": "Material escolar",
            "amount": "8500.00",
        },
        headers=headers,
    )
    assert charge.status_code == 201, charge.text
    charge_id = charge.json()["id"]
    other_child = (await client.post(
        "/children",
        json={"cedula": f"OTHER{uid()}", "first_name": "Outro", "last_name": "Aluno"},
        headers=headers,
    )).json()
    other_charge = await client.post(
        "/finance/internal-payments",
        json={
            "child_id": other_child["id"],
            "description": "Cobrança privada",
            "amount": "9000.00",
        },
        headers=headers,
    )
    assert other_charge.status_code == 201, other_charge.text

    parent_rows = await client.get(
        "/finance/parent/internal-payments", headers=parent_headers,
    )
    assert parent_rows.status_code == 200, parent_rows.text
    assert [row["id"] for row in parent_rows.json()] == [charge_id]

    uploaded = await client.post(
        "/finance/parent/internal-payments/proof",
        files={"file": ("pagamento.png", b"parent-proof", "image/png")},
        headers=parent_headers,
    )
    assert uploaded.status_code == 200, uploaded.text
    forbidden = await client.patch(
        f"/finance/parent/internal-payments/{other_charge.json()['id']}/submit",
        json={
            "proof_url": uploaded.json()["url"],
            "payment_method": "transfer",
            "payment_date": "2026-09-10",
        },
        headers=parent_headers,
    )
    assert forbidden.status_code == 404
    submitted = await client.patch(
        f"/finance/parent/internal-payments/{charge_id}/submit",
        json={
            "proof_url": uploaded.json()["url"],
            "payment_method": "transfer",
            "payment_date": "2026-09-10",
            "notes": "Transferência efectuada",
        },
        headers=parent_headers,
    )
    assert submitted.status_code == 200, submitted.text
    assert submitted.json()["status"] == "proof_submitted"

    school_queue = await client.get("/finance/internal-payments", headers=headers)
    queued = next(row for row in school_queue.json() if row["id"] == charge_id)
    assert queued["status"] == "proof_submitted"
    confirmed = await client.patch(
        f"/finance/internal-payments/{charge_id}/review",
        json={"action": "confirm"},
        headers=headers,
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["status"] == "paid"
