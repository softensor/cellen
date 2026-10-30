# -*- coding: utf-8 -*-
"""Debt control: one read model over FinReg receivables or local invoices.

The school director asks two questions the fiscal engine answers differently
depending on the school's mode:

* FinReg-active schools: what does FinReg still consider receivable, for which
  pupil and which service? FinReg is the only source of that balance.
* Internal schools: the same question over Cellen's own signed invoices.

Both paths return the same row shape so the debt screen, the service report
and the dashboard have exactly one implementation to read. Balances are never
re-derived in the client: in FinReg mode they come from the receivables feed,
in internal mode from the same allocation/credit-note arithmetic the local
delinquent report uses.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.billing import BillingRun
from app.models.finance import (
    BillingItem,
    CreditNote,
    Invoice,
    InvoiceLine,
    Payment,
    PaymentAllocation,
    PaymentReference,
)
from app.models.finreg_integration import FinregBillingInstruction
from app.models.person import Child
from app.models.principia_pay import PrincipiaPayConnection
from app.services.billing_profiles import (
    get_fee_policy,
    get_school_year,
    policy_values,
)
from app.services.billing_run import (
    BillingError,
    FINREG_MODES,
    _add_days,
    _planned_dates,
    current_billing_month,
)
from app.services.finreg import FakeFinregAdapter, FinregError, HttpFinregAdapter
from app.services.finreg_dispatch import BILLING_RUN_COMMAND, integration_mode
from app.utils.agt import today_luanda

BUCKETS = ("current", "bucket_0_30", "bucket_31_60", "bucket_61_90", "bucket_90_plus")
PAGE_SIZE = 2000
MAX_PAGES = 10


def age_bucket(days_overdue: int) -> str:
    if days_overdue <= 0:
        return "current"
    if days_overdue <= 30:
        return "bucket_0_30"
    if days_overdue <= 60:
        return "bucket_31_60"
    if days_overdue <= 90:
        return "bucket_61_90"
    return "bucket_90_plus"


def _money(value) -> float:
    return round(float(value or 0), 2)


def _iso(value) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    return value.isoformat()


def _allocated_services(lines: list[dict], outstanding: float) -> list[dict]:
    """Spread a document's outstanding balance across its service lines.

    A partially paid multi-service invoice has no per-line settlement in the
    fiscal document (payment allocations are per document), so the report
    attributes the remaining balance proportionally to each line's gross
    amount. Sum of the result always equals the document outstanding.
    """
    gross = sum(float(line.get("gross_amount") or 0) for line in lines)
    if outstanding <= 0 or not lines:
        return []
    result: list[dict] = []
    remaining = outstanding
    for index, line in enumerate(lines):
        line_gross = float(line.get("gross_amount") or 0)
        if index == len(lines) - 1:
            share = remaining
        elif gross > 0:
            share = round(outstanding * line_gross / gross, 2)
            remaining = round(remaining - share, 2)
        else:
            share = 0.0
        result.append({
            "service": line.get("service"),
            "service_label": line.get("service_label") or line.get("description"),
            "description": line.get("description"),
            "gross_amount": _money(line_gross),
            "outstanding_amount": _money(share),
        })
    return result


async def _item_labels(db: AsyncSession, school_id: UUID, item_ids: set[UUID]) -> dict[UUID, str]:
    if not item_ids:
        return {}
    rows = (
        await db.execute(
            select(BillingItem.id, BillingItem.name).where(
                BillingItem.school_id == school_id,
                BillingItem.id.in_(item_ids),
            )
        )
    ).all()
    return {row[0]: row[1] for row in rows}


def _uuid_or_none(value) -> Optional[UUID]:
    try:
        return UUID(str(value)) if value else None
    except (TypeError, ValueError):
        return None


async def _finreg_rows(
    db: AsyncSession,
    *,
    school_id: UUID,
    adapter,
    as_of: date,
    overdue_only: bool,
) -> list[dict]:
    rows: list[dict] = []
    for page in range(MAX_PAGES):
        operation = (
            f"receivables?as_of={as_of.isoformat()}"
            f"&overdue_only={'true' if overdue_only else 'false'}"
            f"&limit={PAGE_SIZE}&offset={page * PAGE_SIZE}"
        )
        payload = await adapter.request(
            "GET", operation, None,
            actor_reference=f"cellen-debt-control:{school_id}",
        )
        page_rows = payload.get("rows") or []
        rows.extend(page_rows)
        if len(page_rows) < PAGE_SIZE:
            break

    items = await _item_labels(
        db,
        school_id,
        {
            UUID(str(line["product_external_id"]))
            for row in rows
            for line in row.get("lines") or []
            if _uuid_or_none(line.get("product_external_id"))
        },
    )
    result: list[dict] = []
    for row in rows:
        context = row.get("school_context") or {}
        raw_lines = row.get("lines") or []
        lines = [
            {
                "service": line.get("product_external_id"),
                "service_label": items.get(
                    _uuid_or_none(line.get("product_external_id"))
                ) or line.get("description"),
                "description": line.get("description"),
                "quantity": float(line.get("quantity") or 0),
                "gross_amount": _money(line.get("gross_amount")),
            }
            for line in raw_lines
        ]
        outstanding = _money(row.get("outstanding_amount"))
        result.append({
            "source": "finreg",
            "document_id": row.get("document_id"),
            # The host's own id for this document, as supplied when it was
            # created; principia-pay settlements and receipts key off it.
            "document_external_id": row.get("document_external_id"),
            "document_number": row.get("full_document_number"),
            "document_type": row.get("document_type"),
            "document_date": row.get("document_date"),
            "due_date": row.get("due_date"),
            "student_id": context.get("pupil_id"),
            "student_name": context.get("pupil_name"),
            "guardian_id": row.get("customer_external_id"),
            "guardian_name": row.get("customer_name"),
            "currency_code": row.get("currency_code") or "AOA",
            "gross_total": _money(row.get("gross_total")),
            "credited_total": _money(row.get("credited_total")),
            "paid_total": _money(row.get("paid_total")),
            "outstanding": outstanding,
            "days_overdue": int(row.get("days_overdue") or 0),
            "bucket": row.get("bucket") or age_bucket(int(row.get("days_overdue") or 0)),
            "status": "overdue" if int(row.get("days_overdue") or 0) > 0 else "pending",
            "lines": lines,
            "services": _allocated_services(lines, outstanding),
        })
    return result


async def _internal_rows(
    db: AsyncSession,
    *,
    school_id: UUID,
    as_of: date,
    overdue_only: bool,
) -> list[dict]:
    conditions = [
        Invoice.school_id == school_id,
        Invoice.status.in_(("pending", "partially_paid", "overdue")),
        Invoice.is_void.is_(False),
        Invoice.document_type.in_(("FT", "ND")),
    ]
    if overdue_only:
        conditions.append(Invoice.due_date < as_of)
    invoices = list(
        (
            await db.execute(
                select(Invoice)
                .where(*conditions)
                .order_by(Invoice.due_date.asc(), Invoice.invoice_date.asc())
            )
        ).scalars().all()
    )
    if not invoices:
        return []
    invoice_ids = [invoice.id for invoice in invoices]

    paid = {
        row[0]: row[1]
        for row in (
            await db.execute(
                select(
                    PaymentAllocation.invoice_id,
                    func.coalesce(func.sum(PaymentAllocation.amount_applied), 0),
                )
                .join(Payment, Payment.id == PaymentAllocation.payment_id)
                .where(
                    PaymentAllocation.invoice_id.in_(invoice_ids),
                    Payment.status == "normal",
                )
                .group_by(PaymentAllocation.invoice_id)
            )
        ).all()
    }
    credited = {
        row[0]: row[1]
        for row in (
            await db.execute(
                select(
                    CreditNote.invoice_id,
                    func.coalesce(func.sum(CreditNote.gross_total), 0),
                )
                .where(CreditNote.invoice_id.in_(invoice_ids))
                .group_by(CreditNote.invoice_id)
            )
        ).all()
    }
    line_rows = (
        await db.execute(
            select(InvoiceLine)
            .where(InvoiceLine.invoice_id.in_(invoice_ids))
            .order_by(InvoiceLine.invoice_id, InvoiceLine.line_number)
        )
    ).scalars().all()
    lines_by_invoice: dict[UUID, list[InvoiceLine]] = {}
    for line in line_rows:
        lines_by_invoice.setdefault(line.invoice_id, []).append(line)

    item_ids = {line.billing_item_id for line in line_rows if line.billing_item_id}
    items = await _item_labels(db, school_id, item_ids)
    child_ids = {invoice.child_id for invoice in invoices if invoice.child_id}
    children = {
        child.id: f"{child.first_name} {child.last_name}"
        for child in (
            await db.execute(select(Child).where(Child.id.in_(child_ids)))
        ).scalars().all()
    } if child_ids else {}

    result: list[dict] = []
    for invoice in invoices:
        gross = _money(invoice.gross_total)
        paid_total = _money(paid.get(invoice.id))
        credited_total = _money(credited.get(invoice.id))
        outstanding = _money(max(gross - paid_total - credited_total, 0))
        if outstanding <= 0:
            continue
        due = invoice.due_date or invoice.invoice_date
        days_overdue = max((as_of - due).days, 0)
        lines = [
            {
                "service": str(line.billing_item_id) if line.billing_item_id else None,
                "service_label": items.get(line.billing_item_id) or line.description,
                "description": line.description,
                "quantity": float(line.quantity),
                "gross_amount": _money(line.line_total),
            }
            for line in lines_by_invoice.get(invoice.id, [])
        ]
        result.append({
            "source": "internal",
            "document_id": str(invoice.id),
            "document_external_id": str(invoice.id),
            "document_number": invoice.full_document_number,
            "document_type": invoice.document_type,
            "document_date": _iso(invoice.invoice_date),
            "due_date": _iso(invoice.due_date),
            "student_id": str(invoice.child_id) if invoice.child_id else None,
            "student_name": children.get(invoice.child_id) if invoice.child_id else None,
            "guardian_id": str(invoice.billing_guardian_id) if invoice.billing_guardian_id else None,
            "guardian_name": invoice.customer_name,
            "currency_code": "AOA",
            "gross_total": gross,
            "credited_total": credited_total,
            "paid_total": paid_total,
            "outstanding": outstanding,
            "days_overdue": days_overdue,
            "bucket": age_bucket(days_overdue),
            "status": "overdue" if days_overdue > 0 else "pending",
            "lines": lines,
            "services": _allocated_services(lines, outstanding),
        })
    return result


def _matches_service(row: dict, service: str) -> bool:
    """Exact key or label match; substring matching would let "Propina"
    sweep up every tuition variant a school configures."""
    wanted = service.strip().casefold()
    if not wanted:
        return True
    return any(
        wanted == str(line.get("service") or "").strip().casefold()
        or wanted == str(line.get("service_label") or "").strip().casefold()
        for line in row.get("lines") or []
    )


def _summary(rows: list[dict]) -> dict:
    buckets = {bucket: 0.0 for bucket in BUCKETS}
    total = overdue = 0.0
    by_service: dict[str, dict] = {}
    by_student: dict[str, dict] = {}
    for row in rows:
        amount = float(row["outstanding"])
        total += amount
        if row["days_overdue"] > 0:
            overdue += amount
        buckets[row["bucket"]] = round(buckets.get(row["bucket"], 0.0) + amount, 2)
        for service in row.get("services") or []:
            key = str(service.get("service") or service.get("service_label") or "outros")
            entry = by_service.setdefault(key, {
                "service": service.get("service"),
                "service_label": service.get("service_label"),
                "outstanding": 0.0,
                "documents": 0,
            })
            entry["outstanding"] = round(entry["outstanding"] + float(service["outstanding_amount"]), 2)
            entry["documents"] += 1
        student_key = str(row.get("student_id") or "sem_aluno")
        student = by_student.setdefault(student_key, {
            "student_id": row.get("student_id"),
            "student_name": row.get("student_name"),
            "outstanding": 0.0,
            "overdue": 0.0,
            "documents": 0,
        })
        student["outstanding"] = round(student["outstanding"] + amount, 2)
        if row["days_overdue"] > 0:
            student["overdue"] = round(student["overdue"] + amount, 2)
        student["documents"] += 1
    return {
        "total_outstanding": _money(total),
        "total_overdue": _money(overdue),
        "by_bucket": {key: _money(value) for key, value in buckets.items()},
        "by_service": sorted(
            by_service.values(), key=lambda entry: entry["outstanding"], reverse=True
        ),
        "by_student": sorted(
            by_student.values(), key=lambda entry: entry["outstanding"], reverse=True
        ),
    }


async def list_debts(
    db: AsyncSession,
    *,
    school_id: UUID,
    as_of: Optional[date] = None,
    overdue_only: bool = False,
    student_id: Optional[UUID] = None,
    guardian_id: Optional[UUID] = None,
    service: Optional[str] = None,
    bucket: Optional[str] = None,
    adapter=None,
) -> dict:
    """Open debts in one shape, from whichever engine owns the school."""
    reference = as_of or today_luanda()
    if reference > today_luanda():
        reference = today_luanda()
    mode = await integration_mode(db, school_id)
    if mode in FINREG_MODES:
        adapter = adapter or (
            FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter()
        )
        try:
            rows = await _finreg_rows(
                db, school_id=school_id, adapter=adapter,
                as_of=reference, overdue_only=overdue_only,
            )
        except FinregError as exc:
            raise BillingError(
                exc.code,
                f"Não foi possível ler as dívidas do FinReg: {exc.detail}",
                502,
            ) from exc
    else:
        rows = await _internal_rows(
            db, school_id=school_id, as_of=reference, overdue_only=overdue_only
        )

    if bucket is not None and bucket not in BUCKETS:
        raise BillingError(
            "invalid_bucket",
            f"Antiguidade inválida. Use uma de: {', '.join(BUCKETS)}.",
            422,
        )
    if student_id is not None:
        rows = [row for row in rows if row.get("student_id") == str(student_id)]
    if guardian_id is not None:
        rows = [row for row in rows if row.get("guardian_id") == str(guardian_id)]
    if service:
        rows = [row for row in rows if _matches_service(row, service)]
    if bucket is not None:
        rows = [row for row in rows if row.get("bucket") == bucket]

    summary = _summary(rows)
    return {
        "mode": mode,
        "as_of": reference.isoformat(),
        "count": len(rows),
        "overdue_only": overdue_only,
        "bucket": bucket,
        **summary,
        "rows": rows,
    }


async def service_report(
    db: AsyncSession,
    *,
    school_id: UUID,
    date_from: date,
    date_to: date,
    adapter=None,
) -> dict:
    """Sales by service for a period, in either mode.

    FinReg-active schools read FinReg's own sales-by-product report, so the
    number the director sees is the number the fiscal engine reports. Internal
    schools aggregate the same signed invoice lines locally.
    """
    if date_from > date_to:
        raise BillingError("invalid_period", "A data inicial é posterior à final.", 422)
    mode = await integration_mode(db, school_id)
    if mode in FINREG_MODES:
        adapter = adapter or (
            FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter()
        )
        try:
            rows = await adapter.request(
                "GET",
                f"reports/sales-by-product?date_from={date_from.isoformat()}"
                f"&date_to={date_to.isoformat()}",
                None,
                actor_reference=f"cellen-service-report:{school_id}",
            )
        except FinregError as exc:
            raise BillingError(
                exc.code,
                f"Não foi possível ler o relatório do FinReg: {exc.detail}",
                502,
            ) from exc
        items = await _item_labels(
            db,
            school_id,
            {
                UUID(str(row["product_external_id"]))
                for row in rows
                if _uuid_or_none(row.get("product_external_id"))
            },
        )
        services = [
            {
                "service": row.get("product_external_id"),
                "service_label": items.get(
                    _uuid_or_none(row.get("product_external_id"))
                ) or row.get("description"),
                "description": row.get("description"),
                "quantity": _money(row.get("total_qty")),
                "net_total": _money(row.get("total_net")),
                "tax_total": _money(row.get("total_tax")),
                "gross_total": _money(row.get("total_gross")),
            }
            for row in rows
        ]
    else:
        rows = (
            await db.execute(
                select(
                    InvoiceLine.billing_item_id,
                    InvoiceLine.description,
                    func.sum(InvoiceLine.quantity),
                    func.sum(InvoiceLine.line_net),
                    func.sum(InvoiceLine.iva_amount),
                    func.sum(InvoiceLine.line_total),
                )
                .join(Invoice, InvoiceLine.invoice_id == Invoice.id)
                .where(
                    Invoice.school_id == school_id,
                    Invoice.document_type.in_(("FT", "ND", "FR")),
                    Invoice.is_void.is_(False),
                    Invoice.invoice_date >= date_from,
                    Invoice.invoice_date <= date_to,
                )
                .group_by(InvoiceLine.billing_item_id, InvoiceLine.description)
                .order_by(func.sum(InvoiceLine.line_total).desc())
            )
        ).all()
        items = await _item_labels(
            db, school_id, {row[0] for row in rows if row[0]}
        )
        services = [
            {
                "service": str(row[0]) if row[0] else None,
                "service_label": items.get(row[0]) or row[1],
                "description": row[1],
                "quantity": _money(row[2]),
                "net_total": _money(row[3]),
                "tax_total": _money(row[4]),
                "gross_total": _money(row[5]),
            }
            for row in rows
        ]
    return {
        "mode": mode,
        "period": {"from": date_from.isoformat(), "to": date_to.isoformat()},
        "services": services,
        "totals": {
            "quantity": _money(sum(row["quantity"] for row in services)),
            "net_total": _money(sum(row["net_total"] for row in services)),
            "tax_total": _money(sum(row["tax_total"] for row in services)),
            "gross_total": _money(sum(row["gross_total"] for row in services)),
        },
    }


async def _month_status(
    db: AsyncSession, *, school_id: UUID, today: date
) -> dict:
    """What the current billing month looks like to a director.

    Answers the home card: has this month's debt generation run, for how many
    students, and when is it due. A BillingRun row only ever exists because
    the generate path created it, so its presence is the "generated" signal.
    """
    month = current_billing_month()
    run = (
        await db.execute(
            select(BillingRun)
            .where(
                BillingRun.school_id == school_id,
                BillingRun.billing_month == month,
            )
            .order_by(BillingRun.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    school_year = await get_school_year(db, school_id)
    policy = (
        await get_fee_policy(db, school_id, school_year.id)
        if school_year is not None
        else None
    )
    values = policy_values(policy)
    run_date, _ = _planned_dates(month, values["billing_day"], today)
    due_date = _add_days(run_date, values["due_days"]).isoformat()
    if run is None:
        return {
            "billing_month": month,
            "generated": False,
            "status": None,
            "students": None,
            "failed": None,
            "total": None,
            "due_date": due_date,
            "auto_generate": bool(values["auto_generate"]),
        }
    stats = run.stats or {}
    totals = stats.get("totals") or {}
    snapshot = stats.get("policy") or {}
    auto_generate = bool(values["auto_generate"])
    if policy is None:
        # No policy row to read: the run's snapshot is the only record left.
        auto_generate = bool(snapshot.get("auto_generate"))
    return {
        "billing_month": month,
        "generated": True,
        "status": run.status,
        "students": stats.get("students"),
        "failed": stats.get("failed"),
        "total": totals.get("total"),
        "due_date": stats.get("due_date") or due_date,
        "auto_generate": auto_generate,
        "references": await _month_references(
            db, school_id=school_id, month=month
        ),
    }


async def _month_references(
    db: AsyncSession, *, school_id: UUID, month: str
) -> dict:
    """How far the month's bills got on their way to the families.

    Generating the debts is only the first step: each emitted document then
    gets a payment reference the guardian sees in the app, and the reference
    is eventually paid. The home card shows that chain, so a director can see
    "sent to 40 of 42 families, 12 paid" without opening three screens.
    """
    enabled = (
        await db.execute(
            select(func.count())
            .select_from(PrincipiaPayConnection)
            .where(
                PrincipiaPayConnection.school_id == school_id,
                PrincipiaPayConnection.status == "active",
            )
        )
    ).scalar_one() > 0
    rows = (
        await db.execute(
            select(
                FinregBillingInstruction.payment_reference_status,
                PaymentReference.status,
                func.count(),
            )
            .select_from(FinregBillingInstruction)
            .outerjoin(
                PaymentReference,
                PaymentReference.id == FinregBillingInstruction.payment_reference_id,
            )
            .where(
                FinregBillingInstruction.school_id == school_id,
                FinregBillingInstruction.command_type == BILLING_RUN_COMMAND,
                FinregBillingInstruction.status == "confirmed",
                FinregBillingInstruction.payload["billing_month"].astext == month,
            )
            .group_by(
                FinregBillingInstruction.payment_reference_status,
                PaymentReference.status,
            )
        )
    ).all()
    counts = {"documents": 0, "sent": 0, "waiting": 0, "failed": 0, "skipped": 0, "paid": 0}
    for issue_status, reference_status, count in rows:
        counts["documents"] += count
        if issue_status == "created":
            counts["sent"] += count
            if reference_status == "paid":
                counts["paid"] += count
        elif issue_status == "failed":
            counts["failed"] += count
        elif issue_status == "skipped":
            counts["skipped"] += count
        else:
            counts["waiting"] += count
    return {"enabled": enabled, **counts}


async def dashboard(db: AsyncSession, *, school_id: UUID, adapter=None) -> dict:
    """The finance home: debts, billing and collections in one answer."""
    today = today_luanda()
    month_start = today.replace(day=1)
    mode = await integration_mode(db, school_id)
    month = await _month_status(db, school_id=school_id, today=today)
    debts = await list_debts(
        db, school_id=school_id, overdue_only=False, adapter=adapter
    )
    period = {
        "from": month_start.isoformat(),
        "to": today.isoformat(),
    }
    if mode in FINREG_MODES:
        adapter = adapter or (
            FakeFinregAdapter() if mode == "fake" else HttpFinregAdapter()
        )
        try:
            sales = await adapter.request(
                "GET",
                f"reports/sales-summary?date_from={period['from']}&date_to={period['to']}",
                None,
                actor_reference=f"cellen-dashboard:{school_id}",
            )
            collections = await adapter.request(
                "GET",
                f"reports/collections-summary?date_from={period['from']}&date_to={period['to']}",
                None,
                actor_reference=f"cellen-dashboard:{school_id}",
            )
        except FinregError as exc:
            raise BillingError(
                exc.code,
                f"Não foi possível ler o painel do FinReg: {exc.detail}",
                502,
            ) from exc
    else:
        sales_rows = (
            await db.execute(
                select(
                    func.count(),
                    func.coalesce(func.sum(Invoice.gross_total), 0),
                ).where(
                    Invoice.school_id == school_id,
                    Invoice.document_type.in_(("FT", "ND", "FR")),
                    Invoice.is_void.is_(False),
                    Invoice.invoice_date >= month_start,
                    Invoice.invoice_date <= today,
                )
            )
        ).one()
        collections_rows = (
            await db.execute(
                select(Payment.payment_method, func.count(), func.coalesce(func.sum(Payment.amount), 0))
                .where(
                    Payment.school_id == school_id,
                    Payment.status == "normal",
                    Payment.payment_date >= month_start,
                    Payment.payment_date <= today,
                )
                .group_by(Payment.payment_method)
            )
        ).all()
        sales = {
            "period": period,
            "invoice_count": sales_rows[0],
            "total_gross": _money(sales_rows[1]),
        }
        collections = {
            "period": period,
            "payment_count": sum(row[1] for row in collections_rows),
            "total_collected": _money(sum(row[2] for row in collections_rows)),
            "by_method": [
                {"payment_method": row[0], "payment_count": row[1], "total": _money(row[2])}
                for row in collections_rows
            ],
        }
    return {
        "mode": mode,
        "as_of": today.isoformat(),
        "period": period,
        "month": month,
        "debts": {
            "count": debts["count"],
            "total_outstanding": debts["total_outstanding"],
            "total_overdue": debts["total_overdue"],
            "by_bucket": debts["by_bucket"],
            "by_service": debts["by_service"][:10],
        },
        "sales": sales,
        "collections": collections,
    }
