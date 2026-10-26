from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    MEDIA_DIR: str = "./media"
    PLATFORM_ADMIN_EMAIL: str
    PLATFORM_ADMIN_PASSWORD: str

    # Finreg is the sole issuer for schools explicitly placed in pilot/live.
    # Credentials remain server-side and are never returned to Flutter.
    # FINREG_BASE_URL is the FinReg ORIGIN (no /api/v1): the connector kit
    # appends /api/v1/integrations itself.
    FINREG_BASE_URL: str = "http://localhost:8001"
    FINREG_WEB_URL: str | None = None
    FINREG_CLIENT_ID: str | None = None
    FINREG_CLIENT_SECRET: str | None = None
    FINREG_CLIENT_SECRET_FILE: str | None = None
    FINREG_TIMEOUT_SECONDS: float = 15.0
    FINREG_VERIFY_TLS: bool = True
    FINREG_TLS_CA_FILE: str | None = None
    FINREG_INTEGRATION_ENABLED: bool = False

    # Public Cellen address. FinReg offers it as the "back to Cellen" link on
    # delegated sessions; unset, launches simply carry no return target.
    CELLEN_WEB_URL: str | None = None

    # Public website contact-form delivery. Gmail uses smtp.gmail.com:587 with
    # STARTTLS and an App Password (never the account's normal password).
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_FROM_EMAIL: str | None = None
    CONTACT_RECIPIENT_EMAIL: str | None = None

    # WhatsApp Cloud API (Meta Business) — platform-level defaults
    # Schools can override per-school via wa_phone_number_id / wa_access_token on their record
    WHATSAPP_PHONE_NUMBER_ID: str | None = None
    WHATSAPP_ACCESS_TOKEN: str | None = None

    model_config = SettingsConfigDict(env_file=".env")

    @property
    def finreg_origin(self) -> str:
        """FinReg origin, tolerating the pre-kit env form with ``/api/v1``."""
        base = (self.FINREG_BASE_URL or "").strip().rstrip("/")
        if base.endswith("/api/v1"):
            base = base[: -len("/api/v1")]
        return base


settings = Settings()
