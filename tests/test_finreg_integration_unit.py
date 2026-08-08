import uuid
from pathlib import Path

import pytest

from app.models.finreg_integration import FinregSchoolConnection
from app.models.finance import Payment
from app.services.finreg import (
    FakeFinregAdapter,
    FinregError,
    billing_idempotency_key,
    school_context,
)
from app.services.finreg_events import synchronize_connection


def test_primary_finance_route_uses_finreg_module_without_legacy_fallback():
    root = Path(__file__).resolve().parents[1]
    router = (root / "mobile/lib/core/router/router.dart").read_text()
    host = (root / "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart").read_text()

    assert "path: '/admin/finance',              builder: (_, __) => const FinregSalesHostScreen()" in router
    assert "FinregSchoolBillingModule(" in host
    assert "return const InvoicesScreen()" not in host


def test_finreg_parent_payment_cross_system_references_are_persisted():
    assert "finreg_document_external_reference" in Payment.__table__.columns
    assert "finreg_payment_external_reference" in Payment.__table__.columns


def test_school_extensions_and_parent_finreg_payments_are_wired():
    root = Path(__file__).resolve().parents[1]
    host = (root / "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart").read_text()
    parent = (root / "mobile/lib/features/parent/finance/parent_invoices_screen.dart").read_text()
    assert host.count("FinregModuleExtension(") >= 7
    assert "final canPay = invoice.status != 'paid'" in parent
    assert "/finreg/parent/receipts" in parent
    assert "/finreg/parent/statement" in parent


def test_billing_key_is_stable_and_period_scoped():
    school, contract = uuid.uuid4(), uuid.uuid4()
    first = billing_idempotency_key(school, contract, "2026-09")
    assert first == billing_idempotency_key(school, contract, "2026-09")
    assert first != billing_idempotency_key(school, contract, "2026-10")
    assert "2026-09" not in first


def test_school_context_uses_only_contract_fields():
    instruction, school, pupil = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    value = school_context(
        instruction_id=instruction, school_id=school, pupil_id=pupil, pupil_name="Pupil",
        enrolment_id=None, academic_year_id=None, academic_year_label="2026/2027",
        billing_period="2026-09",
    )
    assert value["schema"] == "school/v1"
    assert value["source_reference"] == str(instruction)
    assert value["pupil_id"] == str(pupil)


@pytest.mark.asyncio
async def test_fake_adapter_replays_success_without_duplicate():
    adapter = FakeFinregAdapter()
    kwargs = dict(idempotency_key="same", correlation_id="correlation", actor_reference="actor")
    assert await adapter.execute("documents", {}, **kwargs) == await adapter.execute("documents", {"different": True}, **kwargs)
    assert len(adapter.results) == 1


@pytest.mark.asyncio
async def test_fake_adapter_models_unknown_outcome():
    expected = FinregError("timeout_unknown", "timeout", retryable=True, unknown_outcome=True)
    adapter = FakeFinregAdapter({"documents": expected})
    with pytest.raises(FinregError) as raised:
        await adapter.execute("documents", {}, idempotency_key="key", correlation_id="c", actor_reference="a")
    assert raised.value.unknown_outcome


@pytest.mark.asyncio
async def test_event_sync_rejects_credentials_for_another_company():
    expected_company = uuid.uuid4()
    connection = FinregSchoolConnection(
        school_id=uuid.uuid4(), finreg_company_id=expected_company, mode="shadow"
    )

    class WrongCompanyAdapter:
        async def capabilities(self, actor_reference):
            return {"company_id": str(uuid.uuid4())}

    with pytest.raises(FinregError) as raised:
        await synchronize_connection(None, connection, adapter=WrongCompanyAdapter())
    assert raised.value.code == "company_mismatch"


@pytest.mark.asyncio
async def test_event_sync_records_receipt_mapping_and_monotonic_cursor():
    company_id, school_id = uuid.uuid4(), uuid.uuid4()
    external_id, entity_id, event_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    connection = FinregSchoolConnection(
        school_id=school_id, finreg_company_id=company_id, mode="shadow",
        last_event_sequence=0,
    )

    class EmptyResult:
        def scalar_one_or_none(self):
            return None

    class MemorySession:
        def __init__(self):
            self.added = []
            self.commits = 0

        async def execute(self, statement):
            return EmptyResult()

        async def get(self, model, key):
            return None

        def add(self, value):
            self.added.append(value)

        async def commit(self):
            self.commits += 1

    class EventAdapter:
        async def capabilities(self, actor_reference):
            return {"company_id": str(company_id)}

        async def request(self, method, operation, payload, *, actor_reference):
            return [{
                "sequence_id": 4, "event_id": str(event_id),
                "event_type": "customer.upserted", "entity_type": "customer",
                "entity_id": str(entity_id), "payload": {"external_id": str(external_id)},
            }]

    db = MemorySession()
    assert await synchronize_connection(db, connection, adapter=EventAdapter()) == 1
    assert connection.last_event_sequence == 4
    assert {type(value).__name__ for value in db.added} == {
        "FinregEntityMapping", "FinregEventReceipt"
    }
    assert await synchronize_connection(db, connection, adapter=EventAdapter()) == 0
