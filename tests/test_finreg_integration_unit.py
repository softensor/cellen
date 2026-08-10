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
    assert host.count("requiredCapabilities:") >= 7
    assert "configuredCapabilities: capabilities.configuredCapabilities" in host
    assert "blockedCapabilities: capabilities.blockedCapabilities" in host
    assert "onRefreshCapabilities: _refresh" in host
    assert "final canPay = invoice.status != 'paid'" in parent
    assert "/finreg/parent/receipts" in parent
    assert "/finreg/parent/statement" in parent


def test_flutter_jobs_share_the_reviewed_finreg_package_pin():
    workflow = Path(".github/workflows/flutter_build.yml").read_text()
    expected = "abeb031dbb69a37b532856da6d2cae1237861872"
    assert f"FINREG_PACKAGES_REF: {expected}" in workflow
    assert workflow.count("ref: ${{ env.FINREG_PACKAGES_REF }}") == 3
    assert "50dd3c06ef039e2ec5af8b0eace97df69ca9bdb0" not in workflow
    assert "continue-on-error: true" not in workflow


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


def test_authoritative_saft_export_is_exposed_by_router_and_embedded_host():
    router = Path("app/routers/finreg.py").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert '@router.get("/reports/saft-sales")' in router
    assert "downloadSaftSales" in host
    assert "/finreg/reports/saft-sales" in host


def test_aggregate_production_acceptance_runner_is_release_ready():
    runner = Path("deploy/validate_cellen_finreg_release.sh")
    source = runner.read_text()
    assert runner.stat().st_mode & 0o111
    assert "Scheduler task has no failure" in source
    assert "Recurring generation is idempotent" in source
    assert "SAF-T exports through Cellen into authoritative Finreg" in source
    assert "Evidence report:" in source
    assert 'sudo -u jorgehel git -C "$repo" status' in source
    assert "enabled_capabilities" in source
    assert "composition_profile" in source
    assert 'module_registry.resolve("school", [], "angola")' not in source
    deploy = Path("deploy/deploy_finreg_school_finance.sh").read_text()
    assert "validate_cellen_finreg_release.sh" in deploy
    assert '--mode "$ACCEPTANCE_MODE"' in deploy
    assert '--agt-channel "$ACCEPTANCE_CHANNEL"' in deploy


def test_finreg_promotions_use_bounded_readiness_polling():
    helper = Path("deploy/lib/wait_for_finreg_services.sh").read_text()
    assert "wait_for_finreg_services()" in helper
    assert "attempt <= attempts" in helper
    assert "http://127.0.0.1:8003/ready" in helper
    assert "http://127.0.0.1:8001/health" in helper
    for name in (
        "deploy_finreg_school_finance.sh",
        "promote_finreg_pilot.sh",
        "promote_finreg_agt_sandbox.sh",
        "promote_finreg_live.sh",
    ):
        source = Path("deploy", name).read_text()
        assert 'source "$CELLEN_DIR/deploy/lib/wait_for_finreg_services.sh"' in source
        assert "wait_for_finreg_services" in source
        assert "sleep 5" not in source


def test_agt_mode_lifecycle_is_explicit_and_fail_closed():
    validator = Path("deploy/validate_cellen_finreg_release.sh").read_text()
    pilot = Path("deploy/promote_finreg_pilot.sh").read_text()
    sandbox = Path("deploy/promote_finreg_agt_sandbox.sh")
    live = Path("deploy/promote_finreg_live.sh").read_text()
    assert "shadow\\|disabled" in validator
    assert "pilot\\|(offline|sandbox)" in validator
    assert "live\\|production" in validator
    assert "set_agt_channel" in pilot
    assert "ensure_offline_series" in pilot
    assert "SET generation_mode='finalize'" in pilot
    assert sandbox.stat().st_mode & 0o111
    assert "Expected pilot+offline" in sandbox.read_text()
    assert "no_automatic_replay=true" in sandbox.read_text()
    assert "series_code LIKE 'OFF%'" in sandbox.read_text()
    assert "current channel=$AGT_CHANNEL" in live
    assert "set_agt_channel 5000413178 production" in live
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "agtChannel: value['agt_channel']" in host


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
