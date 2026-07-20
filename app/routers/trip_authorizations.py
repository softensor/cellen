import uuid
from datetime import date, datetime, time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher
from app.models.trip_authorization import TripAuthorization, TripAuthorizationResponse

router = APIRouter(prefix="/trip-authorizations", tags=["Trip Authorizations"])


# ─── Schemas ─────────────────────────────────────────────────────────────────

class TripAuthCreate(BaseModel):
    child_id: Optional[uuid.UUID] = None
    title: Optional[str] = None
    trip_date: date
    destination: Optional[str] = None
    description: Optional[str] = None
    departure_time: Optional[time] = None
    return_time: Optional[time] = None
    deadline_date: Optional[date] = None
    target_turma_id: Optional[uuid.UUID] = None


class TripRespondBody(BaseModel):
    response: str  # "approved" or "denied"


class TripAuthOut(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    school_id: uuid.UUID
    title: Optional[str] = None
    trip_date: date
    destination: Optional[str] = None
    description: Optional[str] = None
    child_id: Optional[uuid.UUID] = None
    departure_time: Optional[time] = None
    return_time: Optional[time] = None
    deadline_date: Optional[date] = None
    parent_response: Optional[str] = None
    created_at: Optional[datetime] = None


class TripRespondOut(BaseModel):
    id: uuid.UUID
    parent_response: str
    response_date: Optional[datetime] = None


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _parent_response_label(authorized: Optional[bool]) -> Optional[str]:
    if authorized is None:
        return "pending"
    return "approved" if authorized else "denied"


async def _get_trip_response_for_child(
    db: AsyncSession, trip_id: uuid.UUID, child_id: uuid.UUID
) -> Optional[TripAuthorizationResponse]:
    result = await db.execute(
        select(TripAuthorizationResponse).where(
            TripAuthorizationResponse.authorization_id == trip_id,
            TripAuthorizationResponse.child_id == child_id,
        )
    )
    return result.scalar_one_or_none()


# ─── Endpoints ───────────────────────────────────────────────────────────────

@router.get("", response_model=list[TripAuthOut])
async def list_trip_authorizations(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    role = getattr(current_user, "_role", None)
    query = (
        select(TripAuthorization)
        .where(TripAuthorization.school_id == school_id)
        .order_by(TripAuthorization.trip_date.desc())
    )

    # Parents only see trips for their own children.
    if role not in ("school_admin", "platform_admin", "teacher"):
        from app.models.person import ChildGuardian
        guardian_id = getattr(current_user, "guardian_id", None)
        if not guardian_id:
            return []
        child_ids_r = await db.execute(
            select(ChildGuardian.child_id).where(ChildGuardian.guardian_id == guardian_id)
        )
        allowed = [r[0] for r in child_ids_r.all()]
        if not allowed:
            return []
        query = query.where(TripAuthorization.child_id.in_(allowed))

    result = await db.execute(query)
    trips = result.scalars().unique().all()

    out = []
    for trip in trips:
        trip_dict = {c.key: getattr(trip, c.key) for c in trip.__table__.columns}
        # Compute parent_response from responses if trip has a child_id
        parent_response = None
        if trip.child_id:
            resp = await _get_trip_response_for_child(db, trip.id, trip.child_id)
            if resp is not None:
                parent_response = _parent_response_label(resp.authorized)
        trip_dict["parent_response"] = parent_response
        out.append(trip_dict)

    return out


@router.post("", response_model=TripAuthOut, status_code=status.HTTP_201_CREATED)
async def create_trip_authorization(
    body: TripAuthCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(require_teacher),
):
    title = body.title or (f"Visita a {body.destination}" if body.destination else "Visita de estudo")
    trip = TripAuthorization(
        school_id=school_id,
        created_by=current_user.id,
        child_id=body.child_id,
        title=title,
        trip_date=body.trip_date,
        destination=body.destination,
        description=body.description,
        departure_time=body.departure_time,
        return_time=body.return_time,
        deadline_date=body.deadline_date,
        target_turma_id=body.target_turma_id,
    )
    db.add(trip)
    await db.commit()
    await db.refresh(trip)

    trip_dict = {c.key: getattr(trip, c.key) for c in trip.__table__.columns}
    trip_dict["parent_response"] = None
    return trip_dict


@router.get("/{trip_id}", response_model=TripAuthOut)
async def get_trip_authorization(
    trip_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    result = await db.execute(
        select(TripAuthorization).where(
            TripAuthorization.id == trip_id,
            TripAuthorization.school_id == school_id,
        )
    )
    trip = result.scalar_one_or_none()
    if trip is None:
        raise HTTPException(status_code=404, detail="Trip authorization not found")

    trip_dict = {c.key: getattr(trip, c.key) for c in trip.__table__.columns}
    parent_response = None
    if trip.child_id:
        resp = await _get_trip_response_for_child(db, trip.id, trip.child_id)
        if resp is not None:
            parent_response = _parent_response_label(resp.authorized)
    trip_dict["parent_response"] = parent_response
    return trip_dict


@router.post("/{trip_id}/respond", response_model=TripRespondOut, status_code=status.HTTP_200_OK)
async def respond_to_trip_authorization(
    trip_id: uuid.UUID,
    body: TripRespondBody,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    current_user=Depends(get_current_user),
):
    from app.models.person import ChildGuardian

    if body.response not in ("approved", "denied"):
        raise HTTPException(status_code=422, detail="response must be 'approved' or 'denied'")

    # Only parents/guardians can respond
    guardian_id = getattr(current_user, "guardian_id", None)
    if guardian_id is None:
        raise HTTPException(status_code=403, detail="Only parents can respond to trip authorizations")

    # Verify trip exists
    result = await db.execute(
        select(TripAuthorization).where(
            TripAuthorization.id == trip_id,
            TripAuthorization.school_id == school_id,
        )
    )
    trip = result.scalar_one_or_none()
    if trip is None:
        raise HTTPException(status_code=404, detail="Trip authorization not found")

    # Determine child_id: use the trip's stored child_id or find parent's first child
    child_id = trip.child_id
    if child_id is None:
        # Fallback: find any child linked to this guardian for this school
        link_result = await db.execute(
            select(ChildGuardian).where(ChildGuardian.guardian_id == guardian_id).limit(1)
        )
        link = link_result.scalar_one_or_none()
        if link is None:
            raise HTTPException(status_code=403, detail="You are not authorized for any child")
        child_id = link.child_id
    else:
        # Verify guardian is linked to the trip's child
        link_result = await db.execute(
            select(ChildGuardian).where(
                ChildGuardian.guardian_id == guardian_id,
                ChildGuardian.child_id == child_id,
            )
        )
        if link_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=403, detail="You are not authorized for this child")

    # Check for existing response (finality)
    existing = await _get_trip_response_for_child(db, trip_id, child_id)
    if existing is not None:
        raise HTTPException(status_code=409, detail="Response already submitted for this child")

    authorized = body.response == "approved"
    response = TripAuthorizationResponse(
        authorization_id=trip_id,
        school_id=school_id,
        child_id=child_id,
        guardian_id=guardian_id,
        authorized=authorized,
    )
    db.add(response)
    await db.commit()
    await db.refresh(response)

    return TripRespondOut(
        id=response.id,
        parent_response=body.response,
        response_date=response.responded_at,
    )


@router.delete("/{trip_id}", status_code=status.HTTP_200_OK)
async def delete_trip_authorization(
    trip_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(TripAuthorization).where(
            TripAuthorization.id == trip_id,
            TripAuthorization.school_id == school_id,
        )
    )
    trip = result.scalar_one_or_none()
    if trip is None:
        raise HTTPException(status_code=404, detail="Trip authorization not found")

    await db.delete(trip)
    await db.commit()
    return {"message": "Trip authorization cancelled"}
