"""principia-pay reference payments, anchored to a fiscal document.

The rail only ever sees an opaque ``caller_reference``. The fiscal identity
stays in Cellen: a reference is opened against one open debt read from
whichever engine owns the school (a FinReg receivable or a local invoice),
and when the rail reports it paid, the settlement is posted back to that
same engine -- FinReg records the payment and issues the RC, an internal
school gets its normal signed receipt.

Two rules make retries safe:

* the create is idempotent on ``caller_reference`` (the rail keys on it), so
  a lost response is recovered by listing by that key -- or by creating
  again with the same key;
* the settlement is idempotent on ``celen-ref-{reference.id}`` as the
  FinReg payment external id and as the local intake idempotency key.

``status`` tracks *Cellen's* settlement state; ``rail_status`` mirrors the
rail. A reference the rail reports paid but whose settlement failed stays
``active`` with ``rail_status='paid'`` so the reconciler retries it.
"""

from __future__ import annotations

import json
import logging
import time
import uuid
from datetime import datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Optional

import httpx
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.finance import PaymentReference
from app.models.platform_settings import PlatformSettings
from app.models.principia_pay import PrincipiaPayConnection
from app.models.school import School
from app.services.billing_run import BillingError, FINREG_MODES
from app.services.debt_control import list_debts
from app.services.finance import PaymentIntakeService
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import integration_mode
from app.services.principia_pay_client import (
    PrincipiaPayClient,
    PrincipiaPayError,
    Reference,
    list_product_clients,
    register_client,
    verify_product_token,
    verify_webhook_signature,
)
from app.services.secret_box import decrypt_secret, encrypt_secret
from app.utils.agt import now_luanda

logger = logging.getLogger(__name__)

PROVIDER = "principia_pay"
_BAND = Decimal("0.01")


# ── Errors ────────────────────────────────────────────────────────────────


class RailUnavailable(BillingError):
    def __init__(self, detail: str):
        super().__init__("principia_pay_unavailable", detail, 502)


class RailRefused(BillingError):
    def __init__(self, detail: str):
        super().__init__("principia_pay_refused", detail, 409)


# ── Connection ────────────────────────────────────────────────────────────


def _base_url() -> str:
    return (settings.PRINCIPIA_PAY_BASE_URL or "").strip().rstrip("/")


def _env_product_token() -> str:
    return (settings.PRINCIPIA_PAY_PRODUCT_TOKEN or "").strip()


def _callback_url() -> Optional[str]:
    value = (settings.PRINCIPIA_PAY_CALLBACK_URL or "").strip()
    return value or None


async def get_platform_settings(db: AsyncSession) -> Optional[PlatformSettings]:
    """The owner console's singleton row, read-only (no implicit insert)."""
    return await db.get(PlatformSettings, 1)


async def ensure_platform_settings(db: AsyncSession) -> PlatformSettings:
    """Get-or-create the singleton without racing a concurrent first write."""
    row = await get_platform_settings(db)
    if row is not None:
        return row
    env_token = _env_product_token()
    row = PlatformSettings(
        id=1,
        principia_pay_enabled=bool(env_token),
        principia_pay_token_prefix=env_token[:12] or None,
        principia_pay_status="unchecked" if env_token else "not_configured",
    )
    db.add(row)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        row = await get_platform_settings(db)
        if row is None:
            raise
    return row


async def resolve_product_token(db: AsyncSession) -> str:
    """The product token in force right now.

    The owner console's row is authoritative once it exists: its switch can
    turn the rail off even while the environment still carries a token.
    Before the first activation there is no row, and the environment token
    keeps its old role as the startup fallback.

    A token the last probe rejected (``attention``) stays stored -- the
    operator's paste is never lost -- but it is not armed. That mirrors the
    proven Mwenenzo swap, which only happens on a verified ``connected``;
    pressing Activar again is the retry.
    """
    row = await get_platform_settings(db)
    if row is None:
        return _env_product_token()
    if not row.principia_pay_enabled:
        return ""
    if row.principia_pay_status == "attention":
        return ""
    if row.principia_pay_token_ciphertext:
        return decrypt_secret(row.principia_pay_token_ciphertext)
    return _env_product_token()


async def is_configured(db: AsyncSession) -> bool:
    return bool(_base_url() and await resolve_product_token(db))


async def _require_configuration(db: AsyncSession) -> tuple[str, str]:
    token = await resolve_product_token(db)
    if not _base_url() or not token:
        raise BillingError(
            "principia_pay_not_configured",
            "O serviço de pagamentos por referência não está configurado nesta instalação.",
            503,
        )
    return _base_url(), token


async def get_connection(
    db: AsyncSession, *, school_id: uuid.UUID
) -> Optional[PrincipiaPayConnection]:
    return (
        await db.execute(
            select(PrincipiaPayConnection).where(
                PrincipiaPayConnection.school_id == school_id
            )
        )
    ).scalar_one_or_none()


