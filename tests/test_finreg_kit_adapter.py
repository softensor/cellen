"""Unit tests for Cellen's finreg-kit adapter.

These pin the adapter's own decisions: which scope bundle each call mints,
that a scoped token is reused per actor instead of minted per request (FinReg
caps token mints at 10 per client per 15 minutes), how kit errors translate
into Cellen's ``FinregError``, query-string splitting, byte downloads and the
delegated workspace launch.
"""

import httpx
import pytest

from finreg_kit import FakeFinreg

from app.core.config import settings
from app.services import finreg as finreg_service
from app.services.finreg import FinregError, HttpFinregAdapter


@pytest.fixture
def finreg(monkeypatch):
    fake = FakeFinreg(vertical="school")
    monkeypatch.setattr(settings, "FINREG_CLIENT_ID", fake.client_id)
    monkeypatch.setattr(settings, "FINREG_CLIENT_SECRET", fake.client_secret)
    monkeypatch.setattr(settings, "FINREG_CLIENT_SECRET_FILE", None)
    monkeypatch.setattr(settings, "FINREG_BASE_URL", fake.base_url)
    monkeypatch.setattr(settings, "FINREG_TLS_CA_FILE", None)
    monkeypatch.setattr(settings, "FINREG_VERIFY_TLS", True)
    monkeypatch.setattr(
        finreg_service,
        "_SHARED_HTTP_CLIENT",
        httpx.AsyncClient(transport=httpx.MockTransport(fake.handler)),
    )
    finreg_service._CLIENT_CACHE.clear()
    yield fake
    finreg_service._CLIENT_CACHE.clear()



def _scopes(sent: list[dict]) -> set[str]:
    merged: set[str] = set()
    for request in sent:
        merged.update(request.get("scope", "").split())
    return merged


def _write_customer(adapter: HttpFinregAdapter, external_id: str, actor: str):
    return adapter.request(
        "PUT",
        f"customers/{external_id}",
        {"customer": {"name": "Escola", "tax_id": "5000000000"}},
        idempotency_key=f"key-{external_id}",
        actor_reference=actor,
    )


@pytest.mark.asyncio
async def test_read_calls_mint_one_read_bundle_token_per_actor(finreg):
    adapter = HttpFinregAdapter()

    await adapter.capabilities("actor-a")
    await adapter.request(
        "GET",
        "events?after=0&limit=50",
        None,
        actor_reference="actor-a",
    )
    await adapter.capabilities("actor-a")

    assert len(finreg.token_requests) == 1
    assert _scopes(finreg.token_requests) == finreg_service._READ_SCOPES
    assert finreg.token_requests[0]["actor_reference"] == "actor-a"

    # A different actor is a different token on purpose: FinReg bakes the
    # actor into the JWT and audits per user.
    await adapter.capabilities("actor-b")
    assert len(finreg.token_requests) == 2
    assert finreg.token_requests[1]["actor_reference"] == "actor-b"


@pytest.mark.asyncio
async def test_mutations_mint_the_write_bundle_once(finreg):
    adapter = HttpFinregAdapter()

    await _write_customer(adapter, "ext-1", "actor-a")
    await _write_customer(adapter, "ext-2", "actor-a")

    assert len(finreg.token_requests) == 1
    assert _scopes(finreg.token_requests) == finreg_service._WRITE_SCOPES
    assert finreg.requests[-1].headers["Idempotency-Key"] == "key-ext-2"


def test_preview_is_a_read_even_though_it_posts():
    assert (
        finreg_service._scopes_for("POST", "preview")
        == finreg_service._READ_SCOPES
    )
    assert (
        finreg_service._scopes_for("POST", "workspace-launches")
        == finreg_service._LAUNCH_SCOPES
    )


@pytest.mark.asyncio
async def test_query_string_is_split_into_params(finreg):
    finreg.customers["ext-1"] = {"id": "c1", "external_id": "ext-1"}
    adapter = HttpFinregAdapter()

    statement = await adapter.request(
        "GET",
        "customers/ext-1/statement?date_from=2026-01-01&date_to=2026-01-31",
        None,
        actor_reference="actor-a",
    )

    assert statement["date_from"] == "2026-01-01"
    assert statement["date_to"] == "2026-01-31"
    assert finreg.requests[-1].url.params["date_from"] == "2026-01-01"


@pytest.mark.asyncio
async def test_download_returns_bytes_with_read_scopes(finreg):
    finreg.documents["doc-1"] = {"id": "d1", "external_id": "doc-1"}
    adapter = HttpFinregAdapter()

    payload = await adapter.download(
        "documents/doc-1/pdf", actor_reference="actor-a"
    )

    assert payload.startswith(b"%PDF-1.4")
    assert _scopes(finreg.token_requests) == finreg_service._READ_SCOPES


