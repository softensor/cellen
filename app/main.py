from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.routers import (
    auth,
    platform,
    schools,
    children,
    guardians,
    employees,
    academic,
    caderneta,
    food,
    absences,
    finance,
    attendance,
    messages,
    photos,
    incidents,
    events,
    notifications,
    parent,
    announcements,
    documents_library,
    appointments,
    evaluations,
    health_events,
    immunizations,
    trip_authorizations,
    pickup_authorizations,
    website,
    reports,
    grades,
    timetable,
    lesson_attendance,
)

app = FastAPI(
    title="Cellen API",
    version="1.0.0",
    description="Multi-tenant SaaS childcare management system",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://jorgehel.github.io",  # Flutter web & website (GitHub Pages)
        "https://softensor.github.io",
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:8080",
        "https://cellen.ao",
        "https://www.cellen.ao",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
    max_age=600,
)

# Include all routers under /api/v1 prefix
app.include_router(auth.router, prefix="/api/v1")
app.include_router(platform.router, prefix="/api/v1")
app.include_router(schools.router, prefix="/api/v1")
app.include_router(children.router, prefix="/api/v1")
app.include_router(guardians.router, prefix="/api/v1")
app.include_router(employees.router, prefix="/api/v1")
app.include_router(academic.router, prefix="/api/v1")
app.include_router(caderneta.router, prefix="/api/v1")
app.include_router(food.router, prefix="/api/v1")
app.include_router(absences.router, prefix="/api/v1")
app.include_router(finance.router, prefix="/api/v1")
app.include_router(attendance.router, prefix="/api/v1")
app.include_router(messages.router, prefix="/api/v1")
app.include_router(photos.router, prefix="/api/v1")
app.include_router(incidents.router, prefix="/api/v1")
app.include_router(events.router, prefix="/api/v1")
app.include_router(notifications.router, prefix="/api/v1")
app.include_router(parent.router, prefix="/api/v1")
app.include_router(announcements.router, prefix="/api/v1")
app.include_router(documents_library.router, prefix="/api/v1")
app.include_router(appointments.router, prefix="/api/v1")
app.include_router(evaluations.router, prefix="/api/v1")
app.include_router(health_events.router, prefix="/api/v1")
app.include_router(immunizations.router, prefix="/api/v1")
app.include_router(trip_authorizations.router, prefix="/api/v1")
app.include_router(pickup_authorizations.router, prefix="/api/v1")
app.include_router(website.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(grades.router, prefix="/api/v1")
app.include_router(timetable.router, prefix="/api/v1")
app.include_router(lesson_attendance.router, prefix="/api/v1")

# Ensure media directory exists and mount static files
_media_path = Path(settings.MEDIA_DIR)
_media_path.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(_media_path)), name="media")


@app.on_event("startup")
async def startup_event():
    import asyncio
    from app.services.scheduled_tasks import run_scheduled_tasks

    # Create platform admin if not exists
    await _seed_platform_admin()

    # Launch daily scheduled tasks (overdue invoices, expire references)
    asyncio.create_task(run_scheduled_tasks())


async def _seed_platform_admin():
    from sqlalchemy import select

    from app.core.database import AsyncSessionLocal
    from app.core.security import hash_password
    from app.models.school import PlatformUser

    async with AsyncSessionLocal() as db:
        try:
            result = await db.execute(
                select(PlatformUser).where(PlatformUser.email == settings.PLATFORM_ADMIN_EMAIL)
            )
            if result.scalar_one_or_none() is None:
                admin = PlatformUser(
                    email=settings.PLATFORM_ADMIN_EMAIL,
                    password_hash=hash_password(settings.PLATFORM_ADMIN_PASSWORD),
                    is_active=True,
                )
                db.add(admin)
                await db.commit()
        except Exception:
            # DB might not be ready at startup — skip silently
            pass


@app.get("/health")
async def health():
    return {"status": "ok", "service": "cellen-api", "version": "1.0.0"}
