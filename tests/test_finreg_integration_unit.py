import uuid
import json
import re
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml
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
from app.models.school import _SEGMENT_DEFAULTS
from app.core.config import settings
from app.routers import finreg as finreg_router
from app.routers.finreg import (
    FINREG_ERP_CAPABILITIES,
    _allowed_local_capabilities,
    _finreg_plan,
    _linked_guardian_child,
    _manifest_plan,
    _plan_allowed_capabilities,
)


def test_primary_finance_route_opens_finreg_without_an_embedded_copy():
    root = Path(__file__).resolve().parents[1]
    router = (root / "mobile/lib/core/router/router.dart").read_text()
    host = (root / "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart").read_text()

    assert "path: '/admin/finance'" in router
    assert "const FinregSalesHostScreen()" in router
    assert "FinregEmbeddedModuleHost(" not in host
    assert "package:finreg_app" not in host
    assert "package:finreg_client_sdk" not in host
    assert "FinregSchoolBillingModule(" not in host
    assert "finregUrlLauncher(" in host
    assert "return const InvoicesScreen()" not in host


def test_finreg_parent_payment_cross_system_references_are_persisted():
    assert "finreg_document_external_reference" in Payment.__table__.columns
    assert "finreg_payment_external_reference" in Payment.__table__.columns


def test_school_extensions_and_parent_finreg_payments_are_wired():
    root = Path(__file__).resolve().parents[1]
    host = (root / "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart").read_text()
    hubs = (root / "mobile/lib/features/admin/finance/school_finance_hubs.dart").read_text()
    parent = (root / "mobile/lib/features/parent/finance/parent_invoices_screen.dart").read_text()
    assert "FinregEmbeddedModuleHost(" not in host
    assert "finregEmbeddedModules" not in host
    assert "onOpenWorkspace: _openWorkspace" not in host
    assert "package:url_launcher/url_launcher.dart" in host
    assert "/finreg/workspace-launch/$capabilityId" in host
    assert "_SchoolBillingOperations" not in host
    # The native finance shortcuts live in the workflow hubs now.
    assert "'/admin/finance/payment-proofs'" in hubs
    assert "FinregAccountingOverviewScreen" not in host
    assert "FinregCashSessionsScreen" not in host
    assert "final canPay = invoice.status != 'paid'" in parent
    assert "/finreg/parent/receipts" in parent
    assert "/finreg/parent/statement" in parent


def test_local_finreg_policy_can_only_narrow_authoritative_workspaces():
    available = {"billing", "accounting", "payroll"}
    features = {
        "finreg_role_capabilities": {
            "finance_officer": ["billing", "outside-composition"],
        }
    }
    school = SimpleNamespace(features=features, resolved_features=features)
    school_admin = SimpleNamespace(_roles={"school_admin"})
    finance_officer = SimpleNamespace(_roles={"finance_officer"})
    coordinator = SimpleNamespace(_roles={"coordinator"})

    assert _allowed_local_capabilities(school, school_admin, available) == available
    assert _allowed_local_capabilities(school, finance_officer, available) == {"billing"}
    assert _allowed_local_capabilities(school, coordinator, available) == set()


def test_custom_roles_are_first_class_finreg_policy_options():
    features = {
        "custom_roles": [{
            "key": "custom_bursar",
            "label": "Tesouraria",
            "permissions": ["finance"],
            "enabled": True,
        }],
        "finreg_role_capabilities": {"custom_bursar": ["billing"]},
    }
    school = SimpleNamespace(features=features, resolved_features=features)
    user = SimpleNamespace(_roles={"custom_bursar"})
    assert _allowed_local_capabilities(
        school, user, {"billing", "payroll"}
    ) == {"billing"}


