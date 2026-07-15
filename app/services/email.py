"""Transactional email delivery for the public website."""

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Raised when an email cannot be delivered safely."""


async def send_contact_submission_email(
    *, name: str, school: str | None, email: str, phone: str | None, message: str
) -> None:
    """Send a contact-form submission through the configured SMTP provider."""
    await asyncio.to_thread(
        _send_contact_submission_email,
        name=name,
        school=school,
        email=email,
        phone=phone,
        message=message,
    )


def _send_contact_submission_email(
    *, name: str, school: str | None, email: str, phone: str | None, message: str
) -> None:
    username = settings.SMTP_USERNAME
    password = settings.SMTP_PASSWORD
    sender = settings.SMTP_FROM_EMAIL or username
    recipient = settings.CONTACT_RECIPIENT_EMAIL or settings.PLATFORM_ADMIN_EMAIL
    if not username or not password or not sender:
        raise EmailDeliveryError("Email delivery is not configured")

    msg = EmailMessage()
    msg["Subject"] = f"Novo contacto do website — {name}"
    msg["From"] = sender
    msg["To"] = recipient
    # Replying in Gmail goes directly to the prospective customer's email.
    msg["Reply-To"] = email
    msg.set_content(
        "Novo pedido de contacto recebido pelo website Cellen.\n\n"
        f"Nome: {name}\n"
        f"Escola: {school or '-'}\n"
        f"Email: {email}\n"
        f"Telefone: {phone or '-'}\n\n"
        f"Mensagem:\n{message}\n"
    )

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=20) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(username, password)
            smtp.send_message(msg)
    except (OSError, smtplib.SMTPException) as exc:
        logger.warning("Website contact email delivery failed: %s", exc)
        raise EmailDeliveryError("Unable to deliver email") from exc
