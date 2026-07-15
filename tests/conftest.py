"""
Shared pytest fixtures for the Cellen API test suite.

DATABASE SETUP
--------------
Tests run against a dedicated PostgreSQL database.  Set the environment variable
TEST_DATABASE_URL (or DATABASE_URL) before running, e.g.:

    TEST_DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost/cellen_test pytest

ISOLATION STRATEGY
------------------
Table creation is done once per session via asyncio.run() in a plain sync fixture
(setup_database).  This avoids sharing asyncpg connections across event loops,
which would trigger "Future attached to a different loop" errors with
pytest-asyncio's per-test loop model.

Each test function gets its own AsyncSession backed by a fresh engine, so there
is no cross-loop connection sharing.

Tests that write data use unique slugs / usernames (uuid-based) so they don't
collide with other tests that run in the same DB.
"""
import asyncio
import os
import uuid

# ── MUST come before any app imports so settings pick up the test DB ──────────
_TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    os.environ.get(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/cellen_test",
    ),
)
os.environ["DATABASE_URL"] = _TEST_DB_URL
# ─────────────────────────────────────────────────────────────────────────────

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

# Register every model with Base.metadata before create_all is called
from app.models.base import Base  # noqa: F401
import app.models.absence  # noqa: F401
import app.models.academic  # noqa: F401
import app.models.billing_item  # noqa: F401
import app.models.caderneta  # noqa: F401
import app.models.employee  # noqa: F401
import app.models.finance  # noqa: F401
import app.models.food  # noqa: F401
import app.models.immunization  # noqa: F401
import app.models.modern  # noqa: F401
import app.models.person  # noqa: F401
import app.models.pickup_auth  # noqa: F401
import app.models.school  # noqa: F401
import app.models.trip_authorization  # noqa: F401
import app.models.user  # noqa: F401
import app.models.website  # noqa: F401

from app.core.config import settings
from app.core.database import get_db
from app.core.security import hash_password
from app.main import app as fastapi_app


# ──────────────────────────────────────────────────────────────────────────────
# Session-scoped setup: drop + create all tables + seed platform admin.
# Uses asyncio.run() so no asyncpg connections bleed into pytest's event loops.
# ──────────────────────────────────────────────────────────────────────────────
@pytest.fixture(scope="session", autouse=True)
def setup_database():
    """Drop, recreate all tables, and seed the platform admin before any test."""

    async def _setup() -> None:
        from sqlalchemy import text
        from app.models.school import PlatformUser

        eng = create_async_engine(_TEST_DB_URL, echo=False)
        async with eng.begin() as conn:
            # Drop and recreate schema to handle leftover tables from schema changes
            await conn.execute(text("DROP SCHEMA public CASCADE"))
            await conn.execute(text("CREATE SCHEMA public"))
            await conn.execute(text("GRANT ALL ON SCHEMA public TO PUBLIC"))
            await conn.run_sync(Base.metadata.create_all)

        factory = async_sessionmaker(eng, expire_on_commit=False)
        async with factory() as sess:
            result = await sess.execute(
                select(PlatformUser).where(
                    PlatformUser.email == settings.PLATFORM_ADMIN_EMAIL
                )
            )
            if result.scalar_one_or_none() is None:
                sess.add(
                    PlatformUser(
                        email=settings.PLATFORM_ADMIN_EMAIL,
                        password_hash=hash_password(settings.PLATFORM_ADMIN_PASSWORD),
                    )
                )
                await sess.commit()

        await eng.dispose()

    asyncio.run(_setup())
    yield

    async def _teardown() -> None:
        eng = create_async_engine(_TEST_DB_URL, echo=False)
        async with eng.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
        await eng.dispose()

    asyncio.run(_teardown())


# ──────────────────────────────────────────────────────────────────────────────
# Per-test DB session — fresh engine each time to stay within the test's loop.
# ──────────────────────────────────────────────────────────────────────────────
@pytest_asyncio.fixture
async def db() -> AsyncSession:  # type: ignore[override]
    eng = create_async_engine(_TEST_DB_URL, echo=False)
    factory = async_sessionmaker(eng, expire_on_commit=False)
    async with factory() as session:
        yield session
    await eng.dispose()


