"""FinReg failures in words a school can act on.

FinReg answers in English and in its own vocabulary ("Document mapping not
found", "http_409"). The school never sees FinReg, so it must never read
FinReg either: every error that reaches a Cellen screen goes through
``explain`` first. The original code and detail stay in the instruction row
and the logs for support; only the message shown changes.
"""
from __future__ import annotations

from dataclasses import dataclass

from fastapi import HTTPException

from app.services.finreg import FinregError

PROCESSING_MESSAGE = (
    "O sistema fiscal ainda não confirmou esta operação. Será confirmada "
    "automaticamente; não é preciso repetir."
)
UNAVAILABLE_MESSAGE = (
    "O sistema fiscal está temporariamente indisponível. Tente dentro de "
    "alguns minutos."
)
GENERIC_REJECTION = (
    "O sistema fiscal recusou esta operação. Se o problema persistir, "
    "contacte o suporte Cellen."
)


@dataclass(frozen=True)
class Explanation:
    code: str
    message: str
    action: str | None = None


# Matched against the FinReg detail, lower-cased, in order: first match wins.
_BY_DETAIL: tuple[tuple[str, Explanation], ...] = (
    ("tax identification number is missing", Explanation(
        "guardian_nif_missing",
        "Falta o NIF do encarregado. Preencha o NIF na ficha do encarregado e tente de novo.",
        "edit_guardian",
    )),
    ("tax id already registered", Explanation(
        "guardian_nif_duplicate",
        "Este NIF já está associado a outro encarregado no sistema fiscal. Confirme o NIF na ficha.",
        "edit_guardian",
    )),
    ("tax exemption reason is required", Explanation(
        "tax_exemption_missing",
        "Um serviço sem IVA precisa do motivo de isenção. Configure-o em Serviços.",
        "edit_billing_item",
    )),
    ("legal exemption or out-of-scope reason", Explanation(
        "tax_exemption_missing",
        "Um serviço sem IVA precisa do motivo de isenção. Configure-o em Serviços.",
        "edit_billing_item",
    )),
    ("requires an agt exemption code", Explanation(
        "tax_exemption_missing",
        "Um serviço isento precisa do código de isenção da AGT. Configure-o em Serviços.",
        "edit_billing_item",
    )),
    ("active invoice series not found", Explanation(
        "series_missing",
        "A série de faturação da escola não está activa. Contacte o suporte Cellen.",
    )),
    ("invalid invoice series", Explanation(
        "series_missing",
        "A série de faturação da escola não está activa. Contacte o suporte Cellen.",
    )),
    ("document series is inactive", Explanation(
        "series_missing",
        "A série de faturação da escola não está activa. Contacte o suporte Cellen.",
    )),
    ("agt transport is disabled", Explanation(
        "agt_channel_disabled",
        "A ligação da escola à AGT ainda não está activa. Contacte o suporte Cellen.",
    )),
    ("verified finreg taxpayer profile", Explanation(
        "fiscal_profile_unverified",
        "Os dados fiscais da escola ainda não foram validados. Contacte o suporte Cellen.",
    )),
    ("fiscal corrections are disabled", Explanation(
        "fiscal_writes_disabled",
        "As anulações fiscais não estão activas para esta escola.",
    )),
    ("fiscal finalization is disabled", Explanation(
        "fiscal_writes_disabled",
        "A emissão fiscal não está activa para esta escola.",
    )),
    ("receipt issuance is disabled", Explanation(
        "fiscal_writes_disabled",
        "A emissão de recibos fiscais não está activa para esta escola.",
    )),
    ("document already cancelled", Explanation(
        "document_already_cancelled", "Este documento já foi anulado.",
    )),
    ("only a finalized sales document can be cancelled", Explanation(
        "document_not_finalized", "Só um documento já emitido pode ser anulado.",
    )),
    ("document already finalized", Explanation(
        "document_already_finalized", "Este documento já foi emitido.",
    )),
    ("has not been issued yet", Explanation(
        "document_not_finalized",
        "O documento ainda está a ser emitido. Tente dentro de instantes.",
    )),
    ("fiscal document is not finalized", Explanation(
        "document_not_finalized",
        "O documento ainda está a ser emitido. Tente dentro de instantes.",
    )),
    ("settlement exceeds outstanding", Explanation(
        "payment_exceeds_balance",
        "O valor é superior ao que está em dívida neste documento.",
    )),
    ("billing plan is paused", Explanation(
        "billing_plan_paused",
        "O plano de faturação do aluno está suspenso. Retome-o antes de faturar.",
    )),
    ("would skip a period", Explanation(
        "billing_period_out_of_order",
        "Há um mês anterior por faturar para este aluno. Fature os meses por ordem.",
    )),
    ("period is closed", Explanation(
        "fiscal_period_closed",
        "O período fiscal desta data já está fechado. Use uma data do período aberto.",
    )),
    ("closed period", Explanation(
        "fiscal_period_closed",
        "O período fiscal desta data já está fechado. Use uma data do período aberto.",
    )),
    ("period closed", Explanation(
        "fiscal_period_closed",
        "O período fiscal desta data já está fechado. Use uma data do período aberto.",
    )),
    ("mapping not found", Explanation(
        "fiscal_record_missing",
        "O sistema fiscal não reconhece este registo. Contacte o suporte Cellen.",
    )),
    ("not found", Explanation(
        "fiscal_record_missing",
        "O sistema fiscal não encontrou este documento. Contacte o suporte Cellen.",
    )),
)