async def ensure_connection(
    db: AsyncSession, *, school_id: uuid.UUID
) -> PrincipiaPayConnection:
    """Return the school's rail client, self-registering on first use.

    Each school gets its own rail Client, so its money never pools with
    another school's. Registration happens once; the API key and callback
    secret are stored encrypted and never returned again.
    """
    existing = await get_connection(db, school_id=school_id)
    if (
        existing is not None
        and existing.status == "active"
        and existing.api_key_ciphertext
    ):
        return existing

    base_url, product_token = await _require_configuration(db)
    school = await db.get(School, school_id)
    if school is None:
        raise BillingError("school_not_found", "Escola não encontrada.", 404)

    try:
        registered = await register_client(
            base_url,
            product_token,
            settings.PRINCIPIA_PAY_SOURCE_SYSTEM,
            external_client_id=str(school_id),
            name=school.name,
            callback_url=_callback_url(),
            timeout_seconds=settings.FINREG_TIMEOUT_SECONDS,
        )
    except PrincipiaPayError as exc:
        if existing is not None:
            existing.status = "error"
            existing.last_error = f"{exc.status_code}: {exc.detail}"[:500]
            await db.commit()
        raise BillingError(
            "principia_pay_register_failed",
            f"A conta de pagamentos da escola não pôde ser criada: {exc.detail}",
            502,
        ) from exc
    except httpx.HTTPError as exc:
        if existing is not None:
            existing.status = "error"
            existing.last_error = str(exc)[:500]
            await db.commit()
        raise RailUnavailable(
            "O serviço de pagamentos não respondeu; tente novamente."
        ) from exc

    connection = existing or PrincipiaPayConnection(
        school_id=school_id, client_id=registered.id
    )
    connection.client_id = registered.id
    connection.api_key_ciphertext = encrypt_secret(registered.api_key)
    if registered.callback_secret:
        connection.callback_secret_ciphertext = encrypt_secret(
            registered.callback_secret
        )
    connection.status = "active"
    connection.last_error = None
    db.add(connection)
    try:
        await db.commit()
    except IntegrityError:
        # A concurrent request registered first; the unique school_id wins
        # and its stored keys are the live ones.
        await db.rollback()
        connection = await get_connection(db, school_id=school_id)
        if connection is None:
            raise
    await db.refresh(connection)
    return connection


def _client(
    connection: PrincipiaPayConnection, *, timeout_seconds: Optional[float] = None
) -> PrincipiaPayClient:
    return PrincipiaPayClient(
        _base_url(),
        decrypt_secret(connection.api_key_ciphertext),
        timeout_seconds=timeout_seconds or settings.FINREG_TIMEOUT_SECONDS,
    )


async def connection_status(db: AsyncSession, *, school_id: uuid.UUID) -> dict:
    connection = await get_connection(db, school_id=school_id)
    return {
        "configured": await is_configured(db),
        "registered": bool(connection and connection.status == "active"),
        "status": connection.status if connection else "unregistered",
        "client_id": connection.client_id if connection else None,
        "last_error": connection.last_error if connection else None,
        "provider": settings.PRINCIPIA_PAY_PROVIDER,
    }


async def probe_connection(db: AsyncSession, *, school_id: uuid.UUID) -> dict:
    """Ask the rail, right now, whether this school can create a reference.

    ``connection_status`` is a database read: it says the keys were stored,
    not that they still work. The card that shows a green tick must be able
    to earn it, or a revoked key or a rail outage keeps looking healthy while
    every reference fails. The probe is a cheap empty listing keyed by a
    one-off caller reference, so it validates auth and reachability without
    touching any money.
    """
    status = await connection_status(db, school_id=school_id)
    result = {
        **status,
        "reachable": False,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "latency_ms": None,
        "probe_error": None,
    }
    if not status["configured"]:
        result["probe_error"] = (
            "O serviço de pagamentos não está configurado nesta instalação."
        )
        return result
    connection = await get_connection(db, school_id=school_id)
    if (
        connection is None
        or connection.status != "active"
        or not connection.api_key_ciphertext
    ):
        result["probe_error"] = (
            "A escola ainda não está registada no serviço de pagamentos."
        )
        return result

    client = _client(
        connection,
        # Stay inside the app's own receive timeout so a slow rail is
        # reported as a failed probe, not as a frozen screen.
        timeout_seconds=min(settings.FINREG_TIMEOUT_SECONDS, 6.0),
    )
    started = time.monotonic()
    try:
        await client.list_references(
            caller_reference=f"cellen-probe-{uuid.uuid4().hex}"
        )
    except PrincipiaPayError as exc:
        _record_error(connection, exc)
        if exc.status_code in (401, 403):
            # The stored key is no longer accepted. Keep the row (its keys
            # are still the only copy) but stop advertising it as active.
            connection.status = "error"
        await db.commit()
        result.update(
            status=connection.status,
            registered=connection.status == "active",
            last_error=connection.last_error,
            probe_error=f"principia-pay {exc.status_code}: {exc.detail}",
            latency_ms=round((time.monotonic() - started) * 1000),
        )
        return result
    except (
        httpx.HTTPError,
        KeyError,
        TypeError,
        ValueError,
        InvalidOperation,
    ) as exc:
        _record_error(connection, exc)
        await db.commit()
        result.update(
            last_error=connection.last_error,
            probe_error=str(exc) or exc.__class__.__name__,
            latency_ms=round((time.monotonic() - started) * 1000),
        )
        return result

    if connection.last_error:
        connection.last_error = None
    await db.commit()
    result.update(
        reachable=True,
        last_error=None,
        latency_ms=round((time.monotonic() - started) * 1000),
    )
    return result


