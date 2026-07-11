import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Caderneta(Base):
    __tablename__ = "cadernetas"
    __table_args__ = (
        UniqueConstraint("school_id", "child_id", "report_date", name="uq_caderneta_child_date"),
        Index("ix_cadernetas_school_id", "school_id"),
        Index("ix_cadernetas_child_id", "child_id"),
        Index("ix_cadernetas_report_date", "report_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="RESTRICT"), nullable=False
    )
    teacher_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("employees.id", ondelete="RESTRICT"), nullable=False
    )
    report_date: Mapped[date] = mapped_column(Date, default=date.today, nullable=False)
    breakfast_rating: Mapped[Optional[str]] = mapped_column(String(50))  # Bem, Muito Bem, Mal, Não Comeu
    lunch_rating: Mapped[Optional[str]] = mapped_column(String(50))
    snack_rating: Mapped[Optional[str]] = mapped_column(String(50))
    physiological_needs: Mapped[Optional[str]] = mapped_column(String(50))  # Normal, Mole, Duro
    had_nap: Mapped[Optional[bool]] = mapped_column(Boolean)
    sensorial_motor_development: Mapped[Optional[str]] = mapped_column(String(255))
    intellectual_development: Mapped[Optional[str]] = mapped_column(String(255))
    social_development: Mapped[Optional[str]] = mapped_column(String(255))
    affective_development: Mapped[Optional[str]] = mapped_column(String(255))
    general_observations: Mapped[Optional[str]] = mapped_column(Text)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
