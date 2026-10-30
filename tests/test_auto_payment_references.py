# -*- coding: utf-8 -*-
"""The monthly bill carries its payment route.

A parent opened the October invoice and the card said the reference was not
available, although an administrator could generate one by hand. Generating
it at emission is the product rule: every finalized monthly document of a
school whose rail connection is active gets its reference automatically, and
the parent document projection shows it on the card.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select, update

from app.core.config import settings
from app.models.finance import PaymentReference
from app.models.finreg_integration import FinregBillingInstruction
from app.models.principia_pay import PrincipiaPayConnection
from app.services import principia_pay
from app.services.billing_run import BillingError
from app.services.parent_finance import list_parent_documents
from app.services.principia_pay_client import Reference
from app.services.secret_box import encrypt_secret
from app.utils.agt import today_luanda
from tests.conftest import auth, login
from tests.test_billing_run_api import (
    _activate_finreg,
    _family,
    _item,
    _policy,
    _scaffold,
)


async def _confirmed_run(client: AsyncClient, ctx: dict) -> dict:
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
    assert run["instructions"][0]["status"] == "confirmed"
    return run


async def _deactivate_other_rails(db) -> None:
    """Each test owns the only active rail connection in the shared database."""
    await db.execute(
        update(PrincipiaPayConnection)
        .where(PrincipiaPayConnection.status == "active")
        .values(status="inactive")
    )
    await db.commit()


async def _rail_connection(db, school_id: str) -> PrincipiaPayConnection:
    await _deactivate_other_rails(db)
    connection = PrincipiaPayConnection(
        school_id=uuid.UUID(school_id),
        client_id="rail-client-auto",
        api_key_ciphertext=encrypt_secret("pp_key"),
        status="active",
    )
    db.add(connection)
    await db.commit()
    await db.refresh(connection)
    return connection


async def _instruction_for_run(db, school_id: str) -> FinregBillingInstruction:
    return (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == uuid.UUID(school_id),
                FinregBillingInstruction.command_type == "billing_run",
            )
        )
    ).scalars().one()


@pytest.mark.asyncio
async def test_the_emitted_month_gets_one_reference_per_document(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    assert instruction.finreg_document_id is not None

    await _rail_connection(db, ctx["school"]["id"])

    async def fake_list_debts(db_, *, school_id, **kwargs):
        return {
            "rows": [{
                "source": "finreg",
                "document_id": str(instruction.finreg_document_id),
                "document_number": "FT AUTO/2026",
                "student_id": family["children"]["ana"]["id"],
                "guardian_id": family["guardian"]["id"],
                "outstanding": 100000.0,
                "currency_code": "AOA",
            }]
        }

    calls = []

    async def fake_create(db_, *, school_id, document_id, debt_row=None, **kwargs):
        calls.append(document_id)
        reference = PaymentReference(
            school_id=school_id,
            billing_guardian_id=uuid.UUID(family["guardian"]["id"]),
            entity="00123",
            reference=f"98765432{len(calls)}",
            amount=100000,
            status="active",
            provider="principia_pay",
            finreg_document_id=uuid.UUID(document_id),
        )
        db_.add(reference)
        await db_.flush()
        return reference

    monkeypatch.setattr(principia_pay, "is_configured", _always_true)
    monkeypatch.setattr(principia_pay, "list_debts", fake_list_debts)
    monkeypatch.setattr(principia_pay, "create_reference", fake_create)

    result = await principia_pay.issue_references_for_confirmed_runs(db)

    assert result == {"created": 1, "skipped": 0, "failed": 0}
    assert calls == [str(instruction.finreg_document_id)]
    await db.refresh(instruction)
    assert instruction.payment_reference_status == "created"
    assert instruction.payment_reference_id is not None
    assert instruction.payment_reference_error is None

    # A second tick must not create a second rail reference.
    again = await principia_pay.issue_references_for_confirmed_runs(db)
    assert again == {"created": 0, "skipped": 0, "failed": 0}
    assert len(calls) == 1


async def _always_true(*args, **kwargs):
    return True


@pytest.mark.asyncio
async def test_the_auto_issuer_persists_a_real_reference_for_the_document(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """The batched ``debt_row`` must flow through the real create path.

    The pass hands the receivables row it already matched to
    ``create_reference`` instead of forcing a second feed read; this pins
    that the reference that lands in the database is anchored to the
    instruction's FinReg document, not to a fresh lookup.
    """
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref-real")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    await _rail_connection(db, ctx["school"]["id"])

    async def fake_create(self, **kwargs):
        return Reference(
            id="rail-auto-2",
            provider="appypay",
            caller_reference=kwargs.get("caller_reference"),
            kind="reference",
            entity="00456",
            reference="123456789",
            redirect_url=None,
            amount=kwargs["amount"],
            currency="AOA",
            status="pending",
            expires_at=None,
            paid_at=None,
            created_at=today_luanda(),
        )

    feed_reads = []

    async def one_school_feed(db_, *, school_id, **kwargs):
        feed_reads.append(school_id)
        return {
            "rows": [{
                "source": "finreg",
                "document_id": str(instruction.finreg_document_id),
                "document_number": "FT REAL/2026",
                "student_id": family["children"]["ana"]["id"],
                "guardian_id": family["guardian"]["id"],
                "outstanding": 100000.0,
                "currency_code": "AOA",
            }]
        }

    monkeypatch.setattr(principia_pay, "is_configured", _always_true)
    monkeypatch.setattr(principia_pay, "list_debts", one_school_feed)
    monkeypatch.setattr(
        principia_pay.PrincipiaPayClient, "create_reference", fake_create
    )

    result = await principia_pay.issue_references_for_confirmed_runs(db)
    assert result == {"created": 1, "skipped": 0, "failed": 0}
    # One feed read for the school, not one per document.
    assert len(feed_reads) == 1

    reference = (
        await db.execute(
            select(PaymentReference).where(
                PaymentReference.finreg_document_id
                == instruction.finreg_document_id
            )
        )
    ).scalars().one()
    assert reference.status == "active"
    assert reference.entity == "00456"
    assert reference.reference == "123456789"
    assert reference.billing_guardian_id == uuid.UUID(family["guardian"]["id"])
    assert reference.invoice_id is None
    await db.refresh(instruction)
    assert instruction.payment_reference_id == reference.id
    assert instruction.payment_reference_status == "created"



@pytest.mark.asyncio
async def test_a_settled_document_is_skipped_once_and_never_retried(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref-settled")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    await _rail_connection(db, ctx["school"]["id"])

    async def empty_receivables(db_, *, school_id, **kwargs):
        return {"rows": []}

    async def must_not_create(*args, **kwargs):
        raise AssertionError("a settled document must not open a reference")

    monkeypatch.setattr(principia_pay, "is_configured", _always_true)
    monkeypatch.setattr(principia_pay, "list_debts", empty_receivables)
    monkeypatch.setattr(principia_pay, "create_reference", must_not_create)

    first = await principia_pay.issue_references_for_confirmed_runs(db)
    assert first == {"created": 0, "skipped": 1, "failed": 0}
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    assert instruction.payment_reference_status == "skipped"
    assert instruction.payment_reference_error == "debt_not_found"

    second = await principia_pay.issue_references_for_confirmed_runs(db)
    assert second == {"created": 0, "skipped": 0, "failed": 0}


@pytest.mark.asyncio
async def test_a_rail_outage_retries_with_backoff_instead_of_losing_the_reference(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref-retry")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    await _rail_connection(db, ctx["school"]["id"])

    async def fake_list_debts(db_, *, school_id, **kwargs):
        return {
            "rows": [{
                "source": "finreg",
                "document_id": str(instruction.finreg_document_id),
                "document_number": "FT AUTO/2026",
                "student_id": family["children"]["ana"]["id"],
                "guardian_id": family["guardian"]["id"],
                "outstanding": 100000.0,
                "currency_code": "AOA",
            }]
        }

    attempts = []

    async def unavailable(*args, **kwargs):
        attempts.append(1)
        raise BillingError(
            "principia_pay_unavailable", "O serviço não respondeu.", 502
        )

    monkeypatch.setattr(principia_pay, "is_configured", _always_true)
    monkeypatch.setattr(principia_pay, "list_debts", fake_list_debts)
    monkeypatch.setattr(principia_pay, "create_reference", unavailable)

    first = await principia_pay.issue_references_for_confirmed_runs(db)
    assert first == {"created": 0, "skipped": 0, "failed": 1}
    await db.refresh(instruction)
    assert instruction.payment_reference_status == "failed"
    assert instruction.payment_reference_attempts == 1
    assert instruction.payment_reference_next_attempt_at is not None
    assert instruction.payment_reference_next_attempt_at > datetime.now(timezone.utc)

    # Before the backoff elapses the row is not selected again.
    second = await principia_pay.issue_references_for_confirmed_runs(db)
    assert second == {"created": 0, "skipped": 0, "failed": 0}
    assert len(attempts) == 1

    # Once the backoff has elapsed, the next tick retries.
    instruction.payment_reference_next_attempt_at = (
        datetime.now(timezone.utc) - timedelta(seconds=1)
    )
    await db.commit()
    third = await principia_pay.issue_references_for_confirmed_runs(db)
    assert third == {"created": 0, "skipped": 0, "failed": 1}
    assert len(attempts) == 2


@pytest.mark.asyncio
async def test_a_school_without_an_active_connection_is_never_registered(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref-off")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)

    async def must_not_create(*args, **kwargs):
        raise AssertionError("no reference may be opened for an opted-out school")

    monkeypatch.setattr(principia_pay, "is_configured", _always_true)
    monkeypatch.setattr(principia_pay, "create_reference", must_not_create)

    # Previous tests' schools stay in the shared database; the pass must do
    # nothing for all of them once none has an active connection.
    await _deactivate_other_rails(db)
    result = await principia_pay.issue_references_for_confirmed_runs(db)
    assert result == {"created": 0, "skipped": 0, "failed": 0}
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    assert instruction.payment_reference_status is None


@pytest.mark.asyncio
async def test_the_parent_card_shows_the_documents_active_reference(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "auto-ref-card")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    instruction = await _instruction_for_run(db, ctx["school"]["id"])

    reference = PaymentReference(
        school_id=uuid.UUID(ctx["school"]["id"]),
        billing_guardian_id=uuid.UUID(family["guardian"]["id"]),
        entity="00123",
        reference="987654321",
        amount=100000,
        status="active",
        provider="principia_pay",
        finreg_document_id=instruction.finreg_document_id,
        finreg_document_number="FT AUTO/2026",
        expires_at=datetime.now(timezone.utc) + timedelta(days=30),
    )
    db.add(reference)
    await db.commit()

    documents = await list_parent_documents(
        db,
        school_id=uuid.UUID(ctx["school"]["id"]),
        guardian_id=uuid.UUID(family["guardian"]["id"]),
    )
    assert len(documents) == 1
    document = documents[0]
    assert document["multicaixa_entity"] == "00123"
    assert document["multicaixa_ref"] == "987654321"
    assert document["payment_reference"]["status"] == "active"
    assert document["payment_reference"]["checkout_url"] is None


@pytest.mark.asyncio
async def test_the_parent_endpoint_opens_a_reference_for_the_family_document(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_test")
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_BASE_URL", "https://rail.test")
    ctx = await _scaffold(client, make_school, "auto-ref-parent")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _confirmed_run(client, ctx)
    instruction = await _instruction_for_run(db, ctx["school"]["id"])
    await _rail_connection(db, ctx["school"]["id"])

    async def fake_list_debts(db_, *, school_id, **kwargs):
        return {
            "rows": [{
                "source": "finreg",
                "document_id": str(instruction.finreg_document_id),
                "document_number": "FT AUTO/2026",
                "student_id": family["children"]["ana"]["id"],
                "guardian_id": family["guardian"]["id"],
                "outstanding": 100000.0,
                "currency_code": "AOA",
            }]
        }

    async def fake_create(self, **kwargs):
        return Reference(
            id="rail-auto-1",
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
        )

    monkeypatch.setattr(principia_pay, "list_debts", fake_list_debts)
    monkeypatch.setattr(
        principia_pay.PrincipiaPayClient, "create_reference", fake_create
    )

    token = await login(
        client,
        family["guardian"]["username"],
        "Guardian1!",
        ctx["school"]["slug"],
    )
    response = await client.post(
        "/finance/parent/payment-references/principia-pay",
        json={"document_id": str(instruction.finreg_document_id)},
        headers=auth(token),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["entity"] == "00123"
    assert body["reference"] == "987654321"
    assert body["status"] == "active"
