import asyncio
import hashlib
import uuid
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import parse_qsl, urlsplit

import httpx

from finreg_kit import (
    FinregClient,
    FinregConfig,
    FinregConfigurationError,
    FinregProtocolError,
    FinregRejected,
    FinregUnavailable,
)

from app.core.config import settings


class FinregError(RuntimeError):
    def __init__(self, code: str, detail: str, *, retryable: bool = False, unknown_outcome: bool = False):
        super().__init__(detail)
        self.code, self.detail = code, detail
        self.retryable, self.unknown_outcome = retryable, unknown_outcome


def billing_idempotency_key(school_id: uuid.UUID, contract_id: uuid.UUID, billing_period: str) -> str:
    canonical = f"cellen:school:{school_id}:contract:{contract_id}:period:{billing_period}"
    return "cellen-" + hashlib.sha256(canonical.encode()).hexdigest()


def school_context(*, instruction_id: uuid.UUID, school_id: uuid.UUID, pupil_id: uuid.UUID | None,
                   pupil_name: str | None, enrolment_id: uuid.UUID | None,
                   academic_year_id: uuid.UUID | None, academic_year_label: str | None,
                   billing_period: str) -> dict[str, Any]:
    return {
        "schema": "school/v1", "source_system": "cellen",
        "source_reference": str(instruction_id), "school_id": str(school_id),
        "pupil_id": str(pupil_id) if pupil_id else None, "pupil_name": pupil_name,
        "enrolment_id": str(enrolment_id) if enrolment_id else None,
        "academic_year_id": str(academic_year_id) if academic_year_id else None,
        "academic_year_label": academic_year_label, "billing_period": billing_period,
    }


class FinregAdapter(Protocol):
    async def capabilities(self, actor_reference: str) -> dict: ...
    async def execute(self, operation: str, payload: dict, *, idempotency_key: str, correlation_id: str, actor_reference: str) -> dict: ...


# FinReg mints one token per scope set and rate-limits token mints to 10 per
# client per 15 minutes, so the adapter keeps three fixed scope bundles instead
# of minting a token per call the way the previous hand-rolled client did.
# Every operation maps onto exactly one bundle; the union is the grant the
# deploy script gives the school's integration client.
_LAUNCH_SCOPES = frozenset({"workspace:launch"})
_READ_SCOPES = frozenset({
    "billing_plans:read",
    "capabilities:read",
    "customers:read",
    "documents:read",
    "events:read",
    "mappings:read",
    "products:read",
    "receipts:read",
    "receivables:read",
    "reports:read",
})
_WRITE_SCOPES = frozenset({
    "billing_plans:write",
    "customers:write",
    "documents:write",
    "employees:write",
    "mappings:write",
    "payments:write",
    "products:write",
    "receipts:write",
    "receivables:write",
})
_READ_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
# FinReg's dry-run preview is a POST that only needs documents:read.
_READ_POST_OPERATIONS = frozenset({"preview"})

_KIT_FAILURES = (
    FinregUnavailable,
    FinregRejected,
    FinregConfigurationError,
    FinregProtocolError,
)


def _translate_kit_error(error: Exception) -> FinregError:
    """Map finreg-kit's taxonomy onto Cellen's FinregError.

    A 5xx or timeout on a mutation arrives as FinregUnavailable with
    unknown_outcome=True: the request may have been applied, so a retry must
    resend the same idempotency key (the outbox already does).
    """
    if isinstance(error, FinregUnavailable):
        code = error.code or (
            f"http_{error.status_code}" if error.status_code else "unavailable"
        )
        return FinregError(
            code, str(error), retryable=True, unknown_outcome=error.unknown_outcome
        )
    if isinstance(error, FinregRejected):
        detail = error.detail if isinstance(error.detail, str) else str(error)
        code = error.code or (
            f"http_{error.status_code}" if error.status_code else "rejected"
        )
        return FinregError(code, detail, retryable=error.retryable)
    if isinstance(error, FinregConfigurationError):
        return FinregError("not_configured", str(error))
    assert isinstance(error, FinregProtocolError)
    return FinregError(
        "protocol_error",
        str(error),
        retryable=False,
        unknown_outcome=error.unknown_outcome,
    )


def _split_operation(operation: str) -> tuple[str, dict[str, str] | None]:
    """Split ``path?query`` so the kit sends the query as params.

    Callers spell operations without a leading slash (``customers/{id}``), and
    the kit concatenates ``api_prefix + path``, so the slash is added here.
    """
    parts = urlsplit(operation)
    path = parts.path if parts.path.startswith("/") else f"/{parts.path}"
    params = dict(parse_qsl(parts.query, keep_blank_values=True)) or None
    return path, params


def _scopes_for(method: str, path: str) -> frozenset[str]:
    normalized = path.strip("/")
    if normalized == "workspace-launches":
        return _LAUNCH_SCOPES
    if method.upper() in _READ_METHODS or normalized in _READ_POST_OPERATIONS:
        return _READ_SCOPES
    return _WRITE_SCOPES


