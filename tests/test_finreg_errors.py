"""FinReg failures reach the school in its own words, never FinReg's."""
import uuid

from app.services.finreg import FinregError
from app.services.finreg_errors import explain, explain_stored, http_error
from app.models.finreg_integration import FinregBillingInstruction
from tests.conftest import auth
from tests.test_finreg_ledger import _document, _draft_instruction, _school_with_family


def test_a_missing_nif_names_the_fix():
    explanation = explain(FinregError("http_422", "Tax identification number is missing for: Maria"))
    assert explanation.code == "guardian_nif_missing"
    assert "NIF" in explanation.message
    assert explanation.action == "edit_guardian"


def test_an_unknown_outcome_is_never_presented_as_a_failure():
    explanation = explain(FinregError("http_504", "Gateway Timeout", retryable=True, unknown_outcome=True))
    assert explanation.code == "fiscal_pending_confirmation"
    assert "não é preciso repetir" in explanation.message


def test_unavailable_and_unmapped_rejections_have_safe_defaults():
    assert explain(FinregError("timeout", "connection reset", retryable=True)).code == "fiscal_unavailable"
    rejected = explain(FinregError("http_422", "Something FinReg-specific happened"))
    assert rejected.code == "fiscal_rejected"
    assert "FinReg" not in rejected.message


def test_no_explanation_mentions_finreg_or_english():
    samples = [
        FinregError("http_404", "Document mapping not found"),
        FinregError("http_409", "Billing plan is paused; resume it before running"),
        FinregError("http_400", "Document already cancelled"),
        FinregError("http_403", "Fiscal corrections are disabled for this integration client"),
        FinregError("capability_entitlement_blocked", "Finreg plan blocks required school capabilities"),
        FinregError("not_configured", "FINREG_CLIENT_ID is not set"),
    ]
    for error in samples:
        message = explain(error).message
        assert "finreg" not in message.lower(), message
        assert " not " not in message and "mapping" not in message.lower(), message


def test_http_error_keeps_the_raw_code_for_support():
    error = http_error(FinregError("http_422", "Tax exemption reason is required for a zero tax rate"))
    assert error.status_code == 422
    assert error.detail["code"] == "tax_exemption_missing"
    assert error.detail["finreg_code"] == "http_422"
    assert error.detail["action"] == "edit_billing_item"
    assert http_error(FinregError("x", "y", retryable=True)).status_code == 503


def test_stored_errors_are_translated():
    assert explain_stored(None, None) is None
    assert "NIF" in explain_stored("http_422", "Tax identification number is missing for: X", status="rejected")
    assert explain_stored("dispatch_exception", "KeyError: 'id'", status="pending") .startswith("O sistema fiscal está")


async def test_activity_and_attention_speak_school_language(client, db, make_school):
    school_id, token, guardian, child = await _school_with_family(db, make_school)
    rejected_doc = uuid.uuid4()
    db.add(_draft_instruction(
        school_id, guardian, child, document_id=rejected_doc,
        snapshot=_document(rejected_doc, agt_status="rejected"),
    ))
    failed = FinregBillingInstruction(
        school_id=school_id,
        idempotency_key=f"cellen-sales-{uuid.uuid4()}",
        command_type="issue_invoice",
        status="rejected",
        error_code="http_422",
        error_detail="Tax identification number is missing for: Maria",
        payload={"guardian": {"external_id": str(guardian.id)}},
    )
    db.add(failed)
    await db.commit()

    # Ledger the documents first, as the screen's first visit does.
    await client.get("/finreg/admin/documents", headers=auth(token))
    attention = (await client.get("/finreg/admin/attention", headers=auth(token))).json()
    assert attention == {"rejected_documents": 1, "pending_documents": 0, "failed_operations": 1}

    activity = (await client.get("/finreg/admin/activity?status=rejected", headers=auth(token))).json()
    item = activity["items"][0]
    assert item["error_detail"].startswith("Falta o NIF do encarregado")
    assert item["support_detail"] == "Tax identification number is missing for: Maria"
    assert item["can_retry"] is True
