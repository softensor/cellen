"""Cellen's local ledger of FinReg fiscal documents (headless invoicing).

Every value on a ledger row must come from FinReg -- an instruction outcome,
an event, or a document refresh -- and the admin routes must only ever show a
school its own documents.
"""
import uuid
from decimal import Decimal

import pytest
from sqlalchemy import select

from app.models.finreg_integration import (
    FinregBillingInstruction,
    FinregDocument,
    FinregSchoolConnection,
)
from app.models.person import Child, Guardian
from app.services import finreg_ledger
from app.services.finreg import FakeFinregAdapter, FinregError
from tests.conftest import auth, uid


def _document(document_id, **overrides) -> dict:
    body = {
        "id": str(document_id),
        "document_type": "invoice",
        "full_document_number": "FT 2026/17",
        "document_status": "finalized",
        "agt_status": "pending",
        "currency_code": "AOA",
        "net_total": 100000.0,
        "tax_total": 14000.0,
        "gross_total": 114000.0,
        "document_date": "2026-11-02",
        "due_date": "2026-11-10",
        "customer_name": "Maria Encarregada",
        "customer_tax_id": "004512345LA041",
        "software_cert_number": "AGT/123/2026",
        "lines": [{
            "description": "Propina Novembro",
            "quantity": 1,
            "unit_price": 100000,
            "discount_pct": 0,
            "tax_rate": 14,
            # FinReg's DocumentLineOut field names, as production returns them
            "net_amount": 100000,
            "tax_amount": 14000,
            "gross_amount": 114000,
        }],
    }
    body.update(overrides)
    return body


async def _school_with_family(db, make_school, mode="live"):
    school, token, slug, _ = await make_school("ledger")
    school_id = uuid.UUID(school["id"])
    guardian = Guardian(school_id=school_id, first_name="Maria", last_name="Encarregada", nif="004512345LA041")
    child = Child(school_id=school_id, cedula=f"C-{uid()}", first_name="Joana", last_name="Aluna")
    db.add_all([guardian, child])
    db.add(FinregSchoolConnection(school_id=school_id, finreg_company_id=uuid.uuid4(), mode=mode))
    await db.commit()
    return school_id, token, guardian, child


def _draft_instruction(school_id, guardian, child, *, document_id=None, snapshot=None, period="2026-11"):
    instruction_id = uuid.uuid4()
    return FinregBillingInstruction(
        id=instruction_id,
        school_id=school_id,
        idempotency_key=f"cellen-sales-{instruction_id}",
        command_type="issue_invoice",
        status="confirmed",
        finreg_document_id=document_id,
        result_snapshot=snapshot,
        payload={
            "guardian": {"external_id": str(guardian.id), "data": {}},
            "draft": {
                "external_id": str(instruction_id),
                "context": {"pupil_id": str(child.id), "billing_period": period},
                "document": {"lines": []},
            },
        },
    )


async def test_a_confirmed_draft_is_ledgered_with_finregs_own_values(db, make_school):
    school_id, _, guardian, child = await _school_with_family(db, make_school)
    document_id = uuid.uuid4()
    instruction = _draft_instruction(
        school_id, guardian, child, document_id=document_id, snapshot=_document(document_id)
    )
    db.add(instruction)
    await db.commit()

    row = await finreg_ledger.record_instruction(db, instruction)
    await db.commit()

    assert row.reference == str(instruction.id)
    assert row.kind == "invoice"
    assert row.full_document_number == "FT 2026/17"
    assert row.gross_total == Decimal("114000.00")
    assert row.guardian_id == guardian.id
    assert row.pupil_id == child.id
    assert row.billing_period == "2026-11"
    assert row.needs_refresh is True  # AGT has not answered yet

    # Recording twice is the same row, never a second one.
    await finreg_ledger.record_instruction(db, instruction)
    await db.commit()
    count = (await db.execute(select(FinregDocument).where(
        FinregDocument.school_id == school_id
    ))).scalars().all()
    assert len(count) == 1