# ──────────────────────────────────────────────────────────────────────────────
# HTTP client with DB override
# ──────────────────────────────────────────────────────────────────────────────
@pytest_asyncio.fixture
async def client(db: AsyncSession) -> AsyncClient:
    async def _get_db():
        yield db

    fastapi_app.dependency_overrides[get_db] = _get_db
    async with AsyncClient(
        transport=ASGITransport(app=fastapi_app),
        base_url="http://test/api/v1",
    ) as ac:
        yield ac
    fastapi_app.dependency_overrides.clear()


# ──────────────────────────────────────────────────────────────────────────────
# Helpers (not fixtures — plain async functions)
# ──────────────────────────────────────────────────────────────────────────────
async def login(ac: AsyncClient, username: str, password: str, school_slug: str | None = None) -> str:
    """Login and return the access token."""
    body: dict = {"username": username, "password": password}
    if school_slug:
        body["school_slug"] = school_slug
    r = await ac.post("/auth/login", json=body)
    assert r.status_code == 200, f"Login failed: {r.text}"
    return r.json()["access_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def uid() -> str:
    return uuid.uuid4().hex[:8]


# ──────────────────────────────────────────────────────────────────────────────
# Platform-admin token
# ──────────────────────────────────────────────────────────────────────────────
@pytest_asyncio.fixture
async def padmin_token(client: AsyncClient) -> str:
    """Token for the seeded platform admin account."""
    return await login(client, settings.PLATFORM_ADMIN_EMAIL, settings.PLATFORM_ADMIN_PASSWORD)


# ──────────────────────────────────────────────────────────────────────────────
# School + school-admin factory
# ──────────────────────────────────────────────────────────────────────────────
@pytest_asyncio.fixture
async def make_school(client: AsyncClient, padmin_token: str):
    """
    Returns an async callable that creates a school via the API and returns:
        (school_dict, admin_access_token, slug, admin_username)
    """
    created: list[str] = []

    async def _factory(prefix: str = "sch"):
        slug = f"{prefix}-{uid()}"
        username = f"adm-{uid()}"
        r = await client.post(
            "/platform/schools",
            json={
                "name": f"Escola {slug}",
                "slug": slug,
                "admin_username": username,
                "admin_password": "Pass1234!",
            },
            headers=auth(padmin_token),
        )
        assert r.status_code == 201, r.text
        school = r.json()
        token = await login(client, username, "Pass1234!", slug)
        created.append(slug)
        return school, token, slug, username

    return _factory


# ──────────────────────────────────────────────────────────────────────────────
# Convenience: a ready-made school + employee (teacher) + parent/guardian setup
# ──────────────────────────────────────────────────────────────────────────────
@pytest_asyncio.fixture
async def school_ctx(client: AsyncClient, make_school):
    """
    Creates a fully populated test school and returns a dict with:
        school, admin_token, slug,
        employee_id, teacher_token,
        child_id,
        guardian_id, parent_token
    """
    school, admin_tok, slug, _adm = await make_school("ctx")
    hdrs = auth(admin_tok)

    # Create employee (teacher)
    emp_r = await client.post(
        "/employees",
        json={
            "first_name": "Ana",
            "last_name": "Silva",
            "employee_type": "teacher",
            "username": f"teacher-{uid()}",
            "password": "Teacher1!",
        },
        headers=hdrs,
    )
    assert emp_r.status_code == 201, emp_r.text
    emp = emp_r.json()
    teacher_tok = await login(client, emp["username"] if "username" in emp else f"teacher-{uid()}", "Teacher1!", slug)

    # Create child
    child_r = await client.post(
        "/children",
        json={"cedula": f"CDL{uid()}", "first_name": "Pedro", "last_name": "Costa"},
        headers=hdrs,
    )
    assert child_r.status_code == 201, child_r.text
    child = child_r.json()

    # Create guardian
    grd_r = await client.post(
        "/guardians",
        json={
            "first_name": "Maria",
            "last_name": "Costa",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=hdrs,
    )
    assert grd_r.status_code == 201, grd_r.text
    grd = grd_r.json()

    # Link guardian to child
    await client.post(
        f"/guardians/{grd['id']}/children",
        json={"child_id": child["id"], "relationship_type": "mother", "is_primary_contact": True},
        headers=hdrs,
    )

    parent_tok = await login(client, grd.get("username", f"parent-{uid()}"), "Parent1!", slug)

    return {
        "school": school,
        "admin_token": admin_tok,
        "slug": slug,
        "employee_id": emp["id"],
        "teacher_token": teacher_tok,
        "child_id": child["id"],
        "guardian_id": grd["id"],
        "parent_token": parent_tok,
    }
