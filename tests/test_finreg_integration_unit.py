import uuid
import json
from pathlib import Path

import pytest
from fastapi import HTTPException

from app.models.finreg_integration import FinregSchoolConnection
from app.models.finance import Payment
from app.services.finreg import (
    FakeFinregAdapter,
    FinregError,
    billing_idempotency_key,
    school_context,
)
from app.services.finreg_events import synchronize_connection
from app.routers.finreg import _linked_guardian_child


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
    assert "hostSurfaces: capabilities.hostSurfaces" in host
    assert "FinregEmbeddedModuleHost(" in host
    assert "finregEmbeddedModules.containsKey" in host
    assert "onOpenWorkspace: _openWorkspace" not in host
    assert "package:url_launcher/url_launcher.dart" not in host
    assert "surfaceBuilders:" in host
    assert "configuredCapabilities: capabilities.configuredCapabilities" in host
    assert "blockedCapabilities: capabilities.blockedCapabilities" in host
    assert "onRefreshCapabilities: _refresh" in host
    assert "FinregAccountingOverviewScreen" not in host
    assert "FinregCashSessionsScreen" not in host
    assert "final canPay = invoice.status != 'paid'" in parent
    assert "/finreg/parent/receipts" in parent
    assert "/finreg/parent/statement" in parent


def test_host_parses_every_authoritative_workspace_without_capability_ids():
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "value['workspaces']" in host
    assert "workspace['capability_id']" in host
    assert "workspace['route']" in host
    assert "/finreg/embedded-session/$capabilityId" in host
    assert "finregEmbeddedModules[workspace.capabilityId]" in host


def test_each_capability_has_one_menu_entry_and_billing_uses_school_extension():
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "length: widget.workspaces.length" in host
    assert "widget.workspaces[_selected]" in host
    assert "capabilityOverrides: {'billing': schoolModule}" in host
    assert "const Tab(icon: Icon(Icons.school_outlined)" not in host
    assert "widget.capabilityOverrides[workspace.capabilityId]" in host
    assert "widget.sessionForCapability(capabilityId)" in host
    assert "_sessions.putIfAbsent" in host
    assert "final Set<String> _visitedCapabilityIds" in host
    assert "child: IndexedStack(" in host
    assert "key: ObjectKey(snapshot.data)" in host
    assert "onSessionExpired:" in host
    assert "_sessions.remove(capabilityId)" in host


def test_school_billing_resolves_and_validates_payer_learner_relationships():
    router = Path("app/routers/finreg.py").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert '@router.get("/guardians/{guardian_id}/pupils")' in router
    assert '@router.get("/guardians")' in router
    assert "require_finance_access" in router
    assert "ChildGuardian.guardian_id == Guardian.id" in router
    assert "The learner is not associated with the selected payer" in router
    assert router.count("await _linked_guardian_child(") == 2
    assert "pupilsForGuardian(String guardianId)" in host
    assert "'/finreg/guardians'" in host
    assert "'/finreg/guardians/$guardianId/pupils'" in host


@pytest.mark.asyncio
async def test_unlinked_payer_learner_pair_is_rejected_before_finreg():
    class EmptyResult:
        def one_or_none(self):
            return None

    class EmptySession:
        async def execute(self, _statement):
            return EmptyResult()

    with pytest.raises(HTTPException) as raised:
        await _linked_guardian_child(
            uuid.uuid4(), uuid.uuid4(), uuid.uuid4(), EmptySession()
        )
    assert raised.value.status_code == 422


def test_school_profile_requirements_have_an_authoritative_workspace():
    profiles = json.loads(Path(
        "../finreg/backend/app/module_manifests/profiles.json"
    ).read_text())
    capabilities = json.loads(Path(
        "../finreg/backend/app/module_manifests/capabilities.json"
    ).read_text())
    school = next(item for item in profiles if item["id"] == "school")
    by_id = {item["id"]: item for item in capabilities}
    missing = {
        capability_id
        for capability_id in school["requires"]
        if not by_id[capability_id].get("ui")
    }
    assert missing == set()


def test_workspace_launch_is_user_bound_and_never_exposes_client_credentials():
    router = Path("app/routers/finreg.py").read_text()
    assert '@router.post("/workspace-launch/{capability_id}")' in router
    assert 'getattr(user, "_roles_list", None)' in router
    assert "/delegated#{urlencode" in router
    assert '"external_user_id": str(user.id)' in router
    assert '"roles": roles' in router
    assert "FINREG_CLIENT_SECRET" not in router
    assert "urlencode({'code': launch['code']})" in router


def test_embedded_session_reuses_delegated_security_without_external_navigation():
    router = Path("app/routers/finreg.py").read_text()
    service = Path("app/services/finreg.py").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert '@router.post("/embedded-session/{capability_id}")' in router
    assert 'response.headers["Cache-Control"] = "no-store"' in router
    assert "exchange_delegated(launch[\"code\"])" in router
    assert 'f"{settings.FINREG_BASE_URL}/auth/delegated/exchange"' in service
    assert 'f"{settings.FINREG_BASE_URL}/auth/me"' in service
    assert "FINREG_CLIENT_SECRET" not in host
    assert "launchUrl(" not in host


def test_all_ci_jobs_share_the_reviewed_finreg_package_pin():
    expected = "52424156cea39258495a0aec1835cdfc31d6bdd9"
    assert Path(".github/finreg-packages-ref").read_text().strip() == expected

    flutter = Path(".github/workflows/flutter_build.yml").read_text()
    backend = Path(".github/workflows/backend_tests.yml").read_text()
    reference = "ref: ${{ steps.finreg-ref.outputs.ref }}"
    assert flutter.count(reference) == 3
    assert backend.count(reference) == 1
    assert "continue-on-error: true" not in flutter


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


def test_legacy_reduced_operational_finreg_screen_is_not_shipped():
    router = Path("app/routers/finreg.py").read_text()
    screen = Path("mobile/lib/features/admin/finance/finreg_operational_modules_screen.dart")
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert not screen.exists()
    assert "FinregOperationalModulesScreen" not in host
    # These proxy endpoints remain valid API integrations, but are no longer
    # presented as substitutes for the complete authoritative workspaces.
    assert '@router.get("/accounting/overview")' in router
    assert '"GET", "accounting/overview"' in router
    assert '@router.get("/cash-sessions")' in router
    assert '"GET", "cash-sessions"' in router


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
    assert "refresh_company_manifest_fingerprints" in deploy
    assert "CELLEN_WEB_ORIGIN=https://softensor.github.io" in deploy
    assert "CORS_ALLOWED_ORIGINS" in deploy
    assert "validate_cellen_finreg_release.sh" in deploy
    assert "Finreg permits the embedded Cellen Web origin" in source
    assert '--mode "$ACCEPTANCE_MODE"' in deploy
    assert '--agt-channel "$ACCEPTANCE_CHANNEL"' in deploy


def test_combined_vps_release_is_single_command_and_identity_checked():
    script = Path("deploy/release_cellen_finreg_from_vps.sh")
    source = script.read_text()
    assert script.stat().st_mode & 0o111
    assert "sudo -u jorgehel git -C \"$FINREG_DIR\" pull --ff-only origin master" in source
    assert "sudo -u jorgehel git -C \"$CELLEN_DIR\" pull --ff-only origin master" in source
    assert "deploy_finreg_school_finance.sh" in source
    assert "deploy-web-release.sh" in source
    assert "validate-web-release.sh" in source
    assert "finreg-release.json" in source
    assert "systemctl is-active finreg-api finreg-worker finreg-beat cellen-api" in source


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
