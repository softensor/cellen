"""The platform owner's principia-pay rail, configured from the product.

The rail shipped env-only: turning it on (and rotating its product token)
meant an SSH edit followed by a restart. What an admin configures belongs in
an admin surface, so this router is that surface, following the shape
Mwenenzo's own Pagamentos screen has proven: the token is encrypted into the
singleton ``platform_settings`` row, live-verified against the rail's
``GET /v1/products/{source_system}`` before it is armed, and only its
non-secret identifying prefix ever leaves the server.

Registration of the schools themselves stays where it belongs -- each school
is its own rail client -- but the owner console can trigger it for any
school and reads the rail's own onboarding state per row, so "will a
payment work?" is answered from the rail, never guessed locally.
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_platform_admin
from app.models.school import School
from app.schemas.platform_payments import (
    PlatformPaymentSchoolRegistration,
    PlatformPaymentsActivationRequest,
    PlatformPaymentsStatusResponse,
    PlatformPaymentSchoolsResponse,
)
from app.services import principia_pay
from app.services.billing_run import BillingError

router = APIRouter(prefix="/platform", tags=["Platform Payments"])


def _raise_billing(exc: BillingError) -> None:
    raise HTTPException(
        status_code=exc.status_code,
        detail={"code": exc.code, "message": exc.detail},
    )


@router.get("/payments/status", response_model=PlatformPaymentsStatusResponse)
async def platform_payments_status(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    return await principia_pay.platform_status(db)


@router.post("/payments/activate", response_model=PlatformPaymentsStatusResponse)
async def activate_platform_payments(
    body: PlatformPaymentsActivationRequest,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    return await principia_pay.activate_platform_token(db, body.product_token)


@router.post("/payments/deactivate", response_model=PlatformPaymentsStatusResponse)
async def deactivate_platform_payments(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    return await principia_pay.deactivate_platform_token(db)


@router.get(
    "/payments/schools", response_model=PlatformPaymentSchoolsResponse
)
async def platform_payment_schools(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    return await principia_pay.platform_schools(db)


@router.post(
    "/payments/schools/{school_id}/register",
    response_model=PlatformPaymentSchoolRegistration,
)
async def register_payment_school(
    school_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    try:
        status = await principia_pay.register_school(db, school_id=school_id)
    except BillingError as exc:
        _raise_billing(exc)
    school = await db.get(School, school_id)
    return PlatformPaymentSchoolRegistration(
        school_id=school_id,
        name=school.name if school is not None else "",
        registered=bool(status.get("registered")),
        client_id=status.get("client_id"),
        status=str(status.get("status") or "unknown"),
    )
