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
    actual = set(payload.get("effective_capabilities") or [])
    required = set(MANIFEST["required_capabilities"])
    missing = required - actual
    if missing:
        raise FinregError(
            "capability_mismatch",
            f"Finreg school profile is missing: {', '.join(sorted(missing))}",
        )
    fingerprint = payload.get("manifest_fingerprint")
    if not isinstance(fingerprint, str) or len(fingerprint) != 64:
        raise FinregError(
            "manifest_fingerprint_missing",
            "Finreg did not return a valid manifest fingerprint",
        )
    return payload
