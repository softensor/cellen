"""Run without a database: python -m unittest tests.test_custom_roles_unit."""
import unittest

from pydantic import ValidationError

from app.core.custom_roles import (
    client_navigation_roles,
    definition_permissions,
    resolve_permissions,
    resolve_roles,
    validate_assignments,
)
from app.schemas.school import SchoolUpdate
from app.schemas.employee import EmployeeUpdate


def definition(**overrides):
    return {"key": "custom_reception", "label": "Recepção",
            "permissions": ["people", "messages"],
            "enabled": True, **overrides}


class CustomRoleTests(unittest.TestCase):
    def test_round_trip_preserves_other_school_settings(self):
        features = {"custom_roles": [definition(label=" Recepção ")],
                    "finance": False, "integration": {"enabled": True}}
        saved = SchoolUpdate(features=features).model_dump()["features"]
        self.assertEqual(saved["custom_roles"][0]["label"], "Recepção")
        self.assertEqual(saved["integration"], features["integration"])
        self.assertFalse(saved["finance"])

    def test_invalid_definitions_are_rejected(self):
        for changes in ({"key": "school_admin"}, {"label": "  "},
                        {"permissions": ["platform_admin"]},
                        {"permissions": ["people", "people"]},
                        {"permissions": ["invented"]}, {"label": "x" * 81}):
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                SchoolUpdate(features={"custom_roles": [definition(**changes)]})

    def test_duplicate_keys_and_names_are_rejected(self):
        for extra in (definition(label="Other"),
                      definition(key="custom_other", label="RECEPÇÃO")):
            with self.subTest(extra=extra), self.assertRaises(ValidationError):
                SchoolUpdate(features={"custom_roles": [definition(), extra]})

    def test_custom_roles_must_be_a_bounded_list(self):
        for value in (None, {}, "test", [definition()] * 51):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                SchoolUpdate(features={"custom_roles": value})

    def test_custom_roles_keep_their_identity_and_explicit_permissions(self):
        features = {"custom_roles": [definition()]}
        self.assertEqual(resolve_roles(["custom_reception", "teacher", "secretary"], features),
                         ["custom_reception", "teacher", "secretary"])
        self.assertEqual(resolve_permissions(["custom_reception"], features),
                         {"people", "messages"})
        self.assertEqual(client_navigation_roles(["custom_reception"], features),
                         ["custom_reception"])

    def test_legacy_definition_is_read_as_an_explicit_permission(self):
        features = {"custom_roles": [{"key": "custom_old", "label": "Antiga",
                    "base_role": "teacher", "enabled": True}]}
        self.assertEqual(resolve_roles(["custom_old"], features), ["custom_old"])
        permissions = resolve_permissions(["custom_old"], features)
        self.assertIn("checkin", permissions)
        self.assertIn("grades", permissions)
        self.assertNotIn("teaching", permissions)

    def test_disabled_deleted_and_cross_school_roles_grant_no_access(self):
        for features in ({}, {"custom_roles": [definition(enabled=False)]}):
            with self.subTest(features=features):
                self.assertEqual(resolve_roles(["custom_reception"], features), [])
                with self.assertRaises(ValueError):
                    validate_assignments(["custom_reception"], features)

    def test_disabled_definition_keeps_its_configured_permissions(self):
        self.assertEqual(
            definition_permissions(definition(enabled=False)),
            {"people", "messages"},
        )

    def test_other_assignments_survive_disabled_custom_role(self):
        self.assertEqual(resolve_roles(["custom_reception", "teacher"], {}), ["teacher"])

    def test_invalid_account_roles_cannot_be_assigned_to_staff(self):
        for roles in ([], ["platform_admin"], ["parent"], ["invented"]):
            with self.subTest(roles=roles), self.assertRaises(ValueError):
                validate_assignments(roles, {})

    def test_assignments_are_deduplicated(self):
        self.assertEqual(validate_assignments(["teacher", "teacher"], {}), ["teacher"])

    def test_disabled_assignment_can_be_preserved_when_editing(self):
        self.assertEqual(validate_assignments(["custom_reception"], {}, ["custom_reception"]),
                         ["custom_reception"])
        self.assertEqual(resolve_roles(["custom_reception"], {}), [])

    def test_existing_employees_accept_updated_roles(self):
        update = EmployeeUpdate(roles=["custom_reception", "teacher"])
        self.assertEqual(update.model_dump(exclude_unset=True),
                         {"roles": ["custom_reception", "teacher"]})