# ── Owner-console activation ─────────────────────────────────────────────


def _platform_status_dict(
    row: Optional[PlatformSettings], *, configured: bool
) -> dict:
    env_token = _env_product_token()
    if row is None:
        enabled = bool(env_token)
        status = "unchecked" if env_token else "not_configured"
        prefix = env_token[:12] or None
        last_error = None
        last_checked = None
        source = "environment" if env_token else None
    else:
        enabled = row.principia_pay_enabled
        status = row.principia_pay_status
        prefix = row.principia_pay_token_prefix
        last_error = row.principia_pay_last_error
        last_checked = row.principia_pay_last_checked_at
        source = None
        if enabled and row.principia_pay_token_ciphertext:
            source = "admin"
        elif enabled and env_token:
            source = "environment"
    return {
        "configured": configured,
        "enabled": enabled,
        "status": status,
        "token_prefix": prefix,
        "token_source": source,
        "provider": settings.PRINCIPIA_PAY_PROVIDER,
        "source_system": settings.PRINCIPIA_PAY_SOURCE_SYSTEM,
        "base_url": _base_url(),
        "last_error": last_error,
        "last_checked_at": last_checked,
    }


async def platform_status(db: AsyncSession) -> dict:
    row = await get_platform_settings(db)
    return _platform_status_dict(row, configured=await is_configured(db))


async def activate_platform_token(db: AsyncSession, product_token: str) -> dict:
    """Save the pasted product token, then ask the rail who it is.

    Save-then-probe, the proven Mwenenzo shape: the paste is committed
    before the network call, so an unreachable rail -- or one that refuses
    the token -- costs the operator nothing but pressing the button again.
    A token is armed only after a verified ``connected``; a refused token
    stays stored with ``attention`` and the reason beside it.
    """
    row = await ensure_platform_settings(db)
    token = product_token.strip()
    row.principia_pay_enabled = True
    row.principia_pay_token_ciphertext = encrypt_secret(token)
    row.principia_pay_token_prefix = token[:12]
    row.principia_pay_status = "unchecked"
    row.principia_pay_last_error = None
    await db.commit()
    await db.refresh(row)

    base_url = _base_url()
    try:
        identity = await verify_product_token(
            base_url, token, settings.PRINCIPIA_PAY_SOURCE_SYSTEM
        )
    except PrincipiaPayError as exc:
        row.principia_pay_status = "attention"
        row.principia_pay_last_error = f"{exc.status_code}: {exc.detail}"[:1000]
    except httpx.HTTPError as exc:
        row.principia_pay_status = "attention"
        row.principia_pay_last_error = str(exc)[:1000]
    else:
        if identity.get("is_active") is False:
            row.principia_pay_status = "attention"
            row.principia_pay_last_error = (
                "O token existe no principia-pay mas está inactivo."
            )
        else:
            row.principia_pay_status = "connected"
            row.principia_pay_last_error = None
            row.principia_pay_last_checked_at = datetime.now(timezone.utc)
            # The rail's answer is authoritative for the prefix: it is the
            # first twelve characters of the token the rail actually matched.
            row.principia_pay_token_prefix = (
                identity.get("token_prefix") or row.principia_pay_token_prefix
            )
    await db.commit()
    await db.refresh(row)
    return _platform_status_dict(row, configured=await is_configured(db))


async def deactivate_platform_token(db: AsyncSession) -> dict:
    """Turn the rail off in this installation, clearing the stored token.

    The row's switch wins over the environment fallback, so this is a real
    off switch even when ``PRINCIPIA_PAY_PRODUCT_TOKEN`` is still set in
    ``.env``. Activating again is all it takes to come back.
    """
    row = await ensure_platform_settings(db)
    row.principia_pay_enabled = False
    row.principia_pay_token_ciphertext = None
    row.principia_pay_token_prefix = None
    row.principia_pay_status = "not_configured"
    row.principia_pay_last_error = None
    row.principia_pay_last_checked_at = None
    await db.commit()
    await db.refresh(row)
    return _platform_status_dict(row, configured=False)


