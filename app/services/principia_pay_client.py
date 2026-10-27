"""Thin client for principia-pay's /v1/references API.

Canonical copy. Vendored (copied, not imported) into each calling product's
backend for now -- principia-pay has no package index and no other product
shares a git root with it. If this ever drifts out of sync across products,
that's the signal to move to a real git dependency instead of re-deriving
this file from memory.

Covers exactly the operations a calling product's backend needs: create a
reference, poll one, list them by caller_reference, verify the signature on
principia-pay's own outbound webhook (see principia-pay's
app/services/notify.py -- this file's `verify_webhook_signature` must stay
byte-for-byte compatible with that function's `_sign`), self-register an
end-tenant, and the two product-tier reads that let an owner console verify
its activation before trusting it.
"""

from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Any

import httpx


class PrincipiaPayError(Exception):
    """A non-2xx response from principia-pay, with its own detail message."""

    def __init__(self, status_code: int, detail: str):
        self.status_code = status_code
        self.detail = detail
        super().__init__(f"principia-pay {status_code}: {detail}")


@dataclass
class Reference:
    id: str
    provider: str
    caller_reference: str | None
    kind: str  # "reference" | "direct" | "redirect"
    entity: str | None
    reference: str | None
    redirect_url: str | None
    amount: Decimal
    currency: str
    status: str  # "pending" | "paid" | "failed" | "expired"
    expires_at: datetime | None
    paid_at: datetime | None
    created_at: datetime
    checkout_url: str | None = None  # only present on the create response

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Reference:
        return cls(
            id=data["id"],
            provider=data["provider"],
            caller_reference=data.get("caller_reference"),
            kind=data["kind"],
            entity=data.get("entity"),
            reference=data.get("reference"),
            redirect_url=data.get("redirect_url"),
            amount=Decimal(str(data["amount"])),
            currency=data["currency"],
            status=data["status"],
            expires_at=_parse_dt(data.get("expires_at")),
            paid_at=_parse_dt(data.get("paid_at")),
            created_at=_parse_dt(data["created_at"]),
            checkout_url=data.get("checkout_url"),
        )


@dataclass
class WebhookEvent:
    """One delivery of principia-pay's outbound notification.

    Fires on every status change, not only "paid" -- a caller must check
    `status` before treating this as a settlement.
    """

    id: str
    provider: str
    caller_reference: str | None
    external_session_id: str | None
    status: str
    amount: Decimal
    currency: str
    paid_at: datetime | None

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> WebhookEvent:
        return cls(
            id=data["id"],
            provider=data["provider"],
            caller_reference=data.get("caller_reference"),
            external_session_id=data.get("external_session_id"),
            status=data["status"],
            amount=Decimal(str(data["amount"])),
            currency=data["currency"],
            paid_at=_parse_dt(data.get("paid_at")),
        )


def _parse_dt(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def verify_webhook_signature(secret: str, body: bytes, signature: str | None) -> bool:
    """True iff `signature` is the HMAC-SHA256 hex digest of `body` under `secret`.

    Must match principia-pay's own `_sign` in app/services/notify.py exactly:
    same algorithm, same encoding, same hex representation. Constant-time
    compare -- this gates "mark this invoice paid", so a timing side-channel
    here is a real vulnerability, not a theoretical one.
    """
    if not signature:
        return False
    expected = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


class PrincipiaPayClient:
    """One client per calling product, authenticated with that product's own
    Client API key (issued once by `POST /v1/admin/clients`, shown only then).
    """

    #: Header principia-pay's notify.py signs its outbound webhook with.
    #: A calling product's own callback route must read this exact header.
    WEBHOOK_SIGNATURE_HEADER = "X-PrincipiaPay-Signature"

    def __init__(self, base_url: str, api_key: str, timeout_seconds: float = 15.0):
        self._base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._timeout = timeout_seconds

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._api_key}"}

    async def create_reference(
        self,
        *,
        provider: str,
        amount: Decimal,
        currency: str = "AOA",
        description: str | None = None,
        caller_reference: str | None = None,
        return_url: str | None = None,
        phone_number: str | None = None,
        expires_at: datetime | None = None,
    ) -> Reference:
        payload: dict[str, Any] = {
            "provider": provider,
            "amount": str(amount),
            "currency": currency,
        }
        if description is not None:
            payload["description"] = description
        if caller_reference is not None:
            payload["caller_reference"] = caller_reference
        if return_url is not None:
            payload["return_url"] = return_url
        if phone_number is not None:
            payload["phone_number"] = phone_number
        if expires_at is not None:
            payload["expires_at"] = expires_at.isoformat()

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self._base_url}/v1/references", json=payload, headers=self._headers(),
            )
        if response.status_code != 201:
            raise PrincipiaPayError(response.status_code, _detail(response))
        return Reference.from_json(response.json())

    async def get_reference(self, reference_id: str) -> Reference:
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.get(
                f"{self._base_url}/v1/references/{reference_id}", headers=self._headers(),
            )
        if response.status_code != 200:
            raise PrincipiaPayError(response.status_code, _detail(response))
        return Reference.from_json(response.json())

    async def list_references(
        self, *, caller_reference: str | None = None,
    ) -> list[Reference]:
        """Every reference this client created, newest first.

        `caller_reference` narrows it to the one a calling product is trying
        to recover after an ambiguous create (timeout, crash): the create is
        idempotent on exactly that key, so at most one row can come back for
        it -- and it is the only way to learn the rail's own id when the
        create response never made it back.
        """
        params = (
            {"caller_reference": caller_reference}
            if caller_reference is not None else None
        )
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.get(
                f"{self._base_url}/v1/references",
                params=params, headers=self._headers(),
            )
        if response.status_code != 200:
            raise PrincipiaPayError(response.status_code, _detail(response))
        return [Reference.from_json(item) for item in response.json()]


