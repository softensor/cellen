import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class School(Base):
    __tablename__ = "schools"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    address: Mapped[Optional[str]] = mapped_column(String(500))
    nif: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    legal_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    agt_series_prefix: Mapped[Optional[str]] = mapped_column(String(10), nullable=True, default="CE")
    city: Mapped[Optional[str]] = mapped_column(String(100))
    country: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(String(50))
    email: Mapped[Optional[str]] = mapped_column(String(255))
    logo_url: Mapped[Optional[str]] = mapped_column(String(500))
    currency: Mapped[str] = mapped_column(String(10), nullable=False, default="AOA")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # WhatsApp Business API settings (overrides platform env vars when set)
    wa_enabled: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    wa_phone_number_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    wa_access_token: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    # School type / segment (preschool | primary | secondary | combined | full)
    segment: Mapped[str] = mapped_column(String(30), nullable=False, default="preschool", server_default="preschool")
    # Per-school feature overrides (JSONB); merged with segment defaults at read time
    features: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    subscription_started_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    subscription_notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    @property
    def resolved_features(self) -> dict:
        """Merge segment defaults with per-school overrides."""
        defaults = _SEGMENT_DEFAULTS.get(self.segment, _SEGMENT_DEFAULTS["preschool"]).copy()
        if self.features:
            defaults.update(self.features)
        return defaults


# Feature defaults per school segment
_SEGMENT_DEFAULTS: dict[str, dict] = {
    "preschool": {
        "caderneta": True,
        "evaluations": True,      # developmental milestone tracking
        "meal_orders": True,
        "immunizations": True,
        "health": True,
        "grades": False,
        "subjects": False,
        "med_report": False,
        "trip_auth": True,
        "pickup_auth": True,
        "timetable_k12": False,   # uses simple activity schedule
    },
    "primary": {
        "caderneta": False,
        "evaluations": False,
        "meal_orders": True,
        "immunizations": True,
        "health": True,
        "grades": True,
        "subjects": True,
        "med_report": True,
        "trip_auth": True,
        "pickup_auth": False,
        "timetable_k12": True,    # uses subject×teacher×period grid
    },
    "secondary": {
        "caderneta": False,
        "evaluations": False,
        "meal_orders": False,
        "immunizations": False,
        "health": True,
        "grades": True,
        "subjects": True,
        "med_report": True,
        "trip_auth": False,
        "pickup_auth": False,
        "timetable_k12": True,
    },
    "combined": {
        "caderneta": False,
        "evaluations": False,
        "meal_orders": True,
        "immunizations": True,
        "health": True,
        "grades": True,
        "subjects": True,
        "med_report": True,
        "trip_auth": True,
        "pickup_auth": False,
        "timetable_k12": True,
    },
    "full": {
        "caderneta": True,
        "evaluations": True,
        "meal_orders": True,
        "immunizations": True,
        "health": True,
        "grades": True,
        "subjects": True,
        "med_report": True,
        "trip_auth": True,
        "pickup_auth": True,
        "timetable_k12": True,
    },
}


class PlatformUser(Base):
    __tablename__ = "platform_users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
