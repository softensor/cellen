import hashlib
import uuid
from pathlib import Path
from typing import Any, Protocol

import httpx

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


class HttpFinregAdapter:
    def __init__(self):
        self._token: str | None = None

    async def _headers(self, actor_reference: str) -> dict[str, str]:
        secret = settings.FINREG_CLIENT_SECRET
        if not secret and settings.FINREG_CLIENT_SECRET_FILE:
            secret = Path(settings.FINREG_CLIENT_SECRET_FILE).read_text(encoding="utf-8").strip()
        if not settings.FINREG_CLIENT_ID or not secret:
            raise FinregError("not_configured", "Finreg credentials are not configured")
        verify = settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS
        async with httpx.AsyncClient(timeout=settings.FINREG_TIMEOUT_SECONDS, verify=verify) as client:
            response = await client.post(f"{settings.FINREG_BASE_URL}/integrations/oauth/token", json={
                "client_id": settings.FINREG_CLIENT_ID, "client_secret": secret,
                "actor_reference": actor_reference,
            })
        if response.status_code != 200:
            raise FinregError("authentication_failed", "Finreg rejected integration credentials")
        self._token = response.json()["access_token"]
        return {"Authorization": f"Bearer {self._token}"}

    async def capabilities(self, actor_reference: str) -> dict:
        headers = await self._headers(actor_reference)
        verify = settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS
        async with httpx.AsyncClient(timeout=settings.FINREG_TIMEOUT_SECONDS, verify=verify) as client:
            response = await client.get(f"{settings.FINREG_BASE_URL}/integrations/capabilities", headers=headers)
        return self._decode(response)

    async def exchange_delegated(self, code: str) -> dict:
        """Consume a one-time workspace grant without exposing host credentials."""
        verify = settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS
        try:
            async with httpx.AsyncClient(
                timeout=settings.FINREG_TIMEOUT_SECONDS,
                verify=verify,
            ) as client:
                token_response = await client.post(
                    f"{settings.FINREG_BASE_URL}/auth/delegated/exchange",
                    json={"code": code},
                )
                tokens = self._decode(token_response)
                user_response = await client.get(
                    f"{settings.FINREG_BASE_URL}/auth/me",
                    headers={
                        "Authorization": f"Bearer {tokens['access_token']}"
                    },
                )
        except httpx.TimeoutException as exc:
            raise FinregError(
                "timeout", "Finreg session exchange timed out", retryable=True
            ) from exc
        except httpx.TransportError as exc:
            raise FinregError(
                "unavailable", "Finreg is unavailable", retryable=True
            ) from exc
        return {"tokens": tokens, "user": self._decode(user_response)}

    async def execute(self, operation: str, payload: dict, *, idempotency_key: str, correlation_id: str, actor_reference: str) -> dict:
        return await self.request("POST", operation, payload, idempotency_key=idempotency_key,
                                  correlation_id=correlation_id, actor_reference=actor_reference)

    async def request(self, method: str, operation: str, payload: dict | None, *,
                      idempotency_key: str | None = None, correlation_id: str | None = None,
                      actor_reference: str) -> dict:
        headers = await self._headers(actor_reference)
        if idempotency_key:
            headers["Idempotency-Key"] = idempotency_key
        if correlation_id:
            headers["X-Correlation-ID"] = correlation_id
        try:
            verify = settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS
            async with httpx.AsyncClient(timeout=settings.FINREG_TIMEOUT_SECONDS, verify=verify) as client:
                response = await client.request(method, f"{settings.FINREG_BASE_URL}/integrations/{operation}", json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise FinregError("timeout_unknown", "Finreg request timed out", retryable=True, unknown_outcome=True) from exc
        except httpx.TransportError as exc:
            raise FinregError("unavailable", "Finreg is unavailable", retryable=True) from exc
        return self._decode(response)

    async def download(self, operation: str, *, actor_reference: str) -> bytes:
        headers = await self._headers(actor_reference)
        try:
            verify = settings.FINREG_TLS_CA_FILE or settings.FINREG_VERIFY_TLS
            async with httpx.AsyncClient(timeout=settings.FINREG_TIMEOUT_SECONDS, verify=verify) as client:
                response = await client.get(
                    f"{settings.FINREG_BASE_URL}/integrations/{operation}", headers=headers
                )
        except httpx.TimeoutException as exc:
            raise FinregError("timeout", "Finreg download timed out", retryable=True) from exc
        except httpx.TransportError as exc:
            raise FinregError("unavailable", "Finreg is unavailable", retryable=True) from exc
        if response.status_code >= 400:
            self._decode(response)
        return response.content

    @staticmethod
    def _decode(response: httpx.Response) -> dict:
        if response.status_code >= 400:
            retryable = response.status_code in {408, 429, 502, 503, 504}
            try: detail = response.json().get("detail", "Finreg request failed")
            except ValueError: detail = "Finreg request failed"
            raise FinregError(f"http_{response.status_code}", str(detail), retryable=retryable)
        return response.json()


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
