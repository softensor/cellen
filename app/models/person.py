import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    Boolean, Date, DateTime, ForeignKey, Index, Numeric, String, UniqueConstraint, func
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Guardian(Base):
    __tablename__ = "guardians"
    __table_args__ = (
        Index("ix_guardians_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    first_name: Mapped[str] = mapped_column(String(100), nullable=False)
    middle_name: Mapped[Optional[str]] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100), nullable=False)
    birth_date: Mapped[Optional[date]] = mapped_column(Date)
    place_of_birth: Mapped[Optional[str]] = mapped_column(String(255))
    sex: Mapped[Optional[str]] = mapped_column(String(1))  # 'M', 'F'
    civil_state: Mapped[Optional[str]] = mapped_column(String(50))
    nationality: Mapped[Optional[str]] = mapped_column(String(100))
    naturality: Mapped[Optional[str]] = mapped_column(String(100))
    profession: Mapped[Optional[str]] = mapped_column(String(255))
    qualifications: Mapped[Optional[str]] = mapped_column(String(255))
    id_card_number: Mapped[Optional[str]] = mapped_column(String(100))
    photo_url: Mapped[Optional[str]] = mapped_column(String(500))
    # Address
    street: Mapped[Optional[str]] = mapped_column(String(255))
    house_number: Mapped[Optional[str]] = mapped_column(String(50))
    building_number: Mapped[Optional[str]] = mapped_column(String(50))
    apt_number: Mapped[Optional[str]] = mapped_column(String(50))
    city: Mapped[Optional[str]] = mapped_column(String(100))
    municipio: Mapped[Optional[str]] = mapped_column(String(100))
    bairro: Mapped[Optional[str]] = mapped_column(String(100))
    nif: Mapped[Optional[str]] = mapped_column(String(30), nullable=True)
    # Contacts
    mobile_first: Mapped[Optional[str]] = mapped_column(String(50))
    mobile_second: Mapped[Optional[str]] = mapped_column(String(50))
    email: Mapped[Optional[str]] = mapped_column(String(255))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    child_links = relationship("ChildGuardian", back_populates="guardian", cascade="all, delete-orphan")


class Child(Base):
    __tablename__ = "children"
    __table_args__ = (
        UniqueConstraint("school_id", "cedula", name="uq_children_school_cedula"),
        Index("ix_children_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    cedula: Mapped[str] = mapped_column(String(100), nullable=False)
    first_name: Mapped[str] = mapped_column(String(100), nullable=False)
    middle_name: Mapped[Optional[str]] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100), nullable=False)
    birth_date: Mapped[Optional[date]] = mapped_column(Date)
    place_of_birth: Mapped[Optional[str]] = mapped_column(String(255))
    sex: Mapped[Optional[str]] = mapped_column(String(1))
    nationality: Mapped[Optional[str]] = mapped_column(String(100))
    naturality: Mapped[Optional[str]] = mapped_column(String(100))
    height: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2))
    special_needs: Mapped[Optional[str]] = mapped_column(String(500))
    medical_prescription: Mapped[Optional[str]] = mapped_column(String(500))
    photo_url: Mapped[Optional[str]] = mapped_column(String(500))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Address inline
    street: Mapped[Optional[str]] = mapped_column(String(255))
    house_number: Mapped[Optional[str]] = mapped_column(String(50))
    building_number: Mapped[Optional[str]] = mapped_column(String(50))
    apt_number: Mapped[Optional[str]] = mapped_column(String(50))
    city: Mapped[Optional[str]] = mapped_column(String(100))
    municipio: Mapped[Optional[str]] = mapped_column(String(100))
    bairro: Mapped[Optional[str]] = mapped_column(String(100))
    # Emergency contacts
    emergency_contact_name: Mapped[Optional[str]] = mapped_column(String(255))
    emergency_contact_phone: Mapped[Optional[str]] = mapped_column(String(50))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    guardian_links = relationship("ChildGuardian", back_populates="child", cascade="all, delete-orphan")


class ChildGuardian(Base):
    __tablename__ = "child_guardians"
    __table_args__ = (
        UniqueConstraint("child_id", "guardian_id", name="uq_child_guardian"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("children.id", ondelete="CASCADE"), nullable=False
    )
    guardian_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("guardians.id", ondelete="RESTRICT"), nullable=False
    )
    relationship_type: Mapped[str] = mapped_column(String(50), nullable=False)  # father, mother, legal_guardian, grandparent, other
    is_primary_contact: Mapped[bool] = mapped_column(Boolean, default=False)

    child = relationship("Child", back_populates="guardian_links")
    guardian = relationship("Guardian", back_populates="child_links")