async def platform_schools(db: AsyncSession) -> dict:
    """Every school, with the rail's own onboarding answer where available.

    A local connection row alone cannot say whether a payment will work: the
    rail may still be waiting for the school's provider credentials or its
    verification. One product-tier read maps the rail's per-client state onto
    each school; a rail that cannot answer degrades every row to
    ``unreachable`` rather than guessing.
    """
    schools = (
        await db.execute(select(School).order_by(School.name, School.id))
    ).scalars().all()
    connections = {
        row.school_id: row
        for row in (
            await db.execute(select(PrincipiaPayConnection))
        ).scalars().all()
    }
    configured = await is_configured(db)
    rail_by_external: dict[str, dict] = {}
    rail_error: Optional[str] = None
    if configured:
        try:
            rail_by_external = {
                str(row.get("external_client_id")): row
                for row in await list_product_clients(
                    _base_url(),
                    await resolve_product_token(db),
                    settings.PRINCIPIA_PAY_SOURCE_SYSTEM,
                )
            }
        except PrincipiaPayError as exc:
            rail_error = f"{exc.status_code}: {exc.detail}"[:500]
        except httpx.HTTPError as exc:
            rail_error = str(exc)[:500]

    rows = []
    for school in schools:
        connection = connections.get(school.id)
        rail_row = rail_by_external.get(str(school.id))
        if not configured:
            state = "platform_off"
        elif rail_error is not None:
            state = "unreachable"
        elif connection is not None and rail_row is not None:
            state = str(rail_row.get("onboarding_state") or "unknown")
        elif connection is not None:
            state = "missing_on_rail"
        elif rail_row is not None:
            state = "unlinked"
        else:
            state = "unregistered"
        rows.append(
            {
                "id": school.id,
                "name": school.name,
                "slug": school.slug,
                "is_active": bool(school.is_active),
                "registered": bool(connection and connection.status == "active"),
                "client_id": connection.client_id if connection else None,
                "last_error": connection.last_error if connection else None,
                "rail_state": state,
                "providers": (
                    dict(rail_row.get("providers") or {}) if rail_row else {}
                ),
            }
        )
    return {"configured": configured, "rail_error": rail_error, "schools": rows}


async def register_school(db: AsyncSession, *, school_id: uuid.UUID) -> dict:
    """Ensure this school exists on the rail with a key this system holds.

    The rail is asked first, so the button cannot create two clients: an
    existing pair is a no-op, a local key whose rail client vanished is
    replaced, and a rail client this system has no key for is refused rather
    than shadowed -- its key was shown once and cannot be recovered.
    """
    school = await db.get(School, school_id)
    if school is None:
        raise BillingError("school_not_found", "Escola não encontrada.", 404)
    base_url, product_token = await _require_configuration(db)
    try:
        rail_ids = {
            str(row.get("external_client_id"))
            for row in await list_product_clients(
                base_url, product_token, settings.PRINCIPIA_PAY_SOURCE_SYSTEM
            )
        }
    except PrincipiaPayError as exc:
        raise RailRefused(f"principia-pay {exc.status_code}: {exc.detail}") from exc
    except httpx.HTTPError as exc:
        raise RailUnavailable(f"principia-pay unreachable: {exc}") from exc

    connection = await get_connection(db, school_id=school_id)
    external_id = str(school_id)
    if connection is not None and external_id in rail_ids:
        return await connection_status(db, school_id=school_id)
    if connection is not None:
        # The rail no longer has this client, so the stored key is dead.
        await db.delete(connection)
        await db.commit()
    elif external_id in rail_ids:
        raise BillingError(
            "principia_pay_key_missing",
            "Esta escola já existe no principia-pay, mas a chave do cliente "
            "não está neste sistema. É preciso repor a chave no principia-pay "
            "antes de voltar a ligar a escola.",
            409,
        )
    await ensure_connection(db, school_id=school_id)
    return await connection_status(db, school_id=school_id)


# ── Reference creation ────────────────────────────────────────────────────


def _money(value) -> Decimal:
    return Decimal(str(value or 0)).quantize(_BAND, rounding=ROUND_HALF_UP)


def _description_from(number: Optional[str]) -> str:
    # AppyPay caps a charge description at 50 characters.
    return f"Pagamento {number}".strip()[:50]


async def _open_debt_row(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    document_id: str,
    guardian_id: Optional[uuid.UUID],
    allowed_child_ids: Optional[set[str]] = None,
    adapter=None,
) -> dict:
    debts = await list_debts(db, school_id=school_id, adapter=adapter)
    for row in debts["rows"]:
        if str(row.get("document_id")) != str(document_id):
            continue
        owner = row.get("guardian_id")
        is_owner = guardian_id is None or str(owner) == str(guardian_id)
        # A second parent may pay for a child they are linked to, even
        # though the school bills the family through one payer.
        family_child = str(row.get("student_id") or "") in (
            allowed_child_ids or set()
        )
        if not is_owner and not family_child:
            raise BillingError(
                "debt_not_found", "Dívida não encontrada para este encarregado.", 404
            )
        return row
    raise BillingError(
        "debt_not_found", "Dívida não encontrada ou já liquidada.", 404
    )