def test_a_school_manifest_without_the_add_on_hides_erp_workspaces():
    school = SimpleNamespace(features={}, resolved_features={})
    workspaces = {
        "billing",
        "catalog",
        "parties",
        "payments",
        "receivables",
        "recurring_billing",
        "reporting",
        "accounting",
        "payroll",
        "purchasing",
        "treasury",
    }
    manifest = {
        "navigable_capabilities": sorted(workspaces - FINREG_ERP_CAPABILITIES),
        "erp_capabilities": [],
        "erp_entitled": False,
    }

    assert _manifest_plan(school, manifest) == {
        "plan": "billing",
        "erp_enabled": False,
        "erp_capabilities": [],
    }
    assert (
        _plan_allowed_capabilities(school, workspaces, manifest)
        == workspaces - FINREG_ERP_CAPABILITIES
    )
    assert FINREG_ERP_CAPABILITIES == {"accounting", "payroll", "purchasing", "treasury"}


def test_finreg_erp_add_on_in_the_manifest_unlocks_the_full_workspace_set():
    # The local mirror is deliberately off: FinReg's manifest decides.
    school = SimpleNamespace(features={}, resolved_features={})
    workspaces = {
        "billing", "accounting", "payroll", "purchasing", "treasury",
    }
    manifest = {
        "navigable_capabilities": sorted(workspaces),
        "erp_capabilities": sorted(FINREG_ERP_CAPABILITIES & workspaces),
        "erp_entitled": True,
    }

    plan = _manifest_plan(school, manifest)
    assert plan["plan"] == "erp"
    assert plan["erp_enabled"] is True
    assert plan["erp_capabilities"] == sorted(FINREG_ERP_CAPABILITIES & workspaces)
    assert _plan_allowed_capabilities(school, workspaces, manifest) == workspaces


def test_an_older_finreg_keeps_the_local_plan_mirror():
    features = {"finreg_erp": True}
    school = SimpleNamespace(features=features, resolved_features=features)
    workspaces = {"billing", "accounting", "payroll", "purchasing", "treasury"}

    assert _finreg_plan(school)["plan"] == "erp"
    assert _manifest_plan(school, {"vertical": "school"})["erp_enabled"] is True
    assert _plan_allowed_capabilities(school, workspaces) == workspaces

    plain = SimpleNamespace(features={}, resolved_features={})
    assert _manifest_plan(plain, {"vertical": "school"})["erp_enabled"] is False
    assert (
        _plan_allowed_capabilities(plain, workspaces)
        == workspaces - FINREG_ERP_CAPABILITIES
    )


def test_every_school_segment_sells_the_billing_plan_by_default():
    for segment, defaults in _SEGMENT_DEFAULTS.items():
        assert defaults["finreg"] is True, segment
        assert defaults["finreg_erp"] is False, segment


def test_the_plan_is_enforced_on_capabilities_launch_and_local_policy():
    router = Path("app/routers/finreg.py").read_text()
    assert 'manifest["finreg_plan"] = _manifest_plan(school, manifest)' in router
    assert "capability_id in FINREG_ERP_CAPABILITIES" in router
    assert '"code": "finreg_erp_not_enabled"' in router
    assert router.count("_plan_allowed_capabilities(") == 5
    assert "available_set = _plan_allowed_capabilities(" in router
    assert "available = _plan_allowed_capabilities(" in router
    assert 'return_to = {"label": "Cellen", "url": settings.CELLEN_WEB_URL}' in router


class _LaunchAdapter:
    """Stands in for FinReg's HTTP adapter on the launch path only."""

    manifest: dict = {}
    launches: list[dict] = []

    async def capabilities(self, _external_user_id):
        return type(self).manifest

    async def workspace_launch(self, **kwargs):
        type(self).launches.append(kwargs)
        return {
            "url": "https://finreg.test/#/delegated?code=abc",
            "target_path": "/billing",
            "expires_in": 60,
        }


class _LaunchSession:
    def __init__(self, school, mode="pilot"):
        self.school = school
        self.mode = mode

    async def execute(self, _statement):
        connection = SimpleNamespace(mode=self.mode)
        return SimpleNamespace(scalar_one_or_none=lambda: connection)

    async def get(self, _model, _identifier):
        return self.school


def _launch_school():
    return SimpleNamespace(
        id=uuid.uuid4(),
        features={},
        resolved_features={},
    )


def _launch_user():
    return SimpleNamespace(
        id=uuid.uuid4(),
        username="admin",
        email="admin@cellen.app",
        _roles={"school_admin"},
        _roles_list=["school_admin"],
    )


