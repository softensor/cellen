# -*- coding: utf-8 -*-
"""Payments recorded by the school on the family's behalf.

Parents pay at the counter, by transfer or in cash all the time. The finance
desk must be able to settle the exact debt the parent portal shows, in
whichever engine owns the school, idempotently, and with the cash session
rules the rest of the cashier obeys.
"""
import uuid
from datetime import timedelta
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.config import settings
from app.models.finance import Invoice, Payment, Receipt
from app.models.finreg_integration import FinregBillingInstruction
from app.services.finreg import FakeFinregAdapter, FinregError
from app.services.in_person_payment import record_in_person_payment
from app.utils.agt import today_luanda
from tests.conftest import auth, uid
from tests.test_billing_run_api import (
    _activate_finreg,
    _family as _billing_family,
    _item as _billing_item,
    _policy as _billing_policy,
    _scaffold as _billing_scaffold,
)
from tests.test_finance_phases import _family, _invoice, _scaffold


async def _record(client: AsyncClient, ctx: dict, body: dict) -> dict:
    response = await client.post(
        "/finance/payments/record", json=body, headers=ctx["headers"]
    )
    return {"status": response.status_code, "body": response.json()}


# ─── internal mode ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_desk_records_a_transfer_and_the_invoice_settles_with_a_receipt(
    client: AsyncClient, make_school, db,
):
    ctx = await _scaffold(client, make_school, "inperson")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 50000)
    key = f"desk-{uid()}"

    result = await _record(
        client,
        ctx,
        {
            "document_id": invoice["id"],
            "amount": 50000,
            "payment_method": "transfer",
            "reference": "TRF-2026-001",
            "notes": "Pago na secretaria",
            "idempotency_key": key,
        },
    )
    assert result["status"] == 201, result["body"]
    payment = result["body"]
    assert payment["status"] == "normal"
    assert payment["payment_method"] == "transfer"
    assert payment["allocated_invoices"] == [
        {"invoice_id": invoice["id"], "amount_applied": 50000.0}
    ]
    assert payment["notes"] == "Pago na secretaria · Ref: TRF-2026-001"
    assert payment["guardian_name"]

    receipt = (
        await db.execute(
            select(Receipt).where(Receipt.payment_id == uuid.UUID(payment["id"]))
        )
    ).scalar_one_or_none()
    assert receipt is not None
    assert float(receipt.gross_total) == 50000.0

    row = await db.get(Invoice, uuid.UUID(invoice["id"]))
    await db.refresh(row)
    assert row.status == "paid"

    # The same click, retried after a lost response: same payment, no double
    # charge.
    repeated = await _record(
        client,
        ctx,
        {
            "document_id": invoice["id"],
            "amount": 50000,
            "payment_method": "transfer",
            "idempotency_key": key,
        },
    )
    assert repeated["status"] == 201, repeated["body"]
    assert repeated["body"]["id"] == payment["id"]
    count = (
        await db.execute(
            select(func.count())
            .select_from(Payment)
            .where(Payment.idempotency_key == key)
        )
    ).scalar_one()
    assert count == 1


@pytest.mark.asyncio
async def test_cash_at_the_counter_requires_an_open_cash_session(
    client: AsyncClient, make_school,
):
    ctx = await _scaffold(client, make_school, "inperson-cash")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 50000)

    result = await _record(
        client,
        ctx,
        {
            "document_id": invoice["id"],
            "amount": 50000,
            "payment_method": "cash",
            "idempotency_key": f"desk-{uid()}",
        },
    )
    assert result["status"] == 400, result["body"]
    assert result["body"]["detail"]["code"] == "cash_session_closed"


@pytest.mark.asyncio
async def test_amount_above_the_balance_is_refused(
    client: AsyncClient, make_school,
):
    ctx = await _scaffold(client, make_school, "inperson-over")
    family = await _family(client, ctx)
    invoice = await _invoice(client, ctx, family, ctx["first"], 50000)

    result = await _record(
        client,
        ctx,
        {
            "document_id": invoice["id"],
            "amount": 60000,
            "payment_method": "transfer",
            "idempotency_key": f"desk-{uid()}",
        },
    )
    assert result["status"] == 422, result["body"]
    assert result["body"]["detail"]["code"] == "amount_above_balance"


@pytest.mark.asyncio
async def test_settled_or_unknown_document_is_not_payable(
    client: AsyncClient, make_school,
):
    ctx = await _scaffold(client, make_school, "inperson-404")
    result = await _record(
        client,
        ctx,
        {
            "document_id": str(uuid.uuid4()),
            "amount": 1000,
            "payment_method": "transfer",
            "idempotency_key": f"desk-{uid()}",
        },
    )
    assert result["status"] == 404, result["body"]
    assert result["body"]["detail"]["code"] == "debt_not_found"


# ─── FinReg mode ────────────────────────────────────────────────────────────


