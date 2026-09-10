"""Independent school-specific roles and their explicit access permissions."""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

STAFF_ROLES = {"school_admin", "coordinator", "finance_officer", "secretary", "teacher", "nurse", "staff"}

_LEGACY_PERMISSION = {
    "coordinator": "academic_coordination",
    "finance_officer": "finance",
    "secretary": "secretariat",
    "teacher": "teaching",
    "nurse": "health",
}

_PERMISSION_CLIENT_ROLE = {
    "school_administration": "school_admin",
    "academic_coordination": "coordinator",
    "finance": "finance_officer",
    "secretariat": "secretary",
    "teaching": "teacher",
    "staff_services": "secretary",
    "health": "nurse",
}


class CustomRole(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(pattern=r"^custom_[a-z0-9_]{1,64}$")
    label: str = Field(min_length=1, max_length=80)
    permissions: list[Literal[
        "school_administration",
        "academic_coordination",
        "finance",
        "secretariat",
        "teaching",
        "staff_services",
        "health",
    ]] = Field(max_length=7)
    enabled: bool = True

    @field_validator("label", mode="before")
    @classmethod
    def trim_label(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("permissions")
    @classmethod
    def unique_permissions(cls, value):
        if len(set(value)) != len(value):
            raise ValueError("As permissões da função não podem ser repetidas")
        return value


def custom_roles(features: dict | None) -> dict[str, dict]:
    return {role["key"]: role for role in (features or {}).get("custom_roles", []) or []}


def resolve_roles(roles: list[str], features: dict | None) -> list[str]:
    """Resolve current assignments without converting custom roles to built-ins."""
    definitions = custom_roles(features)
    resolved = []
    for role in roles:
        if role.startswith("custom_"):
            definition = definitions.get(role)
            if not definition or not definition.get("enabled", True):
                continue
        if role not in resolved:
            resolved.append(role)
    return resolved


def resolve_permissions(roles: list[str], features: dict | None) -> set[str]:
    """Return permissions explicitly granted by active custom-role definitions."""
    definitions = custom_roles(features)
    permissions: set[str] = set()
    for role in roles:
        definition = definitions.get(role)
        if definition and definition.get("enabled", True):
            explicit = definition.get("permissions")
            if isinstance(explicit, list):
                permissions.update(explicit)
            elif definition.get("base_role") in _LEGACY_PERMISSION:
                # Read compatibility for definitions saved by the first release.
                # The next platform-admin save writes the explicit format.
                permissions.add(_LEGACY_PERMISSION[definition["base_role"]])
    return permissions


def client_navigation_roles(roles: list[str], features: dict | None) -> list[str]:
    """Return legacy role hints for clients; these are never authorization input."""
    resolved = resolve_roles(roles, features)
    result = [role for role in resolved if not role.startswith("custom_")]
    for permission in sorted(resolve_permissions(roles, features)):
        role = _PERMISSION_CLIENT_ROLE[permission]
        if role not in result:
            result.append(role)
    return result


def validate_assignments(roles: list[str], features: dict | None, existing=()) -> list[str]:
    definitions = custom_roles(features)
    if not roles:
        raise ValueError("Seleccione pelo menos uma função.")
    for role in roles:
        if role in STAFF_ROLES:
            available = role == "school_admin" or (features or {}).get(f"role_{role}") is not False
        else:
            definition = definitions.get(role)
            available = bool(definition and definition.get("enabled", True))
        if not available and role not in existing:
            raise ValueError("Função desconhecida ou indisponível nesta escola: " + role)
    return list(dict.fromkeys(roles))