def _launch_manifest(*, erp_entitled: bool) -> dict:
    workspaces = [{"capability_id": "billing"}, {"capability_id": "accounting"}]
    navigable = ["billing"] + (["accounting"] if erp_entitled else [])
    return {
        "erp_entitled": erp_entitled,
        "erp_capabilities": (
            sorted(FINREG_ERP_CAPABILITIES) if erp_entitled else []
        ),
        "navigable_capabilities": navigable,
        "workspaces": workspaces,
    }


@pytest.mark.asyncio
async def test_the_erp_addon_cannot_be_launched_without_the_entitlement(
    monkeypatch,
):
    _LaunchAdapter.manifest = _launch_manifest(erp_entitled=False)
    _LaunchAdapter.launches = []
    monkeypatch.setattr(finreg_router, "HttpFinregAdapter", _LaunchAdapter)
    monkeypatch.setattr(settings, "CELLEN_WEB_URL", None)
    session = _LaunchSession(_launch_school())
    user = _launch_user()

    with pytest.raises(HTTPException) as raised:
        await finreg_router.workspace_launch(
            "accounting", user=user, school_id=uuid.uuid4(), db=session
        )

    assert raised.value.status_code == 403
    assert raised.value.detail["code"] == "finreg_erp_not_enabled"
    assert _LaunchAdapter.launches == []

    # The base billing plan still launches; without a host address the mint
    # carries no return target rather than a broken one.
    result = await finreg_router.workspace_launch(
        "billing", user=user, school_id=uuid.uuid4(), db=session
    )
    assert result["url"].startswith("https://finreg.test/")
    assert _LaunchAdapter.launches[0]["capability_id"] == "billing"
    assert _LaunchAdapter.launches[0]["return_to"] is None


@pytest.mark.asyncio
async def test_the_erp_launch_carries_the_host_return_target(monkeypatch):
    _LaunchAdapter.manifest = _launch_manifest(erp_entitled=True)
    _LaunchAdapter.launches = []
    monkeypatch.setattr(finreg_router, "HttpFinregAdapter", _LaunchAdapter)
    monkeypatch.setattr(settings, "CELLEN_WEB_URL", "https://cellen.test")

    await finreg_router.workspace_launch(
        "accounting",
        user=_launch_user(),
        school_id=uuid.uuid4(),
        db=_LaunchSession(_launch_school()),
    )

    assert _LaunchAdapter.launches[0]["capability_id"] == "accounting"
    assert _LaunchAdapter.launches[0]["return_to"] == {
        "label": "Cellen",
        "url": "https://cellen.test",
    }


def test_local_module_access_is_separate_from_finreg_control_plane():
    router = Path("app/routers/finreg.py").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    for role in (
        "coordinator", "finance_officer", "secretary", "teacher", "nurse",
        "parent", "student",
    ):
        assert f'"{role}"' in router
    assert '@router.get("/local-access-policy")' in router
    assert '@router.put("/local-access-policy")' in router
    assert router.count("user=Depends(require_school_admin)") >= 2
    assert "Local policy cannot grant a capability outside Finreg composition" in router
    assert router.count("Module is not granted to this school role") == 1
    assert "authority\": \"local_access_only" in router
    assert "Acessos e funções" in host
    assert "Não podem ativar módulos" in host
    assert "for (final definition in _roles)" in host
    assert "payload['custom_roles']" in host
    assert "role_workspaces" in router
    assert "role_features" in router
    assert "school_features" in router
    assert "role_available" in router
    assert "Áreas do Cellen" in host
    assert "Módulos financeiros Finreg" in host
    assert "Função desativada para esta escola" in host
    settings = Path("mobile/lib/features/admin/school_settings_screen.dart").read_text()
    assert "showSchoolAccessPolicyDialog" in settings
    assert "Acessos e funções" in settings


