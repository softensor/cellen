# -*- coding: utf-8 -*-
"""
AGT (Autoridade Geral Tributaria) compliance utilities.

Implements:
- RSA-SHA1 digital signature chain per Decreto Executivo n.º 683/25
- Document number generation
- Series management with per-series locking
- Canonical formatting
"""
import base64
import hashlib
import os
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional
from uuid import UUID

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finance import DocumentSeries

# ─── Timezone ─────────────────────────────────────────────────────────────────

LUANDA_UTC_OFFSET_HOURS = 1  # WAT = UTC+1, no DST


def now_luanda() -> datetime:
    """Current datetime in Africa/Luanda (UTC+1)."""
    from datetime import timezone, timedelta
    tz = timezone(timedelta(hours=LUANDA_UTC_OFFSET_HOURS))
    return datetime.now(tz)


def today_luanda() -> date:
    return now_luanda().date()


# ─── Formatting ───────────────────────────────────────────────────────────────

def format_gross_total(amount: Decimal) -> str:
    """Format amount per AGT canonical rules: 2 decimal places, dot separator."""
    rounded = amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{rounded:.2f}"


def format_system_entry_date(dt: datetime) -> str:
    """Format SystemEntryDate as YYYY-MM-DDThh:mm:ss (no timezone suffix in signed string)."""
    return dt.strftime("%Y-%m-%dT%H:%M:%S")


def format_invoice_date(d: date) -> str:
    return d.strftime("%Y-%m-%d")


def generate_document_number(doc_type: str, year: int, number: int) -> str:
    """Generate AGT document number: 'FT 2026/1' (no zero-padding per spec)."""
    return f"{doc_type} {year}/{number}"


def signature_excerpt(hash_code: str) -> str:
    """Extract the 4-character signature excerpt for document printing.
    Characters at positions 1, 11, 21, 31 of the Base64 signature."""
    if not hash_code or len(hash_code) < 32:
        return "----"
    try:
        return hash_code[0] + hash_code[10] + hash_code[20] + hash_code[30]
    except IndexError:
        return "----"


# ─── Line computation ─────────────────────────────────────────────────────────

