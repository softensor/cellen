import json
from pathlib import Path

from app.services.finreg import FinregError

_PATH = Path(__file__).with_name("finreg_school_manifest.json")
MANIFEST = json.loads(_PATH.read_text(encoding="utf-8"))


def validate_school_capabilities(payload: dict) -> dict:
    if payload.get("vertical") != MANIFEST["vertical"]:
        raise FinregError(
            "vertical_mismatch",
            f"Cellen requires Finreg profile {MANIFEST['vertical']}",
        )
    required = set(MANIFEST["required_capabilities"])
    configured = set(payload.get("configured_capabilities") or [])
    missing_configuration = required - configured
    if missing_configuration:
        raise FinregError(
            "capability_mismatch",
            "Finreg school profile is missing: "
            f"{', '.join(sorted(missing_configuration))}",
        )
    operational = set(payload.get("effective_capabilities") or [])
    commercially_blocked = required - operational
    if commercially_blocked:
        raise FinregError(
            "capability_entitlement_blocked",
            "Finreg plan blocks required school capabilities: "
            f"{', '.join(sorted(commercially_blocked))}",
        )
    fingerprint = payload.get("manifest_fingerprint")
    if not isinstance(fingerprint, str) or len(fingerprint) != 64:
        raise FinregError(
            "manifest_fingerprint_missing",
            "Finreg did not return a valid manifest fingerprint",
        )
    return payload