def _secret_fingerprint(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()[:16]


def _credentials() -> tuple[str, str]:
    secret = settings.FINREG_CLIENT_SECRET
    if not secret and settings.FINREG_CLIENT_SECRET_FILE:
        secret = Path(settings.FINREG_CLIENT_SECRET_FILE).read_text(encoding="utf-8").strip()
    if not settings.FINREG_CLIENT_ID or not secret:
        raise FinregError("not_configured", "Finreg credentials are not configured")
    return settings.FINREG_CLIENT_ID, secret


def _tls_verify() -> bool | str:
    return settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS


# Routers construct a fresh adapter per request, so token reuse only works when
# the kit client outlives the request. One client per (origin, client, secret
# fingerprint, actor) keeps FinReg's per-user audit attribution without a token
# mint per call; a rotated secret invalidates its entry through the fingerprint.
_CLIENT_CACHE: dict[tuple[str, str, str, str], FinregClient] = {}
_CLIENT_CACHE_LIMIT = 512
_CLIENT_CACHE_LOCK = asyncio.Lock()
_SHARED_HTTP_CLIENT: httpx.AsyncClient | None = None


async def _shared_http_client() -> httpx.AsyncClient:
    global _SHARED_HTTP_CLIENT
    if _SHARED_HTTP_CLIENT is None or _SHARED_HTTP_CLIENT.is_closed:
        _SHARED_HTTP_CLIENT = httpx.AsyncClient(
            timeout=httpx.Timeout(settings.FINREG_TIMEOUT_SECONDS),
            verify=_tls_verify(),
        )
    return _SHARED_HTTP_CLIENT


class HttpFinregAdapter:
    def __init__(self, *, transport: httpx.AsyncBaseTransport | None = None,
                 http_client: httpx.AsyncClient | None = None):
        if transport is not None and http_client is not None:
            raise TypeError("pass either transport or http_client, not both")
        # Tests inject a transport to bypass the process-wide client cache.
        self._transport = transport
        self._http_client = http_client

    async def _client_for(self, actor_reference: str) -> FinregClient:
        client_id, secret = _credentials()
        config = FinregConfig(
            base_url=settings.finreg_origin,
            client_id=client_id,
            client_secret=secret,
            timeout=settings.FINREG_TIMEOUT_SECONDS,
            verify_tls=_tls_verify(),
            actor_reference=actor_reference,
        )
        if self._transport is not None:
            return FinregClient(config, transport=self._transport)
        if self._http_client is not None:
            return FinregClient(config, http_client=self._http_client)
        key = (config.base_url, client_id, _secret_fingerprint(secret), actor_reference)
        async with _CLIENT_CACHE_LOCK:
            client = _CLIENT_CACHE.get(key)
            if client is None:
                if len(_CLIENT_CACHE) >= _CLIENT_CACHE_LIMIT:
                    _CLIENT_CACHE.pop(next(iter(_CLIENT_CACHE)))
                client = FinregClient(config, http_client=await _shared_http_client())
                _CLIENT_CACHE[key] = client
            return client

    async def capabilities(self, actor_reference: str) -> dict:
        return await self.request(
            "GET", "capabilities", None, actor_reference=actor_reference
        )

    async def execute(self, operation: str, payload: dict, *, idempotency_key: str, correlation_id: str, actor_reference: str) -> dict:
        return await self.request("POST", operation, payload, idempotency_key=idempotency_key,
                                  correlation_id=correlation_id, actor_reference=actor_reference)

    async def request(self, method: str, operation: str, payload: dict | None, *,
                      idempotency_key: str | None = None, correlation_id: str | None = None,
                      actor_reference: str) -> dict:
        path, params = _split_operation(operation)
        client = await self._client_for(actor_reference)
        try:
            return await client.request(
                method,
                path,
                scopes=_scopes_for(method, path),
                json=payload,
                params=params,
                idempotency_key=idempotency_key,
                correlation_id=correlation_id,
            )
        except _KIT_FAILURES as exc:
            raise _translate_kit_error(exc) from exc

    async def download(self, operation: str, *, actor_reference: str) -> bytes:
        path, params = _split_operation(operation)
        client = await self._client_for(actor_reference)
        try:
            return await client.request_bytes(
                "GET", path, scopes=_READ_SCOPES, params=params
            )
        except _KIT_FAILURES as exc:
            raise _translate_kit_error(exc) from exc

    async def workspace_launch(self, *, capability_id: str, external_user_id: str,
                               display_name: str, roles: list[str],
                               web_base_url: str, actor_reference: str,
                               correlation_id: str | None = None) -> dict:
        """Mint a single-use delegated launch: ``{url, target_path, expires_in}``."""
        if not roles:
            raise FinregError("no_host_role", "Host role cannot access Finreg workspaces")
        client = await self._client_for(actor_reference)
        try:
            return await client.launch_workspace(
                web_base_url=web_base_url,
                capability_id=capability_id,
                external_user_id=external_user_id,
                display_name=display_name,
                roles=roles,
                correlation_id=correlation_id,
            )
        except _KIT_FAILURES as exc:
            raise _translate_kit_error(exc) from exc


class FakeFinregAdapter:
    """Deterministic failure-capable adapter for Cellen tests and local development."""
    def __init__(self, outcomes: dict[str, dict | FinregError] | None = None):
        self.outcomes = outcomes or {}
        self.results: dict[str, dict] = {}

    async def capabilities(self, actor_reference: str) -> dict:
        return {"api_version": "v1", "schema_version": "school/v1", "vertical": "school", "non_fiscal": True}

    async def execute(self, operation: str, payload: dict, *, idempotency_key: str, correlation_id: str, actor_reference: str) -> dict:
        if idempotency_key in self.results:
            return self.results[idempotency_key]
        outcome = self.outcomes.get(operation)
        if isinstance(outcome, FinregError):
            raise outcome
        result = outcome or {"id": str(uuid.uuid5(uuid.NAMESPACE_URL, idempotency_key)), "status": "confirmed"}
        self.results[idempotency_key] = result
        return result