async def test_a_billing_run_row_is_completed_by_a_refresh(db, make_school):
    school_id, _, guardian, child = await _school_with_family(db, make_school)
    document_id = uuid.uuid4()
    instruction = FinregBillingInstruction(
        school_id=school_id,
        idempotency_key=f"run-{uuid.uuid4()}",
        command_type="billing_run",
        status="confirmed",
        finreg_document_id=document_id,
        result_snapshot={
            "status": "generated",
            "document_id": str(document_id),
            "full_document_number": "FT 2026/18",
            "document_status": "finalized",
        },
        payload={
            "guardian": {"external_id": str(guardian.id), "data": {}},
            "plan": {"context": {"pupil_id": str(child.id), "billing_period": "2026-11"}},
        },
    )
    db.add(instruction)
    await db.commit()

    row = await finreg_ledger.record_instruction(db, instruction)
    await db.commit()
    # A run response carries no totals: the row says so instead of guessing.
    assert row.reference == str(document_id)
    assert row.full_document_number == "FT 2026/18"
    assert row.document_status == "finalized"
    assert row.gross_total is None

    adapter = FakeFinregAdapter({
        f"GET documents/{document_id}": _document(
            document_id, full_document_number="FT 2026/18", agt_status="accepted"
        ),
    })
    await finreg_ledger.refresh_document(db, row, adapter=adapter)
    await db.commit()
    assert row.gross_total == Decimal("114000.00")
    assert row.agt_status == "accepted"
    assert row.needs_refresh is False


async def test_a_failed_refresh_keeps_the_row_and_backs_off(db, make_school):
    school_id, _, guardian, child = await _school_with_family(db, make_school)
    document_id = uuid.uuid4()
    instruction = _draft_instruction(
        school_id, guardian, child, document_id=document_id, snapshot=_document(document_id)
    )
    db.add(instruction)
    await db.commit()
    row = await finreg_ledger.record_instruction(db, instruction)
    adapter = FakeFinregAdapter({
        f"GET documents/{instruction.id}": FinregError("timeout", "FinReg timed out", retryable=True),
    })
    with pytest.raises(FinregError):
        await finreg_ledger.refresh_document(db, row, adapter=adapter)
    await db.commit()
    assert row.refresh_attempts == 1
    assert row.last_error_code == "timeout"
    assert row.gross_total == Decimal("114000.00")
    assert row.needs_refresh is True


async def test_events_update_known_documents_and_ignore_foreign_ones(db, make_school):
    school_id, _, guardian, child = await _school_with_family(db, make_school)
    document_id = uuid.uuid4()
    instruction = _draft_instruction(school_id, guardian, child)
    db.add(instruction)
    await db.commit()

    finalized = {
        "event_type": "document.finalized",
        "entity_type": "document",
        "entity_id": str(document_id),
        "payload": _document(document_id, agt_status="accepted"),
    }
    finalized["payload"]["external_id"] = str(instruction.id)
    row = await finreg_ledger.apply_event(db, school_id, finalized)
    await db.commit()
    assert row is not None
    assert row.reference == str(instruction.id)
    assert row.pupil_id == child.id
    assert row.needs_refresh is False

    # A document no Cellen instruction produced is not listed.
    stranger = {
        "event_type": "document.finalized",
        "entity_type": "document",
        "entity_id": str(uuid.uuid4()),
        "payload": _document(uuid.uuid4()),
    }
    assert await finreg_ledger.apply_event(db, school_id, stranger) is None

    # A correction cancels the original and ledgers the credit note.
    credit_id = uuid.uuid4()
    corrected = {
        "event_type": "document.corrected",
        "entity_type": "document",
        "entity_id": str(credit_id),
        "payload": {
            "original_external_id": str(instruction.id),
            "credit_note_id": str(credit_id),
            "credit_note_number": "NC 2026/3",
        },
    }
    credit = await finreg_ledger.apply_event(db, school_id, corrected)
    await db.commit()
    await db.refresh(row)
    assert row.document_status == "cancelled"
    assert row.corrected_by_document_id == credit_id
    assert credit.kind == "credit_note"
    assert credit.corrects_document_id == document_id
    assert credit.full_document_number == "NC 2026/3"
    assert credit.pupil_id == child.id

    # A replay of the same correction changes nothing.
    again = await finreg_ledger.apply_event(db, school_id, corrected)
    assert again.id == credit.id

    # An AGT answer, should FinReg emit one, lands on the row.
    agt = {
        "event_type": "agt.submission_changed",
        "entity_type": "document",
        "entity_id": str(credit_id),
        "payload": {"document_id": str(credit_id), "agt_status": "rejected", "message": "NIF inválido"},
    }
    updated = await finreg_ledger.apply_event(db, school_id, agt)
    assert updated.agt_status == "rejected"
    assert updated.agt_message == "NIF inválido"