async def _active_reference(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    document_id: uuid.UUID,
    source: str,
) -> Optional[PaymentReference]:
    now = now_luanda()
    column = (
        PaymentReference.invoice_id
        if source == "internal"
        else PaymentReference.finreg_document_id
    )
    return (
        await db.execute(
            select(PaymentReference)
            .where(
                PaymentReference.school_id == school_id,
                column == document_id,
                PaymentReference.provider == PROVIDER,
                PaymentReference.status.in_(("creating", "active")),
                or_(
                    PaymentReference.expires_at.is_(None),
                    PaymentReference.expires_at > now,
                ),
            )
            .order_by(PaymentReference.created_at.desc())
        )
    ).scalars().first()


async def create_reference(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    document_id: str,
    amount: Optional[Decimal] = None,
    guardian_id: Optional[uuid.UUID] = None,
    return_url: Optional[str] = None,
    requested_by: Optional[uuid.UUID] = None,
    allowed_child_ids: Optional[set[str]] = None,
    adapter=None,
) -> PaymentReference:
    """Open (or return) a rail reference against one open debt.

    A browser cannot tell an unhandled 500 from a dead network: both surface
    as a generic "sem ligação ao servidor". This boundary turns any
    unexpected failure into a logged, CORS-bearing 502 so the school sees
    what actually happened and the server keeps the traceback.
    """
    try:
        return await _create_reference(
            db,
            school_id=school_id,
            document_id=document_id,
            amount=amount,
            guardian_id=guardian_id,
            return_url=return_url,
            requested_by=requested_by,
            allowed_child_ids=allowed_child_ids,
            adapter=adapter,
        )
    except BillingError:
        raise
    except Exception as exc:
        logger.exception(
            "principia-pay reference create failed (school=%s document=%s)",
            school_id,
            document_id,
        )
        raise RailUnavailable(
            "Não foi possível preparar a referência de pagamento. "
            "Tente novamente; se persistir, verifique a ligação da escola "
            "ao serviço de pagamentos."
        ) from exc


