"""School-specific role names backed by existing staff access profiles."""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

STAFF_ROLES = {"school_admin", "coordinator", "finance_officer", "secretary", "teacher", "nurse", "staff"}


class CustomRole(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(pattern=r"^custom_[a-z0-9_]{1,64}$")
    label: str = Field(min_length=1, max_length=80)
    base_role: Literal["coordinator", "finance_officer", "secretary", "teacher", "nurse"]
    enabled: bool = True

    @field_validator("label", mode="before")
    @classmethod
    def trim_label(cls, value):
        return value.strip() if isinstance(value, str) else value


def custom_roles(features: dict | None) -> dict[str, dict]:
    return {role["key"]: role for role in (features or {}).get("custom_roles", []) or []}


def resolve_roles(roles: list[str], features: dict | None) -> list[str]:
    """Resolve current assignments; disabled/deleted custom roles grant no access."""
    definitions = custom_roles(features)
    resolved = []
    for role in roles:
        if role.startswith("custom_"):
            definition = definitions.get(role)
            if not definition or not definition.get("enabled", True):
                continue
            role = definition["base_role"]
            if (features or {}).get(f"role_{role}") is False:
                continue
        if role not in resolved:
            resolved.append(role)
    return resolved


def validate_assignments(roles: list[str], features: dict | None, existing=()) -> list[str]:
    definitions = custom_roles(features)
    if not roles:
        raise ValueError("Seleccione pelo menos uma função.")
    for role in roles:
        if role in STAFF_ROLES:
            available = role == "school_admin" or (features or {}).get(f"role_{role}") is not False
        else:
            definition = definitions.get(role)
            available = bool(definition and definition.get("enabled", True) and
                             (features or {}).get(f"role_{definition['base_role']}") is not False)
        if not available and role not in existing:
            raise ValueError("Função desconhecida ou indisponível nesta escola: " + role)
    return list(dict.fromkeys(roles))
