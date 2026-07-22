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
        """Merge segment defaults with per-school overrides (deep-merge dicts).
        Null values in overrides are skipped — they fall back to the segment default.
        """
        defaults = _SEGMENT_DEFAULTS.get(self.segment, _SEGMENT_DEFAULTS["preschool"]).copy()
        if self.features:
            for key, value in self.features.items():
                if value is None:
                    continue  # skip nulls — use segment default
                if isinstance(value, dict) and isinstance(defaults.get(key), dict):
                    defaults[key] = {**defaults[key], **value}
                else:
                    defaults[key] = value
        return defaults


# ---------------------------------------------------------------------------
# Feature defaults per school segment.
# These are the starting point. Platform admin can override any key per school
# via school.features (JSONB). resolved_features = merge(defaults, overrides).
#
# role_permissions: dict[role_key, dict[feature_key, bool]]
#   Controls which features each role can ACCESS at this school.
#   Default (missing key) = True (access granted).
#   Platform admin sets explicit False to restrict a role from a feature.
# ---------------------------------------------------------------------------
_SEGMENT_DEFAULTS: dict[str, dict] = {
    "preschool": {
        # ── Pedagógico ─────────────────────────────────────
        "checkin": True,
        "caderneta": True,
        "evaluations": True,
        "activities": True,
        "timetable_k12": False,
        "lesson_attendance": False,
        "grades": False,
        "subjects": False,
        "report_cards": False,
        "appointments": True,
        # ── Saúde & Incidentes ─────────────────────────────
        "health": True,
        "immunizations": True,
        "med_report": False,
        "incidents": True,
        # ── Operacional ────────────────────────────────────
        "meal_orders": True,
        "trip_auth": True,
        "pickup_auth": True,
        "photos": True,
        "events": True,
        "documents": True,
        # ── Comunicação ────────────────────────────────────
        "announcements": True,
        "messages": True,
        # ── Financeiro ─────────────────────────────────────
        "finance": True,
        # ── Funções disponíveis ────────────────────────────
        "absences": True,
        "role_teacher": True,
        "role_coordinator": True,
        "role_finance_officer": True,
        "role_secretary": True,
        "role_nurse": True,
        "role_student": False,
        # ── Permissões por função (overrides only) ─────────
        # role_permissions: {} means "all roles get default access"
        "role_permissions": {},
    },
    "primary": {
        # ── Pedagógico ─────────────────────────────────────
        "checkin": False,
        "caderneta": False,
        "evaluations": False,
        "activities": False,
        "timetable_k12": True,
        "lesson_attendance": True,
        "grades": True,
        "subjects": True,
        "report_cards": True,
        "appointments": True,
        # ── Saúde & Incidentes ─────────────────────────────
        "health": True,
        "immunizations": True,
        "med_report": True,
        "incidents": True,
        # ── Operacional ────────────────────────────────────
        "meal_orders": True,
        "trip_auth": True,
        "pickup_auth": True,
        "photos": True,
        "events": True,
        "documents": True,
        # ── Comunicação ────────────────────────────────────
        "announcements": True,
        "messages": True,
        # ── Financeiro ─────────────────────────────────────
        "finance": True,
        # ── Funções disponíveis ────────────────────────────
        "absences": True,
        "role_teacher": True,
        "role_coordinator": True,
        "role_finance_officer": True,
        "role_secretary": True,
        "role_nurse": True,
        "role_student": False,
        "role_permissions": {},
    },
    "secondary": {
        # ── Pedagógico ─────────────────────────────────────
        "checkin": False,
        "caderneta": False,
        "evaluations": False,
        "activities": False,
        "timetable_k12": True,
        "lesson_attendance": True,
        "grades": True,
        "subjects": True,
        "report_cards": True,
        "appointments": False,
        # ── Saúde & Incidentes ─────────────────────────────
        "health": True,
        "immunizations": False,
        "med_report": True,
        "incidents": True,
        # ── Operacional ────────────────────────────────────
        "meal_orders": False,
        "trip_auth": False,
        "pickup_auth": False,
        "photos": False,
        "events": True,
        "documents": True,
        # ── Comunicação ────────────────────────────────────
        "announcements": True,
        "messages": True,
        # ── Financeiro ─────────────────────────────────────
        "finance": True,
        # ── Funções disponíveis ────────────────────────────
        "absences": True,
        "role_teacher": True,
        "role_coordinator": True,
        "role_finance_officer": True,
        "role_secretary": True,
        "role_nurse": False,
        "role_student": True,
        "role_permissions": {},
    },
    "combined": {
        # ── Pedagógico ─────────────────────────────────────
        "checkin": False,
        "caderneta": False,
        "evaluations": False,
        "activities": False,
        "timetable_k12": True,
        "lesson_attendance": True,
        "grades": True,
        "subjects": True,
        "report_cards": True,
        "appointments": True,
        # ── Saúde & Incidentes ─────────────────────────────
        "health": True,
        "immunizations": True,
        "med_report": True,
        "incidents": True,
        # ── Operacional ────────────────────────────────────
        "meal_orders": True,
        "trip_auth": True,
        "pickup_auth": True,
        "photos": True,
        "events": True,
        "documents": True,
        # ── Comunicação ────────────────────────────────────
        "announcements": True,
        "messages": True,
        # ── Financeiro ─────────────────────────────────────
        "finance": True,
        # ── Funções disponíveis ────────────────────────────
        "absences": True,
        "role_teacher": True,
        "role_coordinator": True,
        "role_finance_officer": True,
        "role_secretary": True,
        "role_nurse": True,
        "role_student": True,
        "role_permissions": {},
    },
    "full": {
        # ── Pedagógico ─────────────────────────────────────
        "checkin": True,
        "caderneta": True,
        "evaluations": True,
        "activities": True,
        "timetable_k12": True,
        "lesson_attendance": True,
        "grades": True,
        "subjects": True,
        "report_cards": True,
        "appointments": True,
        # ── Saúde & Incidentes ─────────────────────────────
        "health": True,
        "immunizations": True,
        "med_report": True,
        "incidents": True,
        # ── Operacional ────────────────────────────────────
        "meal_orders": True,
        "trip_auth": True,
        "pickup_auth": True,
        "photos": True,
        "events": True,
        "documents": True,
        # ── Comunicação ────────────────────────────────────
        "announcements": True,
        "messages": True,
        # ── Financeiro ─────────────────────────────────────
        "finance": True,
        # ── Funções disponíveis ────────────────────────────
        "absences": True,
        "role_teacher": True,
        "role_coordinator": True,
        "role_finance_officer": True,
        "role_secretary": True,
        "role_nurse": True,
        "role_student": True,
        "role_permissions": {},
    },
}


class PlatformUser(Base):
    __tablename__ = "platform_users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