async def _create_reference(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    document_id: str,
    amount: Optional[Decimal] = None,
    guardian_id: Optional[uuid.UUID] = None,
    return_url: Optional[str] = None,
    requested_by: Optional[uuid.UUID] = None,
    allowed_child_ids: Optional[set[str]] = None,
    adapter=None,
) -> PaymentReference:
    row = await _open_debt_row(
        db,
        school_id=school_id,
        document_id=document_id,
        guardian_id=guardian_id,
        allowed_child_ids=allowed_child_ids,
        adapter=adapter,
    )
    source = row.get("source") or "finreg"
    try:
        doc_uuid = uuid.UUID(str(row["document_id"]))
    except (KeyError, ValueError) as exc:
        raise BillingError(
            "debt_not_found", "Identificador de dívida inválido.", 404
        ) from exc

    existing = await _active_reference(
        db, school_id=school_id, document_id=doc_uuid, source=source
    )
    if existing is not None:
        return existing
    if source == "internal":
        # The manual flow already enforces one active reference per invoice;
        # the rail path must not open a second one behind its back.
        other = (
            await db.execute(
                select(PaymentReference).where(
                    PaymentReference.invoice_id == doc_uuid,
                    PaymentReference.status == "active",
                    PaymentReference.provider != PROVIDER,
                )
            )
        ).scalars().first()
        if other is not None:
            raise BillingError(
                "reference_exists",
                "Já existe uma referência ativa para esta factura.",
                409,
            )

    outstanding = _money(row.get("outstanding"))
    if outstanding <= 0:
        raise BillingError("debt_settled", "Esta dívida já está liquidada.", 409)
    payable = _money(amount) if amount is not None else outstanding
    if payable <= 0:
        raise BillingError(
            "invalid_amount", "O valor da referência deve ser positivo.", 422
        )
    if payable > outstanding:
        raise BillingError(
            "amount_exceeds_outstanding",
            "O valor excede o saldo em dívida.",
            422,
        )

    owner = row.get("guardian_id")
    if not owner:
        raise BillingError(
            "debt_missing_guardian",
            "A dívida não tem encarregado de cobrança associado.",
            409,
        )
    try:
        billing_guardian_id = uuid.UUID(str(owner))
    except (TypeError, ValueError) as exc:
        logger.warning(
            "debt %s carries a non-UUID guardian id %r; refusing a rail reference",
            document_id,
            owner,
        )
        raise BillingError(
            "debt_missing_guardian",
            "A dívida tem um encarregado de cobrança inválido. "
            "Corrija a ligação do aluno ao encarregado na ficha do aluno.",
            409,
        ) from exc

    ref_id = uuid.uuid4()
    reference = PaymentReference(
        id=ref_id,
        school_id=school_id,
        invoice_id=doc_uuid if source == "internal" else None,
        billing_guardian_id=billing_guardian_id,
        entity="",
        reference="",
        amount=payable,
        status="creating",
        provider=PROVIDER,
        caller_reference=f"cellen-ref-{ref_id}",
        finreg_document_id=doc_uuid if source == "finreg" else None,
        finreg_document_number=row.get("document_number"),
        finreg_document_external_id=row.get("document_external_id"),
        created_by=requested_by,
    )
    db.add(reference)
    # Persist before the network call: the caller reference is the recovery
    # key a crashed or timed-out create is reconciled by.
    await db.commit()

    try:
        connection = await ensure_connection(db, school_id=school_id)
    except BillingError:
        # The create never reached the rail, so the local placeholder must
        # not shadow the next attempt: cancel it before surfacing the real
        # error (not configured, registration refused, rail down).
        reference.status = "cancelled"
        reference.rail_status = "not_sent"
        await db.commit()
        raise
    client = _client(connection)
    try:
        rail = await client.create_reference(
            provider=settings.PRINCIPIA_PAY_PROVIDER,
            amount=payable,
            currency=row.get("currency_code") or "AOA",
            description=_description_from(row.get("document_number")),
            caller_reference=reference.caller_reference,
            return_url=return_url,
        )
    except PrincipiaPayError as exc:
        if 400 <= exc.status_code < 500:
            reference.status = "cancelled"
            reference.rail_status = "refused"
            await db.commit()
            raise RailRefused(
                f"O pedido de referência foi recusado: {exc.detail}"
            ) from exc
        reference.rail_status = "create_unknown"
        await db.commit()
        raise RailUnavailable(
            "O serviço de pagamentos não confirmou a referência; "
            "será reconciliada automaticamente."
        ) from exc
    except httpx.HTTPError as exc:
        reference.rail_status = "create_unknown"
        await db.commit()
        # The create is idempotent on caller_reference: if it did land, the
        # listing finds it and the reference is usable immediately.
        rail = await _recover_create(client, reference)
        if rail is None:
            raise RailUnavailable(
                "O serviço de pagamentos não confirmou a referência; "
                "será reconciliada automaticamente."
            ) from exc
    except (KeyError, TypeError, ValueError, InvalidOperation) as exc:
        # The rail answered 201, but in a shape this client cannot read.
        # The create may well have landed: keep it recoverable and let the
        # school retry without opening a second reference.
        reference.rail_status = "create_unknown"
        await db.commit()
        logger.exception(
            "principia-pay returned an unreadable reference for %s",
            reference.caller_reference,
        )
        raise RailUnavailable(
            "O serviço de pagamentos respondeu num formato inesperado; "
            "a referência será reconciliada automaticamente."
        ) from exc

    _apply_rail(reference, rail)
    await db.commit()
    await db.refresh(reference)
    return reference


async def _recover_create(
    client: PrincipiaPayClient, reference: PaymentReference
) -> Optional[Reference]:
    try:
        matches = await client.list_references(
            caller_reference=reference.caller_reference
        )
    except (
        PrincipiaPayError,
        httpx.HTTPError,
        KeyError,
        TypeError,
        ValueError,
        InvalidOperation,
    ):
        return None
    return matches[0] if matches else None


def _apply_rail(reference: PaymentReference, rail: Reference) -> None:
    reference.external_id = rail.id
    reference.entity = rail.entity or reference.entity
    reference.reference = rail.reference or reference.reference
    reference.checkout_url = (
        rail.checkout_url or rail.redirect_url or reference.checkout_url
    )
    reference.rail_status = rail.status
    if rail.expires_at is not None:
        reference.expires_at = rail.expires_at
    if rail.status == "paid":
        reference.paid_at = reference.paid_at or rail.paid_at
        reference.paid_amount = _money(rail.amount)
    elif rail.status == "expired":
        reference.status = "expired"
    elif rail.status == "failed":
        reference.status = "cancelled"
    elif reference.status == "creating":
        # The rail accepted the create and is waiting for the payer. Settle
        # the local state here, not in the caller, so every path that gets a
        # rail answer (create, recovery, poll, webhook) lands in ``active``.
        reference.status = "active"


# ── Querying and refreshing ───────────────────────────────────────────────


async def list_references(
    db: AsyncSession,
    *,
    school_id: uuid.UUID,
    status_filter: Optional[str] = None,
    guardian_id: Optional[uuid.UUID] = None,
    limit: int = 100,
) -> list[PaymentReference]:
    query = select(PaymentReference).where(
        PaymentReference.school_id == school_id,
        PaymentReference.provider == PROVIDER,
    )
    if status_filter:
        query = query.where(PaymentReference.status == status_filter)
    if guardian_id is not None:
        query = query.where(PaymentReference.billing_guardian_id == guardian_id)
    rows = (
        await db.execute(
            query.order_by(PaymentReference.created_at.desc()).limit(
                min(max(limit, 1), 200)
            )
        )
    ).scalars().all()
    return list(rows)


