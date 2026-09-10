"""Independent school-specific roles and their explicit function permissions."""

from pydantic import BaseModel, ConfigDict, Field, field_validator

STAFF_ROLES = {
    "school_admin", "coordinator", "finance_officer", "secretary",
    "teacher", "nurse", "staff",
}

CUSTOM_PERMISSIONS = {
    "people", "academic", "checkin", "caderneta", "evaluations",
    "activities", "timetable_k12", "lesson_attendance", "grades",
    "subjects", "report_cards", "appointments", "absences", "health",
    "immunizations", "med_report", "incidents", "meal_orders", "trip_auth",
    "pickup_auth", "photos", "events", "documents", "announcements",
    "messages", "finance", "reports", "school_settings",
}

_AREA_PERMISSIONS = {
    "school_administration": CUSTOM_PERMISSIONS,
    "academic_coordination": {
        "academic", "checkin", "caderneta", "evaluations", "activities",
        "timetable_k12", "lesson_attendance", "grades", "subjects",
        "report_cards", "appointments", "absences", "reports",
    },
    "finance": {"finance"},
    "secretariat": {
        "people", "academic", "appointments", "absences", "events",
        "documents", "announcements", "messages",
    },
    "teaching": {
        "academic", "checkin", "caderneta", "evaluations", "activities",
        "timetable_k12", "lesson_attendance", "grades", "appointments",
    },
    "staff_services": {
        "appointments", "meal_orders", "photos", "events", "documents",
        "announcements", "messages",
    },
}

_LEGACY_PERMISSION = {
    "coordinator": "academic_coordination",
    "finance_officer": "finance",
    "secretary": "secretariat",
    "teacher": "teaching",
    "nurse": "health",
}

def _expand_permissions(values) -> list[str]:
    expanded: list[str] = []
    for value in values or []:
        for permission in sorted(_AREA_PERMISSIONS.get(value, {value})):
            if permission not in expanded:
                expanded.append(permission)
    return expanded


class CustomRole(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(pattern=r"^custom_[a-z0-9_]{1,64}$")
    label: str = Field(min_length=1, max_length=80)
    permissions: list[str] = Field(max_length=len(CUSTOM_PERMISSIONS))
    enabled: bool = True

    @field_validator("label", mode="before")
    @classmethod
    def trim_label(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("permissions", mode="before")
    @classmethod
    def valid_permissions(cls, value):
        if not isinstance(value, list):
            raise ValueError("permissions deve ser uma lista")
        if len(value) != len(set(value)):
            raise ValueError("As permissões da função não podem ser repetidas")
        expanded = _expand_permissions(value)
        unknown = set(expanded) - CUSTOM_PERMISSIONS
        if unknown:
            raise ValueError("Permissão desconhecida: " + sorted(unknown)[0])
        return expanded


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
    """Return function permissions granted by active custom-role definitions."""
    definitions = custom_roles(features)
    permissions: set[str] = set()
    for role in roles:
        definition = definitions.get(role)
        if not definition or not definition.get("enabled", True):
            continue
        explicit = definition.get("permissions")
        if isinstance(explicit, list):
            permissions.update(_expand_permissions(explicit))
        elif definition.get("base_role") in _LEGACY_PERMISSION:
            legacy = _LEGACY_PERMISSION[definition["base_role"]]
            permissions.update(_AREA_PERMISSIONS.get(legacy, {legacy}))
    return permissions


def client_navigation_roles(roles: list[str], features: dict | None) -> list[str]:
    """Return assigned identities without translating custom roles to built-in roles."""
    return resolve_roles(roles, features)


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