async def test_admin_lists_only_its_own_school_and_backfills(client, db, make_school):
    school_id, token, guardian, child = await _school_with_family(db, make_school)
    other_id, other_token, other_guardian, other_child = await _school_with_family(db, make_school)

    first = uuid.uuid4()
    second = uuid.uuid4()
    db.add_all([
        _draft_instruction(school_id, guardian, child, document_id=first, snapshot=_document(first)),
        _draft_instruction(
            school_id, guardian, child, document_id=second,
            snapshot=_document(second, full_document_number="FT 2026/19", agt_status="rejected",
                               agt_response_message="Série inválida"),
            period="2026-10",
        ),
        _draft_instruction(
            other_id, other_guardian, other_child, document_id=uuid.uuid4(),
            snapshot=_document(uuid.uuid4()),
        ),
    ])
    await db.commit()

    # Nothing was ledgered yet: the first visit backfills from the outbox.
    response = await client.get("/finreg/admin/documents", headers=auth(token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == 2
    assert {item["full_document_number"] for item in body["items"]} == {"FT 2026/17", "FT 2026/19"}
    assert body["items"][0]["pupil_name"] == "Joana Aluna"
    assert body["summary"]["rejected"] == 1

    rejected = await client.get("/finreg/admin/documents?state=rejected", headers=auth(token))
    assert [item["full_document_number"] for item in rejected.json()["items"]] == ["FT 2026/19"]
    assert rejected.json()["items"][0]["agt_message"] == "Série inválida"

    by_period = await client.get("/finreg/admin/documents?period=2026-10", headers=auth(token))
    assert by_period.json()["total"] == 1
    by_name = await client.get("/finreg/admin/documents?q=Joana", headers=auth(token))
    assert by_name.json()["total"] == 2
    by_number = await client.get("/finreg/admin/documents?q=2026/19", headers=auth(token))
    assert by_number.json()["total"] == 1

    document = body["items"][0]
    detail = await client.get(f"/finreg/admin/documents/{document['id']}", headers=auth(token))
    assert detail.status_code == 200
    line = detail.json()["lines"][0]
    assert line["description"] == "Propina Novembro"
    assert line["line_total"] == 114000
    assert line["net_amount"] == 100000
    assert line["tax_amount"] == 14000
    assert detail.json()["software_cert_number"] == "AGT/123/2026"

    # Another school never sees, opens or downloads this document.
    foreign = await client.get(f"/finreg/admin/documents/{document['id']}", headers=auth(other_token))
    assert foreign.status_code == 404
    foreign_pdf = await client.get(f"/finreg/admin/documents/{document['id']}/pdf", headers=auth(other_token))
    assert foreign_pdf.status_code == 404
    other_list = await client.get("/finreg/admin/documents", headers=auth(other_token))
    assert other_list.json()["total"] == 1


async def test_a_draft_document_has_no_pdf_yet(client, db, make_school):
    school_id, token, guardian, child = await _school_with_family(db, make_school)
    document_id = uuid.uuid4()
    db.add(_draft_instruction(
        school_id, guardian, child, document_id=document_id,
        snapshot=_document(document_id, document_status="draft", full_document_number=None),
    ))
    await db.commit()
    listed = (await client.get("/finreg/admin/documents", headers=auth(token))).json()
    item = listed["items"][0]
    assert item["state"] == "processing"
    pdf = await client.get(f"/finreg/admin/documents/{item['id']}/pdf", headers=auth(token))
    assert pdf.status_code == 409
    assert pdf.json()["detail"]["code"] == "document_not_finalized"


async def _ledgered(client, db, make_school, *, mode="fake"):
    school_id, token, guardian, child = await _school_with_family(db, make_school, mode=mode)
    document_id = uuid.uuid4()
    db.add(_draft_instruction(
        school_id, guardian, child, document_id=document_id,
        snapshot=_document(document_id, agt_status="accepted"),
    ))
    await db.commit()
    listed = (await client.get("/finreg/admin/documents", headers=auth(token))).json()
    return school_id, token, guardian, listed["items"][0]


async def test_a_correction_goes_through_the_outbox_once(client, db, make_school, monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    school_id, token, _, document = await _ledgered(client, db, make_school)
    request_id = str(uuid.uuid4())

    response = await client.post(
        f"/finreg/admin/documents/{document['id']}/corrections",
        json={"request_id": request_id, "reason": "Valor errado"},
        headers=auth(token),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "confirmed"
    assert body["document"]["state"] == "cancelled"
    assert body["credit_note"]["kind"] == "credit_note"
    assert body["credit_note"]["corrects_document_id"] == document["finreg_document_id"]

    # The same dialog pressed again is the same correction.
    replay = await client.post(
        f"/finreg/admin/documents/{document['id']}/corrections",
        json={"request_id": request_id, "reason": "Valor errado"},
        headers=auth(token),
    )
    assert replay.status_code == 201
    assert replay.json()["instruction_id"] == body["instruction_id"]
    assert replay.json()["credit_note"]["id"] == body["credit_note"]["id"]

    # A new request for an already cancelled document is refused.
    again = await client.post(
        f"/finreg/admin/documents/{document['id']}/corrections",
        json={"request_id": str(uuid.uuid4()), "reason": "Outra vez"},
        headers=auth(token),
    )
    assert again.status_code == 409
    assert again.json()["detail"]["code"] == "document_already_cancelled"

    credit_notes = (await client.get(
        "/finreg/admin/documents?kind=credit_note", headers=auth(token)
    )).json()
    assert credit_notes["total"] == 1

    activity = (await client.get("/finreg/admin/activity", headers=auth(token))).json()
    labels = [item["label"] for item in activity["items"]]
    assert "Anulação (nota de crédito)" in labels
    correction = next(item for item in activity["items"] if item["command"] == "correction")
    assert correction["status"] == "confirmed"
    assert correction["actor"]  # the admin's username, not "Sistema"
    assert correction["actor"] != "Sistema"


async def test_corrections_are_refused_when_fiscal_writes_are_off(client, db, make_school, monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    _, token, _, document = await _ledgered(client, db, make_school, mode="shadow")
    response = await client.post(
        f"/finreg/admin/documents/{document['id']}/corrections",
        json={"request_id": str(uuid.uuid4()), "reason": "Valor errado"},
        headers=auth(token),
    )
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "finreg_writes_disabled"


async def test_receipts_are_listed_per_school(client, db, make_school):
    from datetime import date as _date
    from app.models.finance import Payment

    school_id, token, guardian, _ = await _school_with_family(db, make_school)
    other_id, other_token, other_guardian, _ = await _school_with_family(db, make_school)
    mine = Payment(
        school_id=school_id, billing_guardian_id=guardian.id, payment_date=_date(2026, 11, 3),
        amount=Decimal("114000"), payment_method="transfer",
        finreg_payment_external_reference=uuid.uuid4(),
    )
    local_only = Payment(
        school_id=school_id, billing_guardian_id=guardian.id, payment_date=_date(2026, 11, 4),
        amount=Decimal("5000"), payment_method="cash",
    )
    theirs = Payment(
        school_id=other_id, billing_guardian_id=other_guardian.id, payment_date=_date(2026, 11, 3),
        amount=Decimal("1"), payment_method="cash",
        finreg_payment_external_reference=uuid.uuid4(),
    )
    db.add_all([mine, local_only, theirs])
    await db.commit()

    body = (await client.get("/finreg/admin/receipts", headers=auth(token))).json()
    assert body["total"] == 1
    assert body["items"][0]["guardian_name"] == "Maria Encarregada"
    assert body["items"][0]["amount"] == 114000.0
    searched = (await client.get("/finreg/admin/receipts?q=Maria", headers=auth(token))).json()
    assert searched["total"] == 1

    foreign = await client.get(f"/finreg/admin/receipts/{mine.id}/pdf", headers=auth(other_token))
    assert foreign.status_code == 404


async def test_fiscal_setup_is_a_read_only_checklist(client, db, make_school, monkeypatch):
    from app.core.config import settings
    from app.models.finance import BillingItem
    from app.routers import finreg_admin

    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    profile = {
        "name": "Colégio Teste", "tax_id": "5000000001", "address": "Rua 1", "city": "Luanda",
        "software_cert_number": "AGT/1/2026", "agt_channel": "sandbox", "non_fiscal": False,
        "series": [{"document_type": "invoice", "series_code": "FT26", "is_active": True, "agt_registered": True}],
        "agt_api_secret": "must-not-pass-through",
    }

    class _Adapter(FakeFinregAdapter):
        async def request(self, method, operation, payload, **kwargs):
            if operation == "fiscal-profile":
                return profile
            return await super().request(method, operation, payload, **kwargs)

    monkeypatch.setattr(finreg_admin, "HttpFinregAdapter", _Adapter)
    school_id, token, guardian, _ = await _school_with_family(db, make_school, mode="live")
    db.add(Guardian(school_id=school_id, first_name="Sem", last_name="Nif"))
    db.add(BillingItem(school_id=school_id, code=f"X-{uid()}", name="Uniforme", unit_price=Decimal("1000"),
                       iva_rate=Decimal("14")))
    await db.commit()

    body = (await client.get("/finreg/admin/setup", headers=auth(token))).json()
    assert body["operational"] is True
    assert body["profile"]["name"] == "Colégio Teste"
    assert "agt_api_secret" not in body["profile"]
    levels = {check["key"]: check["level"] for check in body["checks"]}
    assert levels == {
        "connection": "ok",
        "fiscal_profile": "ok",
        "agt_channel": "warning",  # sandbox, not production
        "series": "ok",
        "billing_items": "error",
        "guardian_nif": "warning",
    }
    items = next(check for check in body["checks"] if check["key"] == "billing_items")
    assert "Uniforme" in items["detail"]


async def test_fiscal_setup_shows_the_certificate_finreg_prints_when_the_profile_lacks_it(
    client, db, make_school, monkeypatch
):
    """Production FinReg leaves the tenant's certificate empty but stamps it on
    every document; the setup card shows what the documents carry."""
    from app.core.config import settings
    from app.routers import finreg_admin

    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)

    class _Adapter(FakeFinregAdapter):
        async def request(self, method, operation, payload, **kwargs):
            if operation == "fiscal-profile":
                return {"name": "Colégio Teste", "tax_id": "5000000001", "software_cert_number": None,
                        "agt_channel": "production", "non_fiscal": False, "series": []}
            return await super().request(method, operation, payload, **kwargs)

    monkeypatch.setattr(finreg_admin, "HttpFinregAdapter", _Adapter)
    school_id, token, _, _ = await _school_with_family(db, make_school, mode="live")
    db.add(FinregDocument(
        school_id=school_id, finreg_document_id=uuid.uuid4(), reference=f"ref-{uid()}",
        document_status="finalized", snapshot={"software_cert_number": "FE/501/AGT/2026"},
    ))
    await db.commit()

    body = (await client.get("/finreg/admin/setup", headers=auth(token))).json()
    assert body["profile"]["software_cert_number"] == "FE/501/AGT/2026"


async def test_fiscal_setup_without_a_connection_says_so(client, db, make_school):
    school, token, _, _ = await make_school("nosetup")
    body = (await client.get("/finreg/admin/setup", headers=auth(token))).json()
    assert body["operational"] is False
    assert body["profile"] is None
    assert body["checks"][0]["key"] == "connection"
    assert body["checks"][0]["level"] == "warning"


async def test_the_refresh_pass_is_silent_while_integration_is_off(db, make_school, monkeypatch):
    from app.core.config import settings

    calls = []

    class _Recording(FakeFinregAdapter):
        async def request(self, method, operation, payload, **kwargs):
            calls.append(operation)
            return await super().request(method, operation, payload, **kwargs)

    monkeypatch.setattr(finreg_ledger, "HttpFinregAdapter", _Recording)
    school_id, _, guardian, child = await _school_with_family(db, make_school, mode="live")
    document_id = uuid.uuid4()
    db.add(_draft_instruction(school_id, guardian, child, document_id=document_id,
                              snapshot=_document(document_id)))
    await db.commit()

    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", False)
    assert await finreg_ledger.refresh_pending(db) == (0, 0)
    assert calls == []

    monkeypatch.setattr(settings, "FINREG_INTEGRATION_ENABLED", True)
    await finreg_ledger.refresh_pending(db)
    assert any(call.startswith("documents/") for call in calls)