async def _fetch_rail(
    client: PrincipiaPayClient, reference: PaymentReference
) -> Reference:
    if reference.external_id:
        return await client.get_reference(reference.external_id)
    if reference.caller_reference:
        recovered = await _recover_create(client, reference)
        if recovered is not None:
            return recovered
        # The create never reached the rail; repeating it under the same
        # caller reference is exactly what the rail's idempotency keys on.
        return await client.create_reference(
            provider=settings.PRINCIPIA_PAY_PROVIDER,
            amount=_money(reference.amount),
            description=_description_from(reference.finreg_document_number),
            caller_reference=reference.caller_reference,
        )
    raise RailUnavailable(
        "A referência não tem identificador no serviço de pagamentos."
    )


async def refresh_reference(
    db: AsyncSession, *, reference: PaymentReference, adapter=None
) -> PaymentReference:
    """Poll the rail; settle if it reports paid. Idempotent by design."""
    if reference.provider != PROVIDER:
        raise BillingError(
            "not_rail_reference",
            "Esta referência não pertence ao serviço de pagamentos.",
            409,
        )
    connection = await get_connection(db, school_id=reference.school_id)
    if connection is None or connection.status != "active":
        raise BillingError(
            "principia_pay_not_registered",
            "O serviço de pagamentos ainda não está ligado para esta escola.",
            409,
        )
    client = _client(connection)
    try:
        rail = await _fetch_rail(client, reference)
    except PrincipiaPayError as exc:
        _record_error(connection, exc)
        await db.commit()
        raise RailUnavailable(
            f"O serviço de pagamentos devolveu um erro: {exc.detail}"
        ) from exc
    except httpx.HTTPError as exc:
        _record_error(connection, exc)
        await db.commit()
        raise RailUnavailable(
            "O serviço de pagamentos não respondeu; tente novamente."
        ) from exc
    except (KeyError, TypeError, ValueError, InvalidOperation) as exc:
        _record_error(connection, exc)
        await db.commit()
        logger.exception(
            "principia-pay returned an unreadable reference while refreshing %s",
            reference.id,
        )
        raise RailUnavailable(
            "O serviço de pagamentos respondeu num formato inesperado; "
            "tente novamente."
        ) from exc

    reference.last_checked_at = now_luanda()
    if connection.last_error:
        connection.last_error = None
    _apply_rail(reference, rail)
    # Commit the rail state before the settlement call: the settlement is
    # idempotent, and this way a crash between the two leaves a reference
    # the reconciler can retry, never a silently lost payment.
    await db.commit()

    if rail.status == "paid" and reference.status != "paid":
        await _settle_paid(db, reference, adapter=adapter)
    await db.refresh(reference)
    return reference


def _record_error(connection: PrincipiaPayConnection, exc: Exception) -> None:
    if isinstance(exc, PrincipiaPayError):
        message = f"{exc.status_code}: {exc.detail}"
    else:
        message = str(exc)
    connection.last_error = message[:500]


async def _settle_paid(
    db: AsyncSession, reference: PaymentReference, *, adapter=None
) -> None:
    amount = _money(reference.paid_amount or reference.amount)
    if amount <= 0:
        raise BillingError(
            "principia_pay_zero_amount",
            "O serviço de pagamentos confirmou um valor inválido.",
            502,
        )
    paid_at = reference.paid_at or now_luanda()
    if not isinstance(paid_at, datetime):
        # A rail payload may carry a date-only value; normalise once so both
        # settlement paths can safely ask for the calendar day.
        paid_at = datetime.combine(paid_at, datetime.min.time())
    if reference.finreg_document_id is not None:
        await _settle_finreg(db, reference, amount=amount, paid_at=paid_at, adapter=adapter)
        return
    await _settle_internal(db, reference, amount=amount, paid_at=paid_at)


