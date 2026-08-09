import pytest

from app.integrations.finreg_school import MANIFEST, validate_school_capabilities
from app.services.finreg import FinregError


def valid_payload():
    return {
        "vertical": "school",
        "configured_capabilities": MANIFEST["required_capabilities"],
        "effective_capabilities": MANIFEST["required_capabilities"],
        "blocked_capabilities": {},
        "manifest_fingerprint": "a" * 64,
    }


def test_school_adapter_accepts_required_finreg_shape():
    assert validate_school_capabilities(valid_payload())["vertical"] == "school"


def test_school_adapter_rejects_retail_profile():
    payload = valid_payload() | {"vertical": "retail"}
    with pytest.raises(FinregError, match="requires Finreg profile school"):
        validate_school_capabilities(payload)


def test_school_adapter_rejects_missing_financial_capability():
    payload = valid_payload()
    payload["configured_capabilities"] = ["billing"]
    payload["effective_capabilities"] = ["billing"]
    with pytest.raises(FinregError, match="profile is missing"):
        validate_school_capabilities(payload)


def test_school_adapter_rejects_commercially_blocked_capability():
    payload = valid_payload()
    payload["effective_capabilities"] = ["billing"]
    with pytest.raises(FinregError, match="plan blocks"):
        validate_school_capabilities(payload)