@pytest.mark.asyncio
async def test_workspace_launch_mints_a_delegated_url(finreg):
    adapter = HttpFinregAdapter()

    launch = await adapter.workspace_launch(
        capability_id="billing",
        external_user_id="user-1",
        display_name="Ana",
        roles=["finance_officer"],
        web_base_url="https://cellen.test",
        actor_reference="user-1",
    )

    assert launch["url"].startswith("https://cellen.test/#/delegated?code=")
    assert launch["target_path"] == "/billing"
    assert launch["expires_in"] == 60
    assert _scopes(finreg.token_requests) == finreg_service._LAUNCH_SCOPES
    assert finreg.launch_codes[next(iter(finreg.launch_codes))]["roles"] == [
        "finance_officer"
    ]
    # No host address, no return target — never a dangling one.
    assert finreg.launch_codes[next(iter(finreg.launch_codes))]["return_to"] is None


@pytest.mark.asyncio
async def test_workspace_launch_carries_the_host_return_target(finreg):
    adapter = HttpFinregAdapter()

    await adapter.workspace_launch(
        capability_id="billing",
        external_user_id="user-1",
        display_name="Ana",
        roles=["finance_officer"],
        web_base_url="https://cellen.test",
        actor_reference="user-1",
        return_to={"label": "Cellen", "url": "https://cellen.test"},
    )

    code = next(iter(finreg.launch_codes))
    assert finreg.launch_codes[code]["return_to"] == {
        "label": "Cellen",
        "url": "https://cellen.test",
    }


@pytest.mark.asyncio
async def test_workspace_launch_refuses_an_empty_host_role(finreg):
    adapter = HttpFinregAdapter()

    with pytest.raises(FinregError) as raised:
        await adapter.workspace_launch(
            capability_id="billing",
            external_user_id="user-1",
            display_name="Ana",
            roles=[],
            web_base_url="https://cellen.test",
            actor_reference="user-1",
        )

    assert raised.value.code == "no_host_role"
    assert finreg.requests == []


@pytest.mark.asyncio
async def test_unavailable_read_is_retryable_without_unknown_outcome(finreg):
    for _ in range(3):
        finreg.queue_failure(503, path_contains="/capabilities")
    adapter = HttpFinregAdapter()

    with pytest.raises(FinregError) as raised:
        await adapter.capabilities("actor-a")

    assert raised.value.code == "http_503"
    assert raised.value.retryable is True
    assert raised.value.unknown_outcome is False


@pytest.mark.asyncio
async def test_unavailable_mutation_reports_unknown_outcome(finreg):
    for _ in range(3):
        finreg.queue_failure(503, path_contains="/customers/ext-1")
    adapter = HttpFinregAdapter()

    with pytest.raises(FinregError) as raised:
        await _write_customer(adapter, "ext-1", "actor-a")

    assert raised.value.code == "http_503"
    assert raised.value.retryable is True
    assert raised.value.unknown_outcome is True


@pytest.mark.asyncio
async def test_rejected_call_keeps_detail_and_retryability(finreg):
    finreg.queue_failure(422, detail="customer.tax_id is invalid")
    adapter = HttpFinregAdapter()

    with pytest.raises(FinregError) as raised:
        await _write_customer(adapter, "ext-1", "actor-a")

    assert raised.value.code == "http_422"
    assert "customer.tax_id is invalid" in raised.value.detail
    assert raised.value.retryable is False
    assert raised.value.unknown_outcome is False

    # A 404 is version skew on the integration surface: retrying later is right.
    finreg.queue_failure(404, path_contains="/customers/ext-2")
    with pytest.raises(FinregError) as missing:
        await _write_customer(adapter, "ext-2", "actor-a")
    assert missing.value.code == "http_404"
    assert missing.value.retryable is True


@pytest.mark.asyncio
async def test_missing_credentials_report_not_configured(monkeypatch):
    monkeypatch.setattr(settings, "FINREG_CLIENT_ID", None)
    monkeypatch.setattr(settings, "FINREG_CLIENT_SECRET", None)
    monkeypatch.setattr(settings, "FINREG_CLIENT_SECRET_FILE", None)

    with pytest.raises(FinregError) as raised:
        await HttpFinregAdapter().capabilities("actor-a")

    assert raised.value.code == "not_configured"
    assert raised.value.retryable is False


def test_origin_normalizes_a_legacy_api_v1_base_url(monkeypatch):
    monkeypatch.setattr(
        settings, "FINREG_BASE_URL", "https://finreg.example/api/v1/"
    )
    assert settings.finreg_origin == "https://finreg.example"
    monkeypatch.setattr(settings, "FINREG_BASE_URL", "https://finreg.example")
    assert settings.finreg_origin == "https://finreg.example"