def test_finance_policy_is_enforced_by_navigation_and_backend():
    dependencies = Path("app/core/dependencies.py").read_text()
    navigation = Path("mobile/lib/core/router/router.dart").read_text()
    assert '_CONFIGURABLE_FINANCE = {"coordinator", "finance_officer", "secretary"}' in dependencies
    assert 'permissions.get(role)' in dependencies
    assert "roleCanAccessWithDefault" in navigation
    assert "final hasFinanceAccess" in navigation


def test_host_consumes_the_manifest_and_launches_without_sdk_types():
    models = Path("mobile/lib/core/models/finreg_models.dart").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "value['workspaces']" in models
    assert "value['capability_id']" in models
    assert "value['route']" in models
    assert "value['agt_channel']" in models
    assert "/finreg/workspace-launch/$capabilityId" in host
    assert "FinregWorkspaceLaunch.fromJson" in host
    assert "finreg_client_sdk" not in host
    assert "finreg_client_sdk" not in models


def test_finreg_has_one_entry_card_and_the_native_tabs_never_depend_on_it():
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "FinReg — facturação e conformidade" in host
    assert "_NativeSchoolFinanceTabs" in host
    # The workspace menu is gone: FinReg owns its own navigation. The only
    # tabs left are the school's own six areas.
    assert "widget.workspaces.length" not in host
    assert "_FinregWorkspaceMenu" not in host
    assert "DefaultTabController(" in host
    assert "length: 6" in host
    assert "FinregSchoolBillingModule(" not in host
    assert "IndexedStack" not in host
    assert "initialRoute:" not in host
    assert "onSessionExpired:" not in host
    assert "finregUrlLauncher(" in host
    assert "LaunchMode.externalApplication" in host
    assert "webOnlyWindowName: '_blank'" in host
    assert "if (_opening) return;" in host
    assert "'Abrir no FinReg'" in host
    # The card's failure branch must not replace the school tabs.
    assert "O FinReg está indisponível" in host
    assert "const Expanded(child: _NativeSchoolFinanceTabs())" in host


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
    assert "FinregEmbeddedModuleHost(" not in host
    assert "finregUrlLauncher(" in host
    assert "_CellenFinregAdapter" not in host


def test_vertical_host_does_not_reimplement_finreg_sales_state():
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "_CellenFinregAdapter" not in host
    assert "FinregSalesRepository" not in host
    assert "FinregEmbeddedModuleHost(" not in host
    assert "_open(" in host
    assert "_createWorkspaceLaunch" in host


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
    service = Path("app/services/finreg.py").read_text()
    assert '@router.post("/workspace-launch/{capability_id}")' in router
    assert 'getattr(user, "_roles_list", None)' in router
    assert "await HttpFinregAdapter().workspace_launch(" in router
    assert "external_user_id=str(user.id)" in router
    assert "roles=roles" in router
    assert "FINREG_CLIENT_SECRET" not in router
    assert "/delegated#" not in router
    assert "launch_workspace(" in service


def test_embedded_session_is_retired_and_launch_never_exposes_credentials():
    router = Path("app/routers/finreg.py").read_text()
    service = Path("app/services/finreg.py").read_text()
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert '@router.post("/embedded-session/{capability_id}")' not in router
    assert "exchange_delegated" not in service
    assert 'f"{settings.FINREG_BASE_URL}/auth/delegated/exchange"' not in service
    assert 'f"{settings.FINREG_BASE_URL}/auth/me"' not in service
    assert "FINREG_CLIENT_SECRET" not in host
    assert "finreg_client_sdk" not in host
    assert "finregUrlLauncher(" in host
    assert "localeTag: localeTag" not in host


