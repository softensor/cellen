import uuid
from datetime import date, datetime, time
from typing import List, Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, String, Text, Time, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class TripAuthorization(Base):
    """Per-trip authorization created by a teacher/admin."""
    __tablename__ = "trip_authorizations"
    __table_args__ = (
        Index("ix_trip_authorizations_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="SET NULL"), nullable=True
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    trip_date: Mapped[date] = mapped_column(Date, nullable=False)
    destination: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    departure_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    return_time: Mapped[Optional[time]] = mapped_column(Time, nullable=True)
    deadline_date: Mapped[Optional[date]] = mapped_column(Date, nullable=True)
    target_turma_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("turmas.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())

    responses: Mapped[List["TripAuthorizationResponse"]] = relationship(
        back_populates="authorization", cascade="all, delete-orphan", lazy="selectin"
    )


class TripAuthorizationResponse(Base):
    """Per-child response from a parent/guardian."""
    __tablename__ = "trip_authorization_responses"
    __table_args__ = (
        UniqueConstraint("authorization_id", "child_id", name="uq_trip_response_auth_child"),
        Index("ix_trip_authorization_responses_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    authorization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("trip_authorizations.id", ondelete="CASCADE"), nullable=False
    )
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    authorized: Mapped[bool] = mapped_column(Boolean, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    responded_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())

    authorization: Mapped["TripAuthorization"] = relationship(back_populates="responses")
