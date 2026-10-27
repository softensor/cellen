# -*- coding: utf-8 -*-
"""The owner console's principia-pay activation, end to end.

The proven Mwenenzo shape: the product token is pasted into the platform
shell, saved before it is trusted, live-verified against the rail, and only
its non-secret prefix ever comes back. A failed probe keeps the paste but
never arms it; the row's switch beats a leftover environment token.
"""
import uuid

import pytest
import pytest_asyncio
from sqlalchemy import select

from app.core.config import settings
from app.models.platform_settings import PlatformSettings
from app.models.principia_pay import PrincipiaPayConnection
from app.services import principia_pay
from app.services.principia_pay_client import PrincipiaPayError, RegisteredClient
from app.services.secret_box import decrypt_secret
from tests.conftest import auth

TOKEN = "ppt_live_token_value"


@pytest.fixture(autouse=True)
def _no_env_token(monkeypatch):
    """Every test starts from "no environment fallback" unless it says so."""
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", None)


@pytest_asyncio.fixture(autouse=True)
async def _clean_platform_settings(db):
    yield
    row = await db.get(PlatformSettings, 1)
    if row is not None:
        await db.delete(row)
        await db.commit()


async def _activate(client, padmin_token, monkeypatch, *, prefix="ppt_live_tok"):
    async def fake_verify(base_url, token, source_system):
        assert token == TOKEN
        return {
            "source_system": source_system,
            "token_prefix": prefix,
            "is_active": True,
        }

    monkeypatch.setattr(principia_pay, "verify_product_token", fake_verify)
    return await client.post(
        "/platform/payments/activate",
        json={"product_token": TOKEN},
        headers=auth(padmin_token),
    )


async def test_platform_status_requires_the_platform_admin(
    client, make_school, padmin_token
):
    _school, admin_token, _slug, _username = await make_school("pay")

    refused = await client.get(
        "/platform/payments/status", headers=auth(admin_token)
    )
    assert refused.status_code == 403

    allowed = await client.get(
        "/platform/payments/status", headers=auth(padmin_token)
    )
    assert allowed.status_code == 200
    body = allowed.json()
    assert body["configured"] is False
    assert body["enabled"] is False
    assert body["status"] == "not_configured"
    assert body["source_system"] == settings.PRINCIPIA_PAY_SOURCE_SYSTEM


async def test_activation_verifies_the_token_and_stores_it_encrypted(
    client, db, padmin_token, monkeypatch
):
    response = await _activate(client, padmin_token, monkeypatch)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["configured"] is True
    assert body["status"] == "connected"
    assert body["token_source"] == "admin"
    assert body["token_prefix"] == "ppt_live_tok"
    assert TOKEN not in response.text

    row = await db.get(PlatformSettings, 1)
    assert row.principia_pay_enabled is True
    assert row.principia_pay_token_ciphertext != TOKEN
    assert decrypt_secret(row.principia_pay_token_ciphertext) == TOKEN
    assert await principia_pay.resolve_product_token(db) == TOKEN


async def test_a_refused_token_is_kept_but_never_armed(
    client, db, padmin_token, monkeypatch
):
    async def fake_verify(base_url, token, source_system):
        raise PrincipiaPayError(401, "Invalid product token")

    monkeypatch.setattr(principia_pay, "verify_product_token", fake_verify)
    response = await client.post(
        "/platform/payments/activate",
        json={"product_token": TOKEN},
        headers=auth(padmin_token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["configured"] is False
    assert body["status"] == "attention"
    assert "401" in body["last_error"]
    assert TOKEN not in response.text

    row = await db.get(PlatformSettings, 1)
    # Saved before it was trusted: the paste survives the failed probe.
    assert decrypt_secret(row.principia_pay_token_ciphertext) == TOKEN
    # But it is not credentials: the rail stays exactly as armed as before.
    assert await principia_pay.resolve_product_token(db) == ""


async def test_deactivation_beats_a_leftover_environment_token(
    client, db, padmin_token, monkeypatch
):
    monkeypatch.setattr(settings, "PRINCIPIA_PAY_PRODUCT_TOKEN", "ppt_env_value")

    before = await client.get(
        "/platform/payments/status", headers=auth(padmin_token)
    )
    assert before.status_code == 200
    assert before.json()["configured"] is True
    assert before.json()["token_source"] == "environment"

    response = await client.post(
        "/platform/payments/deactivate", headers=auth(padmin_token)
    )
    assert response.status_code == 200
    body = response.json()
    assert body["configured"] is False
    assert body["status"] == "not_configured"
    assert await principia_pay.resolve_product_token(db) == ""


async def test_the_owner_registers_a_school_and_reads_the_rails_state(
    client, db, padmin_token, make_school, monkeypatch
):
    school, _admin_token, _slug, _username = await make_school("payreg")
    school_id = school["id"]

    async def fake_list(base_url, token, source_system):
        return []

    async def fake_register(
        base_url,
        product_token,
        source_system,
        *,
        external_client_id,
        name,
        callback_url=None,
        timeout_seconds=15.0,
    ):
        assert external_client_id == str(school_id)
        assert product_token == TOKEN
        return RegisteredClient(
            id="rail-client-1", api_key="pp_key_1", callback_secret="cb_secret"
        )

    monkeypatch.setattr(principia_pay, "list_product_clients", fake_list)
    monkeypatch.setattr(principia_pay, "register_client", fake_register)

    activated = await _activate(client, padmin_token, monkeypatch)
    assert activated.status_code == 200

    registered = await client.post(
        f"/platform/payments/schools/{school_id}/register",
        headers=auth(padmin_token),
    )
    assert registered.status_code == 200, registered.text
    body = registered.json()
    assert body["registered"] is True
    assert body["client_id"] == "rail-client-1"

    connection = (
        await db.execute(
            select(PrincipiaPayConnection).where(
                PrincipiaPayConnection.school_id == uuid.UUID(school_id)
            )
        )
    ).scalar_one_or_none()
    assert connection is not None
    assert connection.api_key_ciphertext != "pp_key_1"
    assert decrypt_secret(connection.api_key_ciphertext) == "pp_key_1"

    # Once the rail has the school, it reports what is still missing -- and
    # the owner's list repeats the rail's answer rather than guessing.
    async def fake_list_with_school(base_url, token, source_system):
        return [
            {
                "external_client_id": str(school_id),
                "onboarding_state": "needs_credentials",
                "providers": {},
            }
        ]

    monkeypatch.setattr(
        principia_pay, "list_product_clients", fake_list_with_school
    )
    listing = await client.get(
        "/platform/payments/schools", headers=auth(padmin_token)
    )
    assert listing.status_code == 200
    row = next(
        item for item in listing.json()["schools"] if item["id"] == str(school_id)
    )
    assert row["rail_state"] == "needs_credentials"
    assert row["registered"] is True