def test_school_composition_uses_native_tabs_without_duplicate_modules():
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    assert "schoolBillingCapabilities" not in host
    assert "manifest.operationalWorkspaces" in host
    assert "finregEmbeddedModules" not in host
    assert "GuardiansListScreen()" in host
    assert "EmployeesListScreen()" in host
    # FinReg's workspace list is not mirrored as host panes: the school tabs
    # group their own workflows into hubs instead of a flat card grid.
    assert "_NativeSchoolFinanceTabs" in host
    assert "_SchoolBillingOperations" not in host
    hubs = Path(
        "mobile/lib/features/admin/finance/school_finance_hubs.dart"
    ).read_text()
    assert "DebtsHub()" in host
    assert "PaymentsHub()" in host
    assert "FinanceConfigHub()" in host
    assert "class DebtsHub" in hubs
    assert "context.push(item.route)" in hubs
    assert "context.go(" not in hubs
    assert "_SchoolContextualModule" not in host
    assert "_CompositionReadiness" in host
    assert "'/finreg/composition-readiness/$capabilityId'" in host
    assert ".label(" in host
    assert "Localizations.localeOf(context).languageCode" in host
    assert '@router.get("/composition-readiness/{capability_id}")' in Path(
        "app/routers/finreg.py"
    ).read_text()
    assert "mapping_policy" in Path("app/routers/finreg.py").read_text()


def test_school_employee_payroll_handoff_is_complete_and_reviewable():
    router = Path("app/routers/finreg.py").read_text()
    employee = Path("app/models/employee.py").read_text()
    form = Path(
        "mobile/lib/features/admin/employees/employee_form_screen.dart"
    ).read_text()
    listing = Path(
        "mobile/lib/features/admin/employees/employees_list_screen.dart"
    ).read_text()
    assert "tax_id" in employee
    for required in (
        '"tax_id": employee.tax_id',
        '"social_security_id": employee.social_security',
        '"base_salary": str(employee.salary)',
        '"hire_date": employee.hire_date.isoformat()',
        '"employees/{employee.id}"',
        'mapping.status = "review_required"',
    ):
        assert required in router
    assert "NIF *" in form
    assert "N.º de inscrição no INSS *" in form
    assert "Salário base" in form
    assert "Preparar processamento salarial" in listing
    host = Path(
        "mobile/lib/features/admin/finance/finreg_sales_host_screen.dart"
    ).read_text()
    # Payroll itself is FinReg's: the host only hands over the employee
    # record and leaves the mapping review to FinReg's payroll workspace.
    assert "EmployeesListScreen()" in host
    assert "_SchoolContextDefinition" not in host


def test_release_grants_catalog_and_employee_integration_scopes():
    deploy = Path("deploy/deploy_finreg_school_finance.sh").read_text()
    acceptance = Path("deploy/validate_cellen_finreg_release.sh").read_text()
    for scope in ("products:read", "products:write", "employees:write"):
        assert scope in deploy
        assert scope in acceptance


def test_all_ci_jobs_share_the_reviewed_finreg_package_pin():
    expected = Path(".github/finreg-packages-ref").read_text().strip()
    kit = Path(".github/finreg-kit-ref").read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{40}", expected)
    assert re.fullmatch(r"[0-9a-f]{40}", kit)

    flutter = Path(".github/workflows/flutter_build.yml").read_text()
    backend = Path(".github/workflows/backend_tests.yml").read_text()
    # The app no longer compiles FinReg packages; only the backend reads the
    # FinReg contract source and imports the connector kit.
    assert "ref: ${{ steps.finreg-ref.outputs.ref }}" not in flutter
    assert backend.count("ref: ${{ steps.finreg-ref.outputs.ref }}") == 1
    assert backend.count("ref: ${{ steps.kit-ref.outputs.ref }}") == 1
    assert 'pip install "$GITHUB_WORKSPACE/finreg-kit"' in backend

    # No build or test step may swallow a failure: a red build has to stay
    # red. The artifact uploads are the one exception — GitHub's artifact
    # quota is account-wide, and a full bucket is a billing condition, not a
    # broken build, so those two steps tolerate it (one per Android and iOS).
    def steps(workflow: str) -> list[dict]:
        return [
            step
            for job in yaml.safe_load(workflow)["jobs"].values()
            for step in job.get("steps", [])
        ]

    tolerant = [step for step in steps(flutter) if step.get("continue-on-error")]
    assert len(tolerant) == 2
    assert all(
        step.get("uses", "").startswith("actions/upload-artifact@")
        for step in tolerant
    )
    assert not any(step.get("continue-on-error") for step in steps(backend))


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
    navigation = Path("mobile/lib/core/router/router.dart").read_text()
    assert "initialCapabilityId: 'reporting'" in navigation
    assert "initialFinregRoute" not in navigation
    assert "FinregEmbeddedModuleHost(" not in host
    assert "finregUrlLauncher(" in host


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
    assert "Finreg retains the legacy Cellen Web CORS origin" in source
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


