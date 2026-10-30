# -*- coding: utf-8 -*-
"""The school issues the reference, the family pays it.

Once the month is billed, the dispatcher opens one payment reference per
document and the guardian sees it in the app. The admin side therefore has to
answer two questions without being asked to create anything: how far did this
month's references get (sent, paid, stuck), and does this debt already have
one. These tests pin both read models.
"""
import uuid

import pytest
from sqlalchemy import update

from app.core.config import settings
from app.models.finance import PaymentReference
from app.models.finreg_integration import FinregBillingInstruction
from app.models.principia_pay import PrincipiaPayConnection
from app.routers import billing as billing_router
from app.services.billing_run import current_billing_month
from app.services.debt_control import _month_references
from app.services.secret_box import encrypt_secret
from tests.test_billing_run_api import _activate_finreg, _family, _scaffold


async def _activate_rail(db, school_id: uuid.UUID) -> None:
    await db.execute(
        update(PrincipiaPayConnection)
        .where(PrincipiaPayConnection.status == "active")
        .values(status="inactive")
    )
    db.add(
        PrincipiaPayConnection(
            school_id=school_id,
            client_id=f"rail-{school_id.hex[:8]}",
            api_key_ciphertext=encrypt_secret("pp_key"),
            status="active",
        )
    )
    await db.commit()


def _instruction(school_id, month, issue_status, reference_id=None):
    return FinregBillingInstruction(
        school_id=school_id,
        idempotency_key=f"cellen-run-{uuid.uuid4()}-{month}",
        command_type="billing_run",
        payload={"billing_month": month},
        status="confirmed",
        finreg_document_id=uuid.uuid4(),
        payment_reference_status=issue_status,
        payment_reference_id=reference_id,
    )


def _reference(school_id, guardian_id, document_id, status):
    return PaymentReference(
        school_id=school_id,
        billing_guardian_id=guardian_id,
        entity="00123",
        reference=str(uuid.uuid4().int)[:9],
        amount=50000,
        status=status,
        provider="principia_pay",
        finreg_document_id=document_id,
    )


@pytest.mark.asyncio
async def test_the_month_counts_references_sent_paid_and_stuck(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "ref-progress")
    await _activate_finreg(client, ctx, "fake")
    family = await _family(client, ctx, siblings=False)
    school_id = uuid.UUID(ctx["school"]["id"])
    guardian_id = uuid.UUID(family["guardian"]["id"])
    month = current_billing_month()

    # Without a rail connection the card must say so, not show zeros.
    before = await _month_references(db, school_id=school_id, month=month)
    assert before["enabled"] is False
    assert before["documents"] == 0

    await _activate_rail(db, school_id)
    paid = _reference(school_id, guardian_id, uuid.uuid4(), "paid")
    active = _reference(school_id, guardian_id, uuid.uuid4(), "active")
    db.add_all([paid, active])
    await db.flush()
    db.add_all([
        _instruction(school_id, month, "created", paid.id),
        _instruction(school_id, month, "created", active.id),
        _instruction(school_id, month, None),
        _instruction(school_id, month, "failed"),
        _instruction(school_id, month, "skipped"),
        # Another month's bill never counts towards this card.
        _instruction(school_id, "2020-01", "created"),
    ])
    await db.commit()

    result = await _month_references(db, school_id=school_id, month=month)

    assert result == {
        "enabled": True,
        "documents": 5,
        "sent": 2,
        "waiting": 1,
        "failed": 1,
        "skipped": 1,
        "paid": 1,
    }


@pytest.mark.asyncio
async def test_a_debt_row_carries_the_reference_the_family_already_has(
    client, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "ref-on-debt")
    await _activate_finreg(client, ctx, "fake")
    family = await _family(client, ctx, siblings=False)
    school_id = uuid.UUID(ctx["school"]["id"])
    guardian_id = uuid.UUID(family["guardian"]["id"])
    with_reference = uuid.uuid4()
    without_reference = uuid.uuid4()
    reference = _reference(school_id, guardian_id, with_reference, "active")
    reference.checkout_url = "https://pay.test/checkout/1"
    db.add(reference)
    await db.commit()

    async def fake_list_debts(db_, *, school_id, **kwargs):
        return {
            "count": 3,
            "rows": [
                {"document_id": str(with_reference), "outstanding": 50000.0},
                {"document_id": str(without_reference), "outstanding": 50000.0},
                # Internal invoices and malformed ids must not break the join.
                {"document_id": "not-a-uuid", "outstanding": 1.0},
            ],
        }

    monkeypatch.setattr(billing_router, "list_debts", fake_list_debts)

    response = await client.get("/billing/debts", headers=ctx["headers"])

    assert response.status_code == 200, response.text
    rows = response.json()["rows"]
    assert rows[0]["payment_reference"]["id"] == str(reference.id)
    assert rows[0]["payment_reference"]["entity"] == "00123"
    assert rows[0]["payment_reference"]["checkout_url"] == "https://pay.test/checkout/1"
    assert rows[1]["payment_reference"] is None
    assert rows[2]["payment_reference"] is None
