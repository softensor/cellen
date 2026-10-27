from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PlatformSettings(Base):
    """Single-row configuration for the platform operator.

    This is the platform's own configuration, not tenant data: there is no
    ``school_id`` and nothing here is scoped per school. ``id`` is pinned to
    1, exactly like the row the finance activation screens read.

    The principia-pay product token lives encrypted (``secret_box``), and
    only its non-secret identifying prefix is ever shown back. Base URL,
    provider and source system stay environment facts -- the token is the
    one value an owner types into a screen.
    """

    __tablename__ = "platform_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)

    # The switch the owner's Pagamentos screen flips. Disabled wins over
    # both a stored token and the environment fallback, so deactivation in
    # the console cannot be undone by an env var left in .env.
    principia_pay_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    principia_pay_token_ciphertext: Mapped[Optional[str]] = mapped_column(Text)
    principia_pay_token_prefix: Mapped[Optional[str]] = mapped_column(String(12))
    # not_configured | unchecked | attention | connected. Advisory: it is
    # what the last activation probe answered, shown next to the switch.
    principia_pay_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="not_configured",
        server_default="not_configured",
    )
    principia_pay_last_error: Mapped[Optional[str]] = mapped_column(String(1000))
    principia_pay_last_checked_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True)
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
