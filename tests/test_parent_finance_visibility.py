# -*- coding: utf-8 -*-
"""What a family sees after the school generates the month.

Acceptance case reported by the owner: an October billing run was generated,
the parents logged in and the portal showed nothing payable. The monthly run
stages its context under ``plan.context`` (not ``draft.context``) and its
amounts live only in the composed plan lines, while FinReg's run response
carries the document id but no amounts. The parent projection has to read all
three sources, and a second parent of the same child must see the same
documents.
"""
import uuid
from datetime import timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.config import settings
from app.models.finreg_integration import FinregBillingInstruction
from app.services.finreg import FakeFinregAdapter, FinregError
from app.services.parent_finance import list_parent_documents
from app.utils.agt import today_luanda
from tests.conftest import auth, login, uid
from tests.test_billing_run_api import (
    _activate_finreg,
    _family,
    _item,
    _policy,
    _scaffold,
)


async def _run_month(client: AsyncClient, ctx: dict) -> dict:
    response = await client.post(
        "/billing/runs",
        json={
            "billing_month": ctx["month"],
            "school_year_id": ctx["year"]["id"],
        },
        headers=ctx["headers"],
    )
    assert response.status_code == 201, response.text
    return response.json()["run"]


async def _parent_login(client: AsyncClient, ctx: dict, guardian: dict) -> str:
    return await login(
        client,
        guardian["username"],
        "Guardian1!",
        ctx["school"]["slug"],
    )


def _expected_status(due_iso: str) -> str:
    from datetime import date

    return "overdue" if date.fromisoformat(due_iso) < today_luanda() else "pending"


@pytest.mark.asyncio
async def test_parent_sees_the_confirmed_month_with_amounts_and_child(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """The owner's defect: run generated, parent portal empty."""
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-run")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")

    run = await _run_month(client, ctx)
    assert run["status"] == "completed"
    assert run["instructions"][0]["status"] == "confirmed"

    token = await _parent_login(client, ctx, family["guardian"])
    response = await client.get("/finreg/parent/documents", headers=auth(token))
    assert response.status_code == 200, response.text
    documents = response.json()
    assert len(documents) == 1, documents

    document = documents[0]
    assert document["finreg"] is True
    assert document["child_id"] == family["children"]["ana"]["id"]
    assert document["child_name"] == "Ana Test"
    # The month the school billed, not null: it lives in plan.context /
    # billing_month, never in the run snapshot.
    assert document["reference_month"] == ctx["first"].isoformat()
    # The amount Cellen composed, because fake mode has no receivable feed.
    assert document["gross_total"] == 100000.0
    assert document["balance"] == 100000.0
    due = (ctx["first"] + timedelta(days=5)).isoformat()
    assert document["due_date"] == due
    assert document["status"] == _expected_status(due)
    # The FinReg document is what a payment must target.
    assert document["document_id"]
    assert document["full_document_number"] not in (None, "", "—")


@pytest.mark.asyncio
async def test_second_parent_of_the_same_child_sees_the_family_document(
    client: AsyncClient, make_school, db, monkeypatch,
):
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-second")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _run_month(client, ctx)

    created = await client.post(
        "/guardians",
        json={
            "first_name": "Paulo",
            "last_name": f"Guard{uid()[:4]}",
            "username": f"grd-{uid()}",
            "password": "Guardian1!",
        },
        headers=ctx["headers"],
    )
    assert created.status_code == 201, created.text
    second = created.json()
    linked = await client.post(
        f"/guardians/{second['id']}/children",
        json={
            "child_id": family["children"]["ana"]["id"],
            "relationship_type": "father",
            "is_primary_contact": False,
        },
        headers=ctx["headers"],
    )
    assert linked.status_code == 201, linked.text

    token = await _parent_login(client, ctx, second)
    response = await client.get("/finreg/parent/documents", headers=auth(token))
    assert response.status_code == 200, response.text
    documents = response.json()
    assert len(documents) == 1, documents
    assert documents[0]["child_id"] == family["children"]["ana"]["id"]
    assert documents[0]["balance"] == 100000.0


