"""Database-free regression tests for live custom-role authorization."""
import unittest
import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

from fastapi import HTTPException
from app.core.dependencies import (
    get_current_user,
    require_finance_access,
    require_secretary,
    require_teacher,
)
from app.core.security import decode_token
from app.routers.auth import refresh_token
from app.schemas.auth import RefreshRequest


class CustomRoleAuthTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.user_id = uuid.uuid4()
        self.school_id = uuid.uuid4()
        self.user = SimpleNamespace(id=self.user_id, school_id=self.school_id,
            is_active=True, roles=["custom_reception"], employee_id=None, guardian_id=None)
        self.features = {"custom_roles": [{"key": "custom_reception", "label": "Recepção",
            "permissions": ["secretariat", "staff_services"], "enabled": True}]}
        self.school = SimpleNamespace(id=self.school_id, is_active=True, resolved_features=self.features)
        self.payload = {"type": "access", "sub": str(self.user_id),
                        "roles": ["teacher"], "school_id": str(self.school_id)}
        self.db = AsyncMock()
        self.db.execute.return_value = Mock(scalar_one_or_none=Mock(return_value=self.user))
        self.db.get.return_value = self.school

    async def test_existing_token_uses_current_independent_permissions(self):
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            actor = await get_current_user("old-token", self.db)
        self.assertEqual(actor._roles, {"custom_reception"})
        self.assertEqual(actor._role, "custom_reception")
        self.assertEqual(actor._custom_permissions, {"secretariat", "staff_services"})

    async def test_disabling_role_revokes_existing_token_access(self):
        self.features["custom_roles"][0]["enabled"] = False
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            with self.assertRaises(HTTPException) as error:
                await get_current_user("old-token", self.db)
        self.assertEqual(error.exception.status_code, 403)

    async def test_only_explicit_permissions_authorize_custom_role(self):
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            actor = await get_current_user("old-token", self.db)
        self.assertIs(await require_secretary(actor), actor)
        for guard in (require_teacher, require_finance_access):
            with self.subTest(guard=guard.__name__), self.assertRaises(HTTPException) as error:
                await guard(actor)
            self.assertEqual(error.exception.status_code, 403)

    async def test_permission_changes_apply_to_existing_token(self):
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            actor = await get_current_user("old-token", self.db)
        self.features["custom_roles"][0]["permissions"] = ["teaching"]
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            actor = await get_current_user("old-token", self.db)
        self.assertIs(await require_teacher(actor), actor)
        with self.assertRaises(HTTPException):
            await require_secretary(actor)

    async def test_finance_permission_obeys_school_feature_switch(self):
        self.features["custom_roles"][0]["permissions"] = ["finance"]
        self.features["finance"] = False
        with patch("app.core.dependencies.decode_token", return_value=self.payload):
            actor = await get_current_user("old-token", self.db)
        with self.assertRaises(HTTPException) as error:
            await require_finance_access(actor)
        self.assertEqual(error.exception.status_code, 403)

    async def test_refresh_uses_current_profile(self):
        self.payload["type"] = "refresh"
        self.db.get.side_effect = [self.user, self.school]
        with patch("app.routers.auth.decode_token", return_value=self.payload):
            response = await refresh_token(RefreshRequest(refresh_token="old-token"), self.db)
        claims = decode_token(response["access_token"])
        self.assertEqual(claims["roles"], ["secretary"])
        self.assertEqual(claims["permissions"], ["secretariat", "staff_services"])

    async def test_refresh_rejects_disabled_role(self):
        self.payload["type"] = "refresh"
        self.features["custom_roles"][0]["enabled"] = False
        self.db.get.side_effect = [self.user, self.school]
        with patch("app.routers.auth.decode_token", return_value=self.payload):
            with self.assertRaises(HTTPException) as error:
                await refresh_token(RefreshRequest(refresh_token="old-token"), self.db)
        self.assertEqual(error.exception.status_code, 403)

    async def test_access_rejects_invalid_school_context(self):
        for school in (None,
                       SimpleNamespace(id=self.school_id, is_active=False),
                       SimpleNamespace(id=uuid.uuid4(), is_active=True)):
            with self.subTest(school=school):
                self.db.get.return_value = school
                with patch("app.core.dependencies.decode_token", return_value=self.payload):
                    with self.assertRaises(HTTPException) as error:
                        await get_current_user("old-token", self.db)
                self.assertEqual(error.exception.status_code, 401)
