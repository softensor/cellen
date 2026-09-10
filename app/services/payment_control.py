import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.finreg_integration import FinregSchoolConnection

ACTIVE_FINREG_MODES = {"fake", "shadow", "pilot", "live"}


async def finreg_is_active(db: AsyncSession, school_id: uuid.UUID) -> bool:
    """Return the authoritative per-school Finreg state without a remote call."""
    if not settings.FINREG_INTEGRATION_ENABLED:
        return False
    connection = (await db.execute(
        select(FinregSchoolConnection).where(
            FinregSchoolConnection.school_id == school_id
        )
    )).scalar_one_or_none()
    return bool(
        connection
        and not connection.kill_switch
        and connection.mode in ACTIVE_FINREG_MODES
    )