def compute_line(
    unit_price: Decimal,
    quantity: Decimal,
    discount_percent: Decimal = Decimal("0"),
    discount_amount: Decimal = Decimal("0"),
    iva_rate: Decimal = Decimal("0"),
) -> dict:
    """Compute line_net, iva_amount, line_total per spec 20.5 rules."""
    gross = unit_price * quantity
    if discount_percent > 0:
        discount = (gross * discount_percent / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    elif discount_amount > 0:
        discount = discount_amount
    else:
        discount = Decimal("0")
    line_net = (gross - discount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    iva_amount = (line_net * iva_rate / Decimal("100")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    line_total = (line_net + iva_amount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return {
        "line_net": line_net,
        "iva_amount": iva_amount,
        "line_total": line_total,
        "discount": discount,
    }


# ─── RSA-SHA1 Signing ────────────────────────────────────────────────────────

def _get_private_key():
    """Load the RSA private key from environment variable (PEM format)."""
    key_pem = os.environ.get("AGT_PRIVATE_KEY")
    if not key_pem:
        # Fallback: generate a temporary key for development (NOT for production)
        return _get_or_generate_dev_key()
    return serialization.load_pem_private_key(key_pem.encode(), password=None)


def _get_or_generate_dev_key():
    """For development only — generate and cache an RSA key."""
    key_path = "/tmp/cellen_dev_agt_key.pem"
    try:
        with open(key_path, "rb") as f:
            return serialization.load_pem_private_key(f.read(), password=None)
    except (FileNotFoundError, Exception):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        with open(key_path, "wb") as f:
            f.write(pem)
        return key


def sign_document(
    invoice_date: date,
    system_entry_date: datetime,
    document_number: str,
    gross_total: Decimal,
    previous_hash: str,
) -> str:
    """
    Sign a fiscal document per AGT requirements.

    Signs the string:
        {InvoiceDate};{SystemEntryDate};{DocumentNumber};{GrossTotal};{PreviousHash}

    Returns Base64-encoded RSA-SHA1 signature.
    """
    # Build the signing string
    parts = [
        format_invoice_date(invoice_date),
        format_system_entry_date(system_entry_date),
        document_number,
        format_gross_total(gross_total),
        previous_hash or "0",
    ]
    sign_string = ";".join(parts)

    # Sign with RSA-SHA1
    private_key = _get_private_key()
    signature = private_key.sign(
        sign_string.encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA1(),
    )
    return base64.b64encode(signature).decode("ascii")


def verify_signature(
    invoice_date: date,
    system_entry_date: datetime,
    document_number: str,
    gross_total: Decimal,
    previous_hash: str,
    hash_code: str,
) -> bool:
    """Verify a document's signature using the public key."""
    parts = [
        format_invoice_date(invoice_date),
        format_system_entry_date(system_entry_date),
        document_number,
        format_gross_total(gross_total),
        previous_hash or "0",
    ]
    sign_string = ";".join(parts)

    private_key = _get_private_key()
    public_key = private_key.public_key()
    try:
        public_key.verify(
            base64.b64decode(hash_code),
            sign_string.encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA1(),
        )
        return True
    except Exception:
        return False


# ─── Series Management ────────────────────────────────────────────────────────

async def acquire_series_lock(
    db: AsyncSession,
    school_id: UUID,
    doc_type: str,
    year: int,
) -> DocumentSeries:
    """
    Acquire a per-series lock (SELECT FOR UPDATE) and return the series.
    Creates the series if it doesn't exist (first use).
    This MUST be called within a transaction.
    """
    result = await db.execute(
        select(DocumentSeries)
        .where(
            DocumentSeries.school_id == school_id,
            DocumentSeries.document_type == doc_type,
            DocumentSeries.year == year,
        )
        .with_for_update()
    )
    series = result.scalar_one_or_none()

    if series is None:
        series = DocumentSeries(
            school_id=school_id,
            document_type=doc_type,
            year=year,
            next_number=1,
            last_hash=None,
            last_invoice_date=None,
            last_system_entry_date=None,
        )
        db.add(series)
        await db.flush()
        # Re-acquire with lock
        result = await db.execute(
            select(DocumentSeries)
            .where(DocumentSeries.id == series.id)
            .with_for_update()
        )
        series = result.scalar_one()

    return series


async def emit_document_number(
    db: AsyncSession,
    school_id: UUID,
    doc_type: str,
    invoice_date: date,
    gross_total: Decimal,
) -> dict:
    """
    Atomically allocate the next number in a series, sign the document,
    and update the series state. Returns dict with all chain fields.

    MUST be called within a transaction. The series row remains locked
    until commit/rollback.
    """
    system_entry_date = now_luanda()
    year = system_entry_date.year

    series = await acquire_series_lock(db, school_id, doc_type, year)

    # Validate monotonicity
    if series.last_invoice_date and invoice_date < series.last_invoice_date:
        raise ValueError(
            f"InvoiceDate {invoice_date} is before the last document date "
            f"{series.last_invoice_date} in series {doc_type} {year}"
        )
    if series.last_system_entry_date and system_entry_date <= series.last_system_entry_date:
        # Clock skew — bump by 1 second to maintain monotonicity
        from datetime import timedelta
        system_entry_date = series.last_system_entry_date + timedelta(seconds=1)

    number = series.next_number
    doc_number = generate_document_number(doc_type, year, number)
    previous_hash = series.last_hash or "0"

    # Sign
    hash_code = sign_document(
        invoice_date=invoice_date,
        system_entry_date=system_entry_date,
        document_number=doc_number,
        gross_total=gross_total,
        previous_hash=previous_hash if previous_hash != "0" else "",
    )

    # Update series state
    series.next_number = number + 1
    series.last_hash = hash_code
    series.last_invoice_date = invoice_date
    series.last_system_entry_date = system_entry_date

    return {
        "series_year": year,
        "series_number": number,
        "full_document_number": doc_number,
        "system_entry_date": system_entry_date,
        "invoice_date": invoice_date,
        "hash_code": hash_code,
        "previous_hash": previous_hash if previous_hash != "0" else None,
        "gross_total": gross_total,
    }
