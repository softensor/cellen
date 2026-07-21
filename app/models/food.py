import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Food(Base):
    __tablename__ = "foods"
    __table_args__ = (
        Index("ix_foods_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    details: Mapped[Optional[str]] = mapped_column(String(500))
    type: Mapped[Optional[str]] = mapped_column(String(50))  # breakfast, lunch, snack, etc.
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())


class FoodMenu(Base):
    __tablename__ = "food_menus"
    __table_args__ = (
        Index("ix_food_menus_school_id", "school_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    level: Mapped[str] = mapped_column(String(100), nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    items = relationship("FoodMenuItem", back_populates="menu", cascade="all, delete-orphan", lazy="selectin")


class FoodMenuItem(Base):
    __tablename__ = "food_menu_items"
    __table_args__ = (
        UniqueConstraint(
            "food_menu_id", "day_of_week", "meal_type", "meal_component",
            name="uq_food_menu_item"
        ),
        Index("ix_food_menu_items_school_id", "school_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    school_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("schools.id", ondelete="RESTRICT"), nullable=False
    )
    food_menu_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("food_menus.id", ondelete="CASCADE"), nullable=False
    )
    day_of_week: Mapped[int] = mapped_column(Integer, nullable=False)  # 0-6
    meal_type: Mapped[str] = mapped_column(String(50), nullable=False)  # breakfast, lunch, snack
    meal_component: Mapped[Optional[str]] = mapped_column(String(50))  # sopa, prato, sobremesa, drink
    food_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("foods.id", ondelete="RESTRICT"), nullable=False
    )

    menu = relationship("FoodMenu", back_populates="items")
    food = relationship("Food", lazy="selectin")

    @property
    def food_name(self) -> Optional[str]:
        return self.food.name if self.food else None