async def _settle_finreg(
    db: AsyncSession,
    reference: PaymentReference,
    *,
    amount: Decimal,
    paid_at: datetime,
    adapter=None,
) -> None:
    mode = await integration_mode(db, reference.school_id)
    if mode not in FINREG_MODES:
        raise BillingError(
            "principia_pay_finreg_unavailable",
            "A escola não está ligada ao FinReg; a liquidação ficará pendente.",
            502,
        )
    adapter = adapter or (FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter())
    payment_external_id = f"cellen-ref-{reference.id}"
    payload = {
        "payment": {
            "document_id": str(reference.finreg_document_id),
            "payment_method": "mobile",
            "amount": str(amount),
            "payment_date": paid_at.date().isoformat(),
            "reference": (
                reference.reference or reference.caller_reference or ""
            )[:255],
            "notes": f"principia-pay {reference.external_id or ''}".strip(),
        }
    }
    actor = f"cellen-principia-pay:{reference.school_id}"
    try:
        await adapter.request(
            "POST",
            f"payments/{payment_external_id}",
            payload,
            idempotency_key=f"cellen-ref-payment-{reference.id}",
            correlation_id=f"cellen-ref-{reference.id}",
            actor_reference=actor,
        )
    except FinregError as exc:
        raise BillingError(
            "principia_pay_settlement_failed",
            f"O FinReg não aceitou a liquidação: {exc.detail}",
            502,
        ) from exc

    if mode in ("pilot", "live"):
        # The receipt is the fiscal proof of the settlement. Closed for
        # non-fiscal client profiles (403) -- that is a configuration, not
        # a failed payment, so it must not flip the reference back.
        try:
            await adapter.request(
                "POST",
                f"payments/{payment_external_id}/receipt",
                None,
                idempotency_key=f"cellen-ref-receipt-{reference.id}",
                correlation_id=f"cellen-ref-{reference.id}",
                actor_reference=actor,
            )
        except FinregError as exc:
            if exc.status_code != 403:
                logger.warning(
                    "principia-pay receipt failed for reference %s: %s",
                    reference.id,
                    exc.detail,
                )

    reference.status = "paid"
    reference.paid_amount = amount
    await db.commit()


async def _settle_internal(
    db: AsyncSession,
    reference: PaymentReference,
    *,
    amount: Decimal,
    paid_at: datetime,
) -> None:
    intake = PaymentIntakeService(db, reference.school_id)
    try:
        await intake.intake(
            billing_guardian_id=reference.billing_guardian_id,
            amount=amount,
            payment_method="mobile",
            payment_date=paid_at.date(),
            target_invoice_ids=(
                [reference.invoice_id] if reference.invoice_id else None
            ),
            payment_reference_id=reference.id,
            idempotency_key=f"cellen-ref-{reference.id}",
            notes=f"principia-pay {reference.external_id or ''}".strip(),
        )
    except ValueError as exc:
        raise BillingError(
            "principia_pay_settlement_failed", str(exc), 409
        ) from exc
    reference.status = "paid"
    reference.paid_amount = amount
    await db.commit()


# ── Webhook and reconciliation ────────────────────────────────────────────


async def handle_callback(
    db: AsyncSession, *, body: bytes, signature: Optional[str]
) -> dict:
    """Verify a rail webhook, then poll the rail for the authoritative state."""
    try:
        payload = json.loads(body)
    except ValueError as exc:
        raise BillingError("invalid_callback", "Corpo inválido.", 400) from exc
    caller_reference = payload.get("caller_reference") if isinstance(payload, dict) else None
    if not caller_reference:
        raise BillingError(
            "invalid_callback", "caller_reference em falta.", 400
        )
    reference = (
        await db.execute(
            select(PaymentReference).where(
                PaymentReference.provider == PROVIDER,
                PaymentReference.caller_reference == str(caller_reference),
            )
        )
    ).scalar_one_or_none()
    if reference is None:
        raise BillingError(
            "unknown_reference", "Referência desconhecida.", 404
        )
    connection = await get_connection(db, school_id=reference.school_id)
    if connection is None or not connection.callback_secret_ciphertext:
        raise BillingError(
            "signature_unavailable", "Assinatura não configurada.", 401
        )
    secret = decrypt_secret(connection.callback_secret_ciphertext)
    if not verify_webhook_signature(secret, body, signature):
        raise BillingError("invalid_signature", "Assinatura inválida.", 401)
    await refresh_reference(db, reference=reference)
    return {
        "status": "ok",
        "reference_status": reference.status,
        "rail_status": reference.rail_status,
    }


async def reconcile_references(
    db: AsyncSession, *, limit: int = 50, min_age_seconds: int = 60
) -> dict:
    """Poll every open rail reference that has not been checked recently."""
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=min_age_seconds)
    rows = (
        await db.execute(
            select(PaymentReference)
            .where(
                PaymentReference.provider == PROVIDER,
                PaymentReference.status.in_(("creating", "active")),
                or_(
                    PaymentReference.last_checked_at.is_(None),
                    PaymentReference.last_checked_at < cutoff,
                ),
            )
            .order_by(PaymentReference.created_at)
            .limit(limit)
        )
    ).scalars().all()

    checked = settled = failed = 0
    for reference in rows:
        checked += 1
        try:
            await refresh_reference(db, reference=reference)
            if reference.status == "paid":
                settled += 1
        except BillingError as exc:
            failed += 1
            await db.rollback()
            logger.warning(
                "Reference payment %s not reconciled: %s", reference.id, exc.code
            )
        except Exception:
            failed += 1
            await db.rollback()
            logger.exception("Reference payment %s reconciliation failed", reference.id)
    return {"checked": checked, "settled": settled, "failed": failed}