def _receivable(document_id, *, guardian_id: str, child_id: str, amount=100000.0) -> dict:
    due = today_luanda()
    return {
        "as_of": due.isoformat(),
        "count": 1,
        "total_outstanding": amount,
        "rows": [
            {
                "document_id": str(document_id),
                "document_external_id": f"doc-{uid()}",
                "full_document_number": "FT 2026/1",
                "document_type": "FT",
                "document_status": "finalized",
                "document_date": due.isoformat(),
                "due_date": (due + timedelta(days=5)).isoformat(),
                "customer_external_id": guardian_id,
                "customer_name": "Maria Guard",
                "currency_code": "AOA",
                "gross_total": amount,
                "credited_total": 0.0,
                "paid_total": 0.0,
                "outstanding_amount": amount,
                "days_overdue": 0,
                "bucket": "current",
                "school_context": {"pupil_id": child_id, "pupil_name": "Ana Test"},
                "lines": [],
            }
        ],
    }


async def _confirmed_instruction(client, ctx, db) -> FinregBillingInstruction:
    generated = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert generated.status_code == 201, generated.text
    instruction = (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == ctx["school_id"],
                FinregBillingInstruction.command_type == "billing_run",
            )
        )
    ).scalar_one()
    assert instruction.status == "confirmed"
    assert instruction.finreg_document_id is not None
    return instruction


@pytest.mark.asyncio
async def test_finreg_school_settles_the_fiscal_document_from_the_desk(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _billing_scaffold(client, make_school, "inperson-finreg")
    ctx["tuition_item"] = await _billing_item(client, ctx, "Mensalidade", 100000)
    await _billing_policy(client, ctx)
    family = await _billing_family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    instruction = await _confirmed_instruction(client, ctx, db)

    adapter = FakeFinregAdapter(
        outcomes={
            "GET receivables": _receivable(
                instruction.finreg_document_id,
                guardian_id=family["guardian"]["id"],
                child_id=family["children"]["ana"]["id"],
            )
        }
    )
    payment = await record_in_person_payment(
        db,
        school_id=ctx["school_id"],
        document_id=instruction.finreg_document_id,
        amount=Decimal("100000"),
        payment_method="transfer",
        reference="TRF-9",
        idempotency_key=f"desk-{uid()}",
        adapter=adapter,
    )

    assert payment.status == "normal"
    assert payment.finreg_document_external_reference == instruction.id
    assert payment.finreg_payment_external_reference == payment.id
    assert payment.notes == "Ref: TRF-9"


class _FailFirstSettlementAdapter(FakeFinregAdapter):
    """Answers the first POST as a timeout, then behaves normally."""

    def __init__(self, outcomes: dict):
        super().__init__(outcomes)
        self.failed = False

    async def request(self, method, operation, payload, **kwargs):
        if (
            method.upper() == "POST"
            and operation.startswith("payments/")
            and not self.failed
        ):
            self.failed = True
            raise FinregError("timeout", "FinReg did not answer in time", retryable=True)
        return await super().request(method, operation, payload, **kwargs)


@pytest.mark.asyncio
async def test_lost_finreg_answer_resumes_the_same_payment_on_retry(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _billing_scaffold(client, make_school, "inperson-retry")
    ctx["tuition_item"] = await _billing_item(client, ctx, "Mensalidade", 100000)
    await _billing_policy(client, ctx)
    family = await _billing_family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    instruction = await _confirmed_instruction(client, ctx, db)
    adapter = _FailFirstSettlementAdapter(
        outcomes={
            "GET receivables": _receivable(
                instruction.finreg_document_id,
                guardian_id=family["guardian"]["id"],
                child_id=family["children"]["ana"]["id"],
            )
        }
    )
    key = f"desk-{uid()}"

    with pytest.raises(Exception) as first:
        await record_in_person_payment(
            db,
            school_id=ctx["school_id"],
            document_id=instruction.finreg_document_id,
            amount=Decimal("100000"),
            payment_method="transfer",
            idempotency_key=key,
            adapter=adapter,
        )
    assert getattr(first.value, "status_code", None) == 503
    assert getattr(first.value, "code", None) == "timeout"

    pending = (
        await db.execute(
            select(Payment).where(
                Payment.school_id == ctx["school_id"],
                Payment.idempotency_key == key,
            )
        )
    ).scalar_one()
    assert pending.status == "pending_finreg"

    # The parent retries from the desk with the same key while FinReg is back.
    # The receivable may already be gone from the open feed; the mirror row is
    # the resume point, not a fresh lookup.
    resumed = await record_in_person_payment(
        db,
        school_id=ctx["school_id"],
        document_id=instruction.finreg_document_id,
        amount=Decimal("100000"),
        payment_method="transfer",
        idempotency_key=key,
        adapter=adapter,
    )
    assert resumed.id == pending.id
    assert resumed.status == "normal"
    assert resumed.finreg_payment_external_reference == resumed.id
    count = (
        await db.execute(
            select(func.count())
            .select_from(Payment)
            .where(
                Payment.school_id == ctx["school_id"],
                Payment.idempotency_key == key,
            )
        )
    ).scalar_one()
    assert count == 1
