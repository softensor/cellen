import uuid
from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Optional

from sqlalchemy import (
    Boolean, Date, DateTime, ForeignKey, Index, Integer, Numeric, String,
    Text, Time, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Attendance(Base):
    __tablename__ = "attendance"
    __table_args__ = (
        UniqueConstraint("school_id", "child_id", "attendance_date", name="uq_attendance_school_child_date"),
        Index("ix_attendance_school_id", "school_id"),
        Index("ix_attendance_attendance_date", "attendance_date"),
        Index("ix_attendance_child_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    recorded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    attendance_date: Mapped[date] = mapped_column(Date, nullable=False, server_default=func.current_date())
    check_in_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    check_out_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="present")
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AttendanceLog(Base):
    """Individual check-in / check-out event (multiple per day per child)."""
    __tablename__ = "attendance_logs"
    __table_args__ = (
        Index("ix_attendance_logs_school_id", "school_id"),
        Index("ix_attendance_logs_child_date", "school_id", "child_id", "attendance_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    recorded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    attendance_date: Mapped[date] = mapped_column(Date, nullable=False)
    event_type: Mapped[str] = mapped_column(String(20), nullable=False)  # check_in | check_out
    event_time: Mapped[time] = mapped_column(Time, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class MessageThread(Base):
    __tablename__ = "message_threads"
    __table_args__ = (
        Index("ix_message_threads_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    subject: Mapped[str] = mapped_column(String(255), nullable=False)
    thread_type: Mapped[str] = mapped_column(String(20), nullable=False, default="direct")
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())

    participants = relationship("ThreadParticipant", back_populates="thread", cascade="all, delete-orphan")
    messages = relationship("Message", back_populates="thread", cascade="all, delete-orphan")


class ThreadParticipant(Base):
    __tablename__ = "thread_participants"

    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("message_threads.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    school_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=True
    )
    last_read_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    thread = relationship("MessageThread", back_populates="participants")


class Message(Base):
    __tablename__ = "messages"
    __table_args__ = (
        Index("ix_messages_school_id", "school_id"),
        Index("ix_messages_thread_id", "thread_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    thread_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("message_threads.id", ondelete="CASCADE"), nullable=False
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())

    thread = relationship("MessageThread", back_populates="messages")


class Photo(Base):
    __tablename__ = "photos"
    __table_args__ = (
        Index("ix_photos_school_id", "school_id"),
        Index("ix_photos_photo_date", "photo_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    uploaded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    turma_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("turmas.id", ondelete="SET NULL"), nullable=True
    )
    child_ids: Mapped[Optional[Any]] = mapped_column(JSONB, nullable=True)
    url: Mapped[str] = mapped_column(String(500), nullable=False)
    caption: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    photo_date: Mapped[date] = mapped_column(Date, nullable=False, server_default=func.current_date())
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Incident(Base):
    __tablename__ = "incidents"
    __table_args__ = (
        Index("ix_incidents_school_id", "school_id"),
        Index("ix_incidents_child_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    reported_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    incident_date: Mapped[date] = mapped_column(Date, nullable=False, server_default=func.current_date())
    incident_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    severity: Mapped[str] = mapped_column(String(20), nullable=False, default="minor")
    description: Mapped[str] = mapped_column(Text, nullable=False)
    action_taken: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    parent_notified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    parent_notified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        Index("ix_events_school_id", "school_id"),
        Index("ix_events_start_date", "start_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False, default="school_event")
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    start_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    end_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    all_day: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    location: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    turma_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("turmas.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_school_id", "school_id"),
        Index("ix_notifications_user_id", "user_id"),
        Index("ix_notifications_is_read", "is_read"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    related_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), nullable=True)
    related_type: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


# ─── AGT Finance Models (re-exported from finance.py for backward compat) ─────
from app.models.finance import (  # noqa: F401, E402
    DocumentSeries, Receipt, CreditNote, Contract,
)


# ─── New Feature Models ────────────────────────────────────────────────────────

class Announcement(Base):
    __tablename__ = "announcements"
    __table_args__ = (
        Index("ix_announcements_school_id", "school_id"),
        Index("ix_announcements_created_at", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    attachment_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    attachment_name: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    target: Mapped[str] = mapped_column(String(20), nullable=False, default="all")
    pinned: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DocumentLibrary(Base):
    __tablename__ = "documents_library"
    __table_args__ = (
        Index("ix_documents_library_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    uploaded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    file_url: Mapped[str] = mapped_column(String(500), nullable=False)
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    file_type: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    target: Mapped[str] = mapped_column(String(20), nullable=False, default="all")
    child_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        Index("ix_appointments_school_id", "school_id"),
        Index("ix_appointments_employee_id", "employee_id"),
        Index("ix_appointments_requested_by", "requested_by"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    requested_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    employee_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL"), nullable=True
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    proposed_date: Mapped[date] = mapped_column(Date, nullable=False)
    proposed_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    confirmed_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    confirmed_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    response_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ChildEvaluation(Base):
    __tablename__ = "child_evaluations"
    __table_args__ = (
        UniqueConstraint(
            "school_id", "child_id", "evaluation_period", "school_year_id",
            name="uq_child_evaluation_period"
        ),
        Index("ix_child_evaluations_school_id", "school_id"),
        Index("ix_child_evaluations_child_id", "child_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    evaluated_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    school_year_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("school_years.id", ondelete="SET NULL"), nullable=True
    )
    evaluation_period: Mapped[str] = mapped_column(String(50), nullable=False)
    evaluation_date: Mapped[date] = mapped_column(Date, nullable=False, server_default=func.current_date())
    cognitive: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    motor: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    language: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    social_emotional: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    creativity: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    autonomy: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    overall_rating: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    observations: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    areas_to_improve: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    objectives_next_period: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class HealthEvent(Base):
    __tablename__ = "health_events"
    __table_args__ = (
        Index("ix_health_events_school_id", "school_id"),
        Index("ix_health_events_child_id", "child_id"),
        Index("ix_health_events_event_date", "event_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    recorded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    event_date: Mapped[date] = mapped_column(Date, nullable=False, server_default=func.current_date())
    event_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    temperature: Mapped[Optional[Decimal]] = mapped_column(Numeric(4, 1), nullable=True)
    medication_given: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    parent_notified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    parent_notified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    action_taken: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