_BY_CODE: dict[str, Explanation] = {
    "integration_disabled": Explanation(
        "fiscal_writes_disabled", "A faturação fiscal não está activa para esta escola.",
    ),
    "not_configured": Explanation(
        "fiscal_not_configured",
        "A ligação ao sistema fiscal não está configurada. Contacte o suporte Cellen.",
    ),
    "company_mismatch": Explanation(
        "fiscal_not_configured",
        "A ligação ao sistema fiscal pertence a outra entidade. Contacte o suporte Cellen.",
    ),
    "capability_entitlement_blocked": Explanation(
        "plan_blocks_operation",
        "O plano de faturação da escola não inclui esta operação.",
    ),
    "capability_mismatch": Explanation(
        "plan_blocks_operation",
        "O perfil fiscal da escola não inclui esta operação. Contacte o suporte Cellen.",
    ),
    "product_not_declared": Explanation(
        "billing_item_not_fiscal",
        "Um dos serviços não tem tratamento fiscal configurado. Configure-o em Serviços.",
        "edit_billing_item",
    ),
    "finreg_run_failed": Explanation(
        "billing_run_failed",
        "O sistema fiscal não conseguiu gerar este mês. Veja o motivo no registo fiscal.",
    ),
    "finreg_run_skipped": Explanation(
        "billing_run_skipped", "O sistema fiscal não tinha nada para faturar neste mês.",
    ),
    "http_401": Explanation(
        "fiscal_not_configured",
        "A ligação ao sistema fiscal foi recusada. Contacte o suporte Cellen.",
    ),
    "http_403": Explanation(
        "fiscal_operation_forbidden",
        "Esta operação fiscal não está autorizada para a escola.",
    ),
}


def explain(exc: FinregError) -> Explanation:
    """The school-facing explanation of one FinReg failure."""
    if exc.unknown_outcome:
        return Explanation("fiscal_pending_confirmation", PROCESSING_MESSAGE)
    detail = str(exc.detail or "").lower()
    for needle, explanation in _BY_DETAIL:
        if needle in detail:
            return explanation
    if exc.code in _BY_CODE:
        return _BY_CODE[exc.code]
    if exc.retryable:
        return Explanation("fiscal_unavailable", UNAVAILABLE_MESSAGE)
    return Explanation("fiscal_rejected", GENERIC_REJECTION)


def explain_stored(code: str | None, detail: str | None, *, status: str | None = None) -> str | None:
    """The school-facing message for an error already stored on an instruction."""
    if not code and not detail:
        return None
    if code == "dispatch_exception":
        return UNAVAILABLE_MESSAGE if status != "rejected" else GENERIC_REJECTION
    return explain(FinregError(
        code or "rejected",
        detail or "",
        retryable=status in {"pending", "processing"},
        unknown_outcome=status == "unknown",
    )).message


def http_error(exc: FinregError) -> HTTPException:
    explanation = explain(exc)
    status = 503 if exc.retryable or exc.unknown_outcome else 422
    detail = {"code": explanation.code, "message": explanation.message, "finreg_code": exc.code}
    if explanation.action:
        detail["action"] = explanation.action
    return HTTPException(status_code=status, detail=detail)
