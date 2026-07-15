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

    # Public website contact-form delivery. Gmail uses smtp.gmail.com:587 with
    # STARTTLS and an App Password (never the account's normal password).
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: str | None = None
    SMTP_FROM_EMAIL: str | None = None
    CONTACT_RECIPIENT_EMAIL: str | None = None

    model_config = SettingsConfigDict(env_file=".env")


settings = Settings()
