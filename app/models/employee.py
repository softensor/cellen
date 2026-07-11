import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Index, Numeric, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class Employee(Base):
    __tablename__ = "employees"
    __table_args__ = (
        UniqueConstraint("school_id", "id_card_number", name="uq_employees_school_idcard"),
        Index("ix_employees_school_id", "school_id"),
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
    sex: Mapped[Optional[str]] = mapped_column(String(1))
    civil_state: Mapped[Optional[str]] = mapped_column(String(50))
    nationality: Mapped[Optional[str]] = mapped_column(String(100))
    naturality: Mapped[Optional[str]] = mapped_column(String(100))
    height: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2))
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
    # Contacts
    mobile_first: Mapped[Optional[str]] = mapped_column(String(50))
    mobile_second: Mapped[Optional[str]] = mapped_column(String(50))
    email: Mapped[Optional[str]] = mapped_column(String(255))
    # Employment
    employee_type: Mapped[str] = mapped_column(String(50), nullable=False)  # teacher, staff, admin
    position: Mapped[Optional[str]] = mapped_column(String(255))
    title_academic: Mapped[Optional[str]] = mapped_column(String(255))
    social_security: Mapped[Optional[str]] = mapped_column(String(100))
    contract_type: Mapped[Optional[str]] = mapped_column(String(50))  # permanent, temporary, intern
    hire_date: Mapped[Optional[date]] = mapped_column(Date)
    salary: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2))
    status: Mapped[str] = mapped_column(String(20), default="active")  # active, inactive, suspended
    privilege: Mapped[Optional[str]] = mapped_column(String(255))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
