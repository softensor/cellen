"""FinReg failures as HTTP answers a school can act on."""
from __future__ import annotations

from fastapi import HTTPException

from app.services.finreg import FinregError


def http_error(exc: FinregError) -> HTTPException:
    status = 503 if exc.retryable or exc.unknown_outcome else 422
    return HTTPException(status_code=status, detail={"code": exc.code, "message": exc.detail})
