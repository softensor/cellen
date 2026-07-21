import asyncio
import os
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

# Load alembic config
config = context.config

# Logging setup
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Import ALL models so that autogenerate can detect them
from app.models.base import Base
from app.models.school import School, PlatformUser  # noqa: F401
from app.models.user import User  # noqa: F401
from app.models.person import Guardian, Child, ChildGuardian  # noqa: F401
from app.models.employee import Employee  # noqa: F401
from app.models.academic import (  # noqa: F401
    SchoolYear, Turma, Activity, Schedule, ScheduleTeacher, ScheduleSlot, Enrollment,
    TimetablePeriod,
)
from app.models.caderneta import Caderneta  # noqa: F401
from app.models.food import Food, FoodMenu, FoodMenuItem  # noqa: F401
from app.models.absence import Absence  # noqa: F401
from app.models.immunization import Immunization  # noqa: F401
from app.models.finance import (  # noqa: F401
    ExpenseCategory, Expense, Invoice, InvoiceLine, Payment, PaymentAllocation,
    BillingItem, BillingItemPrice, Contract, CreditNote, Receipt, DocumentSeries,
    PaymentReference, CreditEntry, CreditRefund, CashSession,
    PaymentPlan, PaymentPlanInstallment, ReminderLog, FinanceAuditEntry,
)
from app.models.grades import Subject, TurmaSubject, Mark  # noqa: F401
from app.models.modern import (  # noqa: F401
    Attendance, AttendanceLog, AttendanceDayStatus,
    MessageThread, ThreadParticipant, Message,
    Photo, Incident, Event, Notification, Announcement,
    DocumentLibrary, Appointment, ChildEvaluation, HealthEvent,
)
from app.models.trip_authorization import TripAuthorization, TripAuthorizationResponse  # noqa: F401
from app.models.pickup_auth import PickupAuthorization, MealOrder  # noqa: F401
from app.models.website import (  # noqa: F401
    WebsiteSetting, WebsitePage, WebsiteSection, WebsiteMedia,
    WebsiteContactSubmission,
)

target_metadata = Base.metadata

# Read DB URL from environment (overrides blank alembic.ini value)
def get_url() -> str:
    from app.core.config import settings
    return settings.DATABASE_URL


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = get_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """Run migrations in 'online' mode with async engine."""
    config_section = config.get_section(config.config_ini_section, {})
    config_section["sqlalchemy.url"] = get_url()

    connectable = async_engine_from_config(
        config_section,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
