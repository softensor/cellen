"""
Tenant middleware — not needed as a starlette middleware layer since
tenant isolation is enforced at the dependency injection level (get_school_id).
This module is reserved for future request-level tenant logging or rate limiting.
"""
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


class TenantContextMiddleware(BaseHTTPMiddleware):
    """Logs school_id context for observability (non-blocking)."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        return response
