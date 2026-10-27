"""Authenticated encryption for stored rail secrets.

The seed is ``SECRET_KEY`` — the same platform secret Cellen already keeps
out of the repository. Only ciphertext ever lands in the database.
"""

import base64
import hashlib
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import settings


def _key() -> bytes:
    return hashlib.sha256(settings.SECRET_KEY.encode("utf-8")).digest()


def encrypt_secret(value: str) -> str:
    nonce = os.urandom(12)
    encrypted = AESGCM(_key()).encrypt(nonce, value.encode("utf-8"), None)
    return base64.urlsafe_b64encode(nonce + encrypted).decode("ascii")


def decrypt_secret(value: str) -> str:
    raw = base64.urlsafe_b64decode(value.encode("ascii"))
    return AESGCM(_key()).decrypt(raw[:12], raw[12:], None).decode("utf-8")
