# -*- coding: utf-8 -*-
"""Per-school principia-pay connection.

Each school registers its own principia-pay product client, so money collected
through reference payments settles into that school's account and never into
another's. The API key and callback secret are stored encrypted (see
``app/services/secret_box.py``); this module only holds the ciphertext.

Mirrors ``FinregBillingInstruction``/``FinregConnection`` conventions: one row
per school, an external identity, a status, and the last error for operators.
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PrincipiaPayConnection(Base):
    __tablename__ = "principia_pay_connections"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    # principia-pay's own client id (UUID, kept as text: only logged/displayed).
    client_id: Mapped[str] = mapped_column(String(40), nullable=False)
    api_key_ciphertext: Mapped[str] = mapped_column(Text, nullable=False)
    callback_secret_ciphertext: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    # active, disabled, error
    last_error: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