def test_cellen_only_release_uses_the_supported_health_endpoint():
    source = Path("deploy/release_cellen_from_vps.sh").read_text()

    assert "http://127.0.0.1:8001/health" in source
    assert "https://167.235.158.77.nip.io/health" in source
    assert "8001/ready" not in source
    assert "pg_dump -Fc" in source
    assert 'alembic" upgrade head' in source


def test_cellen_cutover_stages_the_pinned_kit_and_never_restarts_finreg():
    release = Path("deploy/release_cellen_from_vps.sh").read_text()
    combined = Path("deploy/deploy_finreg_school_finance.sh").read_text()
    pin = Path(".github/finreg-kit-ref").read_text().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", pin)
    for source in (release, combined):
        assert ".github/finreg-kit-ref" in source
        assert 'git -C "$KIT_REPO" archive "$KIT_PIN"' in source
        assert "--no-deps" in source
        assert "--force-reinstall" in source
    # The big-bang window must not touch the certified FinReg services.
    assert "--cellen-only" in combined
    assert "systemctl restart cellen-api" in combined


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
    models = Path("mobile/lib/core/models/finreg_models.dart").read_text()
    assert "value['agt_channel']" in models


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


# ─── fee automation boundary pins ────────────────────────────────────────────

def _source_block(source: str, start: str, end: str) -> str:
    begin = source.index(start)
    stop = source.index(end, begin + len(start))
    return source[begin:stop]


def test_fee_automation_runs_are_registered_for_finance_users():
    from app.main import app

    paths = {route.path for route in app.routes}
    assert "/api/v1/billing/runs/preview" in paths
    assert "/api/v1/billing/runs" in paths
    assert "/api/v1/billing/runs/{run_id}" in paths
    assert "/api/v1/billing/rebuild-plans" in paths

    root = Path(__file__).resolve().parents[1]
    router = (root / "app/routers/billing.py").read_text()
    preview = _source_block(
        router, '@router.post("/runs/preview")', '@router.post("/runs",'
    )
    assert "require_finance_access" in preview
    assert "preview_billing" in preview
    assert "dispatch_instruction" not in preview


def test_preview_computes_without_touching_the_fiscal_engine():
    root = Path(__file__).resolve().parents[1]
    service = (root / "app/services/billing_run.py").read_text()
    preview = _source_block(
        service, "async def preview_billing", "def _add_days"
    )
    # The preview is the "compute before generating" step: it may read the
    # integration mode, but it must never dispatch, enqueue or issue.
    assert "compose_students" in preview
    assert "dispatch_instruction" not in preview
    assert "enqueue_billing_instruction" not in preview
    assert "FakeFinregAdapter" not in preview


def test_only_the_internal_path_emits_local_fiscal_documents():
    root = Path(__file__).resolve().parents[1]
    service = (root / "app/services/billing_run.py").read_text()
    finreg_path = _source_block(
        service, "async def _run_finreg", "def _failure"
    )
    internal_path = _source_block(
        service, "async def _run_internal", "async def refresh_run_status"
    )
    assert "DocumentEmissionService" not in finreg_path
    assert "emit_invoice" not in finreg_path
    assert "enqueue_billing_instruction" in finreg_path
    assert "DocumentEmissionService" in internal_path
    assert "emit_invoice" in internal_path
    assert "issued_by=issued_by" in internal_path


def test_fee_automation_is_drained_by_the_scheduler_not_a_second_worker():
    root = Path(__file__).resolve().parents[1]
    scheduled = (root / "app/services/scheduled_tasks.py").read_text()
    assert "auto_generate_due" in scheduled
    assert "refresh_open_runs" in scheduled
    assert "apply_confirmed_plan_results" in scheduled

    router = (root / "app/routers/billing.py").read_text()
    assert "issued_by=_employee_id(user)" in router
    assert "issued_by=actor_id" not in router