@pytest.mark.asyncio
async def test_document_settled_in_finreg_reads_as_paid_not_payable(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """FinReg only returns open receivables; a settled one must read paid."""
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-paid")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _run_month(client, ctx)

    # The fake adapter answers the feed with an empty page: the monthly
    # document is no longer open, so it was settled (or credited).
    adapter = FakeFinregAdapter()
    documents = await list_parent_documents(
        db,
        school_id=ctx["school_id"],
        guardian_id=uuid.UUID(family["guardian"]["id"]),
        adapter=adapter,
    )
    assert len(documents) == 1, documents
    assert documents[0]["status"] == "paid"
    assert documents[0]["balance"] == 0.0
    assert documents[0]["amount_paid"] == 100000.0


@pytest.mark.asyncio
async def test_a_draft_document_is_processing_not_paid(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """FinReg opens receivables only for finalized documents.

    A shadow run -- or a document whose finalize never happened -- must not
    read as settled simply because the feed does not list it.
    """
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-draft")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _run_month(client, ctx)

    instruction = (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == ctx["school_id"],
                FinregBillingInstruction.command_type == "billing_run",
            )
        )
    ).scalar_one()
    instruction.result_snapshot = {
        **(instruction.result_snapshot or {}),
        "status": "draft",
    }
    await db.commit()

    documents = await list_parent_documents(
        db,
        school_id=ctx["school_id"],
        guardian_id=uuid.UUID(family["guardian"]["id"]),
    )
    assert len(documents) == 1, documents
    assert documents[0]["status"] == "processing"
    assert documents[0]["balance"] == 100000.0
    assert documents[0]["amount_paid"] == 0.0

    # The same run kept in shadow mode never finalizes its documents, so the
    # family must not see a payable month there either.
    instruction.result_snapshot = {
        **(instruction.result_snapshot or {}),
        "status": "confirmed",
    }
    await db.commit()
    await _activate_finreg(client, ctx, "shadow")
    documents = await list_parent_documents(
        db,
        school_id=ctx["school_id"],
        guardian_id=uuid.UUID(family["guardian"]["id"]),
    )
    assert len(documents) == 1, documents
    assert documents[0]["status"] == "processing"


@pytest.mark.asyncio
async def test_feed_failure_falls_back_to_composed_amounts(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """A FinReg outage must not make a debt vanish from the parent portal."""
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-outage")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _run_month(client, ctx)

    adapter = FakeFinregAdapter(
        outcomes={
            "GET receivables": FinregError(
                "finreg_unavailable", "Finreg is down", retryable=True
            )
        }
    )
    documents = await list_parent_documents(
        db,
        school_id=ctx["school_id"],
        guardian_id=uuid.UUID(family["guardian"]["id"]),
        adapter=adapter,
    )
    assert len(documents) == 1, documents
    document = documents[0]
    assert document["gross_total"] == 100000.0
    assert document["balance"] == 100000.0
    assert document["status"] in {"pending", "overdue"}
    assert document["reference_month"] == ctx["first"].isoformat()


@pytest.mark.asyncio
async def test_payment_recorded_at_the_school_settles_the_parent_document(
    client: AsyncClient, make_school, db, monkeypatch,
):
    """An in-person payment must flip the portal row to paid."""
    from decimal import Decimal

    from app.services.in_person_payment import record_in_person_payment

    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    ctx = await _scaffold(client, make_school, "parent-inperson")
    ctx["tuition_item"] = await _item(client, ctx, "Mensalidade", 100000)
    await _policy(client, ctx)
    family = await _family(client, ctx, siblings=False)
    await _activate_finreg(client, ctx, "fake")
    await _run_month(client, ctx)

    instruction = (
        await db.execute(
            select(FinregBillingInstruction).where(
                FinregBillingInstruction.school_id == ctx["school_id"],
                FinregBillingInstruction.command_type == "billing_run",
            )
        )
    ).scalar_one()
    document_id = instruction.finreg_document_id
    assert document_id is not None

    receivable = {
        "as_of": today_luanda().isoformat(),
        "count": 1,
        "total_outstanding": 100000.0,
        "rows": [
            {
                "document_id": str(document_id),
                "document_external_id": f"doc-{uid()}",
                "full_document_number": "FT 2026/1",
                "document_type": "FT",
                "document_status": "finalized",
                "document_date": ctx["first"].isoformat(),
                "due_date": (ctx["first"] + timedelta(days=5)).isoformat(),
                "customer_external_id": family["guardian"]["id"],
                "customer_name": "Maria Guard",
                "currency_code": "AOA",
                "gross_total": 100000.0,
                "credited_total": 0.0,
                "paid_total": 0.0,
                "outstanding_amount": 100000.0,
                "days_overdue": 0,
                "bucket": "current",
                "school_context": {
                    "pupil_id": family["children"]["ana"]["id"],
                    "pupil_name": "Ana Test",
                },
                "lines": [],
            }
        ],
    }
    adapter = FakeFinregAdapter(outcomes={"GET receivables": receivable})

    payment = await record_in_person_payment(
        db,
        school_id=ctx["school_id"],
        document_id=document_id,
        amount=Decimal("100000"),
        payment_method="transfer",
        idempotency_key=f"desk-{uid()}",
        adapter=adapter,
    )
    assert payment.status == "normal"
    assert payment.finreg_payment_external_reference == payment.id
    assert payment.finreg_document_external_reference == instruction.id

    documents = await list_parent_documents(
        db,
        school_id=ctx["school_id"],
        guardian_id=uuid.UUID(family["guardian"]["id"]),
    )
    assert len(documents) == 1, documents
    assert documents[0]["status"] == "paid"
    assert documents[0]["balance"] == 0.0
