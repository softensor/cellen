"""Public website CMS and contact-form tests."""

from sqlalchemy import select

from app.models.website import WebsiteContactSubmission, WebsiteSetting


async def test_contact_submission_is_private_and_emailed(client, db, monkeypatch):
    delivered: dict[str, str | None] = {}

    async def fake_send(**kwargs):
        delivered.update(kwargs)

    monkeypatch.setattr(
        "app.services.email.send_contact_submission_email", fake_send
    )

    response = await client.post(
        "/api/v1/website/public/contact",
        json={
            "name": "Ana Silva",
            "school": "Creche Azul",
            "email": "ana@example.com",
            "phone": "+244 900 000 000",
            "message": "Gostaria de receber uma demonstração.",
        },
    )

    assert response.status_code == 200
    assert response.json()["success"] is True
    assert delivered["email"] == "ana@example.com"

    submission = (
        await db.execute(select(WebsiteContactSubmission))
    ).scalar_one()
    assert submission.delivery_status == "sent"
    assert submission.message == "Gostaria de receber uma demonstração."
    assert (await db.execute(select(WebsiteSetting))).scalars().all() == []