@dataclass
class RegisteredClient:
    """What self-registration returns -- api_key and callback_secret are
    shown exactly once, same discipline as everywhere else in principia-pay
    that mints a secret. The caller must store both itself; there is no
    GET that returns them again.
    """

    id: str
    api_key: str
    callback_secret: str | None


async def register_client(
    base_url: str,
    product_token: str,
    source_system: str,
    *,
    external_client_id: str,
    name: str,
    callback_url: str | None = None,
    timeout_seconds: float = 15.0,
) -> RegisteredClient:
    """Self-register one of this product's own end-tenants as a principia-pay
    Client -- a school for Cellen, a condominium for Mwenenzo. Each tenant
    gets its own Client, and therefore its own payment-provider account
    (inherited from this source_system's defaults, configured once by
    Principia) -- never a single shared Client for the whole product, which
    would settle every tenant's money into one pooled account.

    Authenticated with the product's own ProductToken (minted once by
    Principia via `POST /v1/admin/products/{source_system}/token`), not a
    Client API key -- this product doesn't have one of those yet, that's
    exactly what this call creates.
    """
    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        response = await client.post(
            f"{base_url.rstrip('/')}/v1/products/{source_system}/clients",
            json={
                "external_client_id": external_client_id,
                "name": name,
                "callback_url": callback_url,
            },
            headers={"Authorization": f"Bearer {product_token}"},
        )
    if response.status_code != 201:
        raise PrincipiaPayError(response.status_code, _detail(response))
    body = response.json()
    return RegisteredClient(id=body["id"], api_key=body["api_key"], callback_secret=body.get("callback_secret"))


async def verify_product_token(
    base_url: str,
    product_token: str,
    source_system: str,
    timeout_seconds: float = 10.0,
) -> dict:
    """Who this product token is, from the rail's own answer.

    ``GET /v1/products/{source_system}`` is the product tier's read-only
    identity call: it returns ``source_system``, the non-secret
    ``token_prefix`` and ``is_active``. The owner console calls it before
    trusting a pasted token, so a typo, a revoked token, or one minted for a
    different product cannot silently become the rail's credentials.
    """
    body = await _product_get(
        base_url,
        product_token,
        f"/v1/products/{source_system}",
        timeout_seconds=timeout_seconds,
    )
    return body if isinstance(body, dict) else {}


async def list_product_clients(
    base_url: str,
    product_token: str,
    source_system: str,
    timeout_seconds: float = 10.0,
) -> list[dict]:
    """Every end-tenant the rail holds for this product.

    Strictly read-only and secretless: each row carries the client's
    non-secret identifying prefix and the onboarding state the rail derived
    (credentials / verification / activation), never an API key or callback
    secret. This is what lets the owner console answer "is this school ready
    to take payments?" with the rail's truth rather than a local guess.
    """
    body = await _product_get(
        base_url,
        product_token,
        f"/v1/products/{source_system}/clients",
        timeout_seconds=timeout_seconds,
    )
    return list(body) if isinstance(body, list) else []


async def _product_get(
    base_url: str,
    product_token: str,
    path: str,
    *,
    timeout_seconds: float = 10.0,
) -> dict | list:
    url = f"{base_url.rstrip('/')}{path}"
    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        response = await client.get(
            url, headers={"Authorization": f"Bearer {product_token}"}
        )
    if response.status_code != 200:
        raise PrincipiaPayError(response.status_code, _detail(response))
    return response.json()


def _detail(response: httpx.Response) -> str:
    try:
        body = response.json()
        if isinstance(body, dict) and "detail" in body:
            return str(body["detail"])
    except ValueError:
        pass
    return response.text
