"""The rollout check ledgers what the outbox confirmed and flags trouble."""
import uuid

from sqlalchemy import text

from app.models.finreg_integration import FinregBillingInstruction
from app.scripts import headless_invoicing_check
from tests.test_finreg_ledger import _document, _draft_instruction, _school_with_family


async def test_the_check_backfills_and_gates_on_rejections(db, make_school, monkeypatch, capsys):
    school_id, _, guardian, child = await _school_with_family(db, make_school)
    slug = (await db.execute(
        text("select slug from schools where id = :id"), {"id": school_id}
    )).scalar_one()
    good = uuid.uuid4()
    db.add(_draft_instruction(school_id, guardian, child, document_id=good,
                              snapshot=_document(good, agt_status="accepted")))
    await db.commit()

    class _Session:
        async def __aenter__(self):
            return db

        async def __aexit__(self, *exc):
            return False

    monkeypatch.setattr(headless_invoicing_check, "AsyncSessionLocal", _Session)
    assert await headless_invoicing_check.main(["--school", slug]) == 0
    out = capsys.readouterr().out
    assert "documents=1 (issued=1)" in out
    assert "backfilled_now=1 unledgered=0" in out

    db.add(FinregBillingInstruction(
        school_id=school_id, idempotency_key=f"x-{uuid.uuid4()}", command_type="issue_invoice",
        status="rejected", error_code="http_422", error_detail="nope", payload={},
    ))
    await db.commit()
    assert await headless_invoicing_check.main(["--school", slug]) == 1
    assert await headless_invoicing_check.main(["--school", "no-such-school"]) == 2
