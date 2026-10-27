# -*- coding: utf-8 -*-
"""Pure monthly fee composition.

This module holds no database access and no hardcoded business rules. Given
the school's policy and each student's effective-dated billing inputs, it
returns exactly what the month costs: tuition, transport, extracurricular
activities, proration, and the sibling discount.

Keeping it pure matters for two reasons. The preview endpoint can show the
director the exact invoice amounts without calling FinReg, and the same
function feeds both the FinReg plan and the internal fiscal path, so the two
modes cannot drift.
"""
from __future__ import annotations

import calendar
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Optional
from uuid import UUID

from app.utils.agt import compute_line

MONEY = Decimal("0.01")
HUNDRED = Decimal("100")

SERVICE_TUITION = "tuition"
SERVICE_TRANSPORT = "transport"
SERVICE_MODALITY = "modality"


def quantize_money(value) -> Decimal:
    return Decimal(str(value)).quantize(MONEY, rounding=ROUND_HALF_UP)


def month_bounds(billing_month: str) -> tuple[date, date]:
    """Parse ``YYYY-MM`` and return its first and last day."""
    try:
        year, month = (int(part) for part in billing_month.split("-"))
        first = date(year, month, 1)
    except (ValueError, TypeError) as exc:
        raise ValueError("billing_month must use the YYYY-MM format") from exc
    return first, date(year, month, calendar.monthrange(year, month)[1])


def billing_date(billing_month: str, billing_day: int) -> date:
    """The plan's run date for a month, clamped to the month's last day."""
    first, last = month_bounds(billing_month)
    return date(first.year, first.month, min(max(billing_day, 1), last.day))


def advance_month(value: date) -> date:
    """Same day next month, clamped when the next month is shorter."""
    total = value.month  # 1-based month becomes the zero-based "next" index
    year = value.year + total // 12
    month = total % 12 + 1
    return date(year, month, min(value.day, calendar.monthrange(year, month)[1]))


@dataclass(frozen=True)
class FeePolicyConfig:
    """A materialised, immutable snapshot of the school's editable policy."""
    sibling_discount_pct: Decimal = Decimal("5.00")
    sibling_discount_min_children: int = 2
    sibling_discount_scope: str = "additional_children"
    due_days: int = 5
    billing_day: int = 1
    proration_policy: str = "pro_rata_days"
    default_enrollment_fee: Optional[Decimal] = None


@dataclass(frozen=True)
class CatalogItem:
    """The fiscal attributes of a billing item, detached from the ORM."""
    id: UUID
    code: str
    name: str
    unit_price: Decimal
    iva_rate: Decimal
    tax_option_code: Optional[str]
    exemption_reason: Optional[str]
    exemption_legend: Optional[str]
    category: Optional[str]
    is_active: bool = True


@dataclass(frozen=True)
class ModalityCharge:
    enrollment_id: UUID
    modality_id: UUID
    name: str
    monthly_fee: Decimal
    item: Optional[CatalogItem]
    start_date: date
    end_date: Optional[date] = None


@dataclass(frozen=True)
class TransportCharge:
    assignment_id: UUID
    route_id: UUID
    route_name: str
    monthly_price: Decimal
    item: Optional[CatalogItem]
    start_date: date
    end_date: Optional[date] = None


@dataclass(frozen=True)
class StudentBillingInput:
    child_id: UUID
    child_name: str
    guardian_id: UUID
    guardian_name: str
    guardian_nif: Optional[str]
    enrollment_id: UUID
    enrollment_date: date
    tuition_item: Optional[CatalogItem]
    tuition_base_price: Decimal
    tuition_override: Optional[Decimal]
    starts_on: date
    ends_on: Optional[date]
    billing_day: int
    plan_external_id: UUID
    transport: Optional[TransportCharge] = None
    modalities: tuple[ModalityCharge, ...] = ()
    sort_created_at: Optional[datetime] = None


@dataclass(frozen=True)
class ChargeLine:
    service: str
    service_label: str
    source_id: Optional[UUID]
    billing_item_id: UUID
    description: str
    quantity: Decimal
    base_unit_price: Decimal
    unit_price: Decimal
    discount_pct: Decimal
    tax_rate: Decimal
    tax_option_code: Optional[str]
    exemption_reason: Optional[str]
    exemption_legend: Optional[str]
    proration_factor: Optional[Decimal]
    line_net: Decimal
    iva_amount: Decimal
    line_total: Decimal

    @property
    def gross(self) -> Decimal:
        return quantize_money(self.unit_price * self.quantity)

    @property
    def discount_amount(self) -> Decimal:
        return quantize_money(self.gross * self.discount_pct / HUNDRED)


@dataclass(frozen=True)
class StudentComposition:
    child_id: UUID
    child_name: str
    guardian_id: UUID
    guardian_name: str
    guardian_nif: Optional[str]
    enrollment_id: UUID
    plan_external_id: UUID
    billing_day: int
    sibling_index: int
    family_size: int
    sibling_discount_applied: bool
    starts_on: Optional[date] = None
    lines: tuple[ChargeLine, ...] = ()
    warnings: tuple[str, ...] = ()
    subtotal: Decimal = Decimal("0")
    discount_total: Decimal = Decimal("0")
    net_total: Decimal = Decimal("0")
    iva_total: Decimal = Decimal("0")
    total: Decimal = Decimal("0")


@dataclass(frozen=True)
class BillingComposition:
    billing_month: str
    policy: FeePolicyConfig
    students: tuple[StudentComposition, ...]
    warnings: tuple[str, ...] = ()
    totals: dict = field(default_factory=dict)

    def student(self, child_id: UUID) -> Optional[StudentComposition]:
        return next((s for s in self.students if s.child_id == child_id), None)


@dataclass(frozen=True)
class _Window:
    start: date
    end: date
    factor: Decimal
    billable: bool


def _active_window(
    starts_on: date,
    ends_on: Optional[date],
    month_start: date,
    month_end: date,
    proration_policy: str,
) -> Optional[_Window]:
    start = max(starts_on, month_start)
    end = min(ends_on or month_end, month_end)
    if start > end:
        return None
    total_days = (month_end - month_start).days + 1
    active_days = (end - start).days + 1
    if active_days >= total_days:
        return _Window(start=start, end=end, factor=Decimal("1"), billable=True)
    if proration_policy == "full_month":
        return _Window(start=start, end=end, factor=Decimal("1"), billable=True)
    if proration_policy == "no_charge":
        return _Window(start=start, end=end, factor=Decimal("0"), billable=False)
    factor = (Decimal(active_days) / Decimal(total_days)).quantize(
        Decimal("0.000001"), rounding=ROUND_HALF_UP
    )
    return _Window(start=start, end=end, factor=factor, billable=True)


def _make_line(
    *,
    service: str,
    service_label: str,
    source_id: Optional[UUID],
    item: CatalogItem,
    description: str,
    base_price: Decimal,
    discount_pct: Decimal,
    window: _Window,
    quantity: Decimal = Decimal("1"),
) -> ChargeLine:
    factor = window.factor
    unit_price = quantize_money(base_price * factor)
    computed = compute_line(
        unit_price=unit_price,
        quantity=quantity,
        discount_percent=discount_pct,
        iva_rate=item.iva_rate,
    )
    return ChargeLine(
        service=service,
        service_label=service_label,
        source_id=source_id,
        billing_item_id=item.id,
        description=description,
        quantity=quantity,
        base_unit_price=quantize_money(base_price),
        unit_price=unit_price,
        discount_pct=Decimal(discount_pct),
        tax_rate=item.iva_rate,
        tax_option_code=item.tax_option_code,
        exemption_reason=item.exemption_reason,
        exemption_legend=item.exemption_legend,
        proration_factor=None if factor == Decimal("1") else factor,
        line_net=computed["line_net"],
        iva_amount=computed["iva_amount"],
        line_total=computed["line_total"],
    )


def _service_description(item: CatalogItem, suffix: Optional[str]) -> str:
    if suffix and suffix.strip() and suffix.strip().casefold() != item.name.strip().casefold():
        return f"{item.name} — {suffix.strip()}"
    return item.name


def compose_students(
    inputs: list[StudentBillingInput],
    policy: FeePolicyConfig,
    billing_month: str,
) -> BillingComposition:
    """Compose every student's month without touching the database."""
    month_start, month_end = month_bounds(billing_month)
    by_guardian: dict[UUID, list[StudentBillingInput]] = {}
    for student in inputs:
        by_guardian.setdefault(student.guardian_id, []).append(student)

    sibling: dict[UUID, tuple[int, int, bool]] = {}
    minimum = max(int(policy.sibling_discount_min_children), 1)
    for family in by_guardian.values():
        ordered = sorted(
            family,
            key=lambda s: (
                s.sort_created_at or datetime.min.replace(tzinfo=timezone.utc),
                str(s.child_id),
            ),
        )
        size = len(ordered)
        for index, student in enumerate(ordered, 1):
            applies = size >= minimum and (
                policy.sibling_discount_scope == "all_children" or index >= 2
            )
            sibling[student.child_id] = (index, size, applies)

    composed: list[StudentComposition] = []
    warnings: list[str] = []
    for student in inputs:
        index, family_size, sibling_applies = sibling[student.child_id]
        student_warnings: list[str] = []
        lines: list[ChargeLine] = []

        discount_pct = (
            Decimal(policy.sibling_discount_pct) if sibling_applies else Decimal("0")
        )

        if student.tuition_item is None:
            student_warnings.append("tuition_item_missing")
        elif not student.tuition_item.is_active:
            student_warnings.append("tuition_item_inactive")
        else:
            window = _active_window(
                student.starts_on, student.ends_on, month_start, month_end,
                policy.proration_policy,
            )
            if window is None:
                student_warnings.append("not_enrolled_this_month")
            elif not window.billable:
                student_warnings.append("partial_month_not_charged")
            else:
                base = (
                    student.tuition_override
                    if student.tuition_override is not None
                    else student.tuition_base_price
                )
                if quantize_money(base) <= 0:
                    student_warnings.append("tuition_amount_zero")
                else:
                    lines.append(_make_line(
                        service=SERVICE_TUITION,
                        service_label=student.tuition_item.name,
                        source_id=student.enrollment_id,
                        item=student.tuition_item,
                        description=student.tuition_item.name,
                        base_price=base,
                        discount_pct=discount_pct,
                        window=window,
                    ))

        transport = student.transport
        if transport is not None:
            window = _active_window(
                transport.start_date, transport.end_date, month_start, month_end,
                policy.proration_policy,
            )
            if window is not None and not window.billable:
                student_warnings.append("transport_partial_month_not_charged")
            elif window is not None:
                if transport.item is None:
                    student_warnings.append("transport_item_missing")
                elif not transport.item.is_active:
                    student_warnings.append("transport_item_inactive")
                elif quantize_money(transport.monthly_price) > 0:
                    lines.append(_make_line(
                        service=SERVICE_TRANSPORT,
                        service_label=transport.route_name,
                        source_id=transport.assignment_id,
                        item=transport.item,
                        description=_service_description(
                            transport.item, transport.route_name
                        ),
                        base_price=transport.monthly_price,
                        discount_pct=Decimal("0"),
                        window=window,
                    ))

        for modality in student.modalities:
            window = _active_window(
                modality.start_date, modality.end_date, month_start, month_end,
                policy.proration_policy,
            )
            if window is None:
                continue
            if not window.billable:
                student_warnings.append(
                    f"modality_partial_month_not_charged:{modality.name}"
                )
                continue
            if modality.item is None:
                student_warnings.append(
                    f"modality_item_missing:{modality.name}"
                )
                continue
            if not modality.item.is_active:
                student_warnings.append(
                    f"modality_item_inactive:{modality.name}"
                )
                continue
            if quantize_money(modality.monthly_fee) <= 0:
                continue
            lines.append(_make_line(
                service=SERVICE_MODALITY,
                service_label=modality.name,
                source_id=modality.enrollment_id,
                item=modality.item,
                description=_service_description(modality.item, modality.name),
                base_price=modality.monthly_fee,
                discount_pct=Decimal("0"),
                window=window,
            ))

        subtotal = sum((line.gross for line in lines), Decimal("0"))
        discount_total = sum((line.discount_amount for line in lines), Decimal("0"))
        net_total = sum((line.line_net for line in lines), Decimal("0"))
        iva_total = sum((line.iva_amount for line in lines), Decimal("0"))
        total = sum((line.line_total for line in lines), Decimal("0"))

        if not lines:
            student_warnings.append("nothing_to_bill")
        for warning in student_warnings:
            if warning not in warnings:
                warnings.append(warning)

        composed.append(StudentComposition(
            child_id=student.child_id,
            child_name=student.child_name,
            guardian_id=student.guardian_id,
            guardian_name=student.guardian_name,
            guardian_nif=student.guardian_nif,
            enrollment_id=student.enrollment_id,
            plan_external_id=student.plan_external_id,
            billing_day=student.billing_day,
            sibling_index=index,
            family_size=family_size,
            sibling_discount_applied=sibling_applies and bool(lines)
            and any(line.service == SERVICE_TUITION for line in lines),
            starts_on=student.starts_on,
            lines=tuple(lines),
            warnings=tuple(student_warnings),
            subtotal=quantize_money(subtotal),
            discount_total=quantize_money(discount_total),
            net_total=quantize_money(net_total),
            iva_total=quantize_money(iva_total),
            total=quantize_money(total),
        ))

    students = tuple(sorted(composed, key=lambda s: (s.guardian_name.casefold(), s.child_name.casefold())))
    totals = {
        "students": len(students),
        "lines": sum(len(s.lines) for s in students),
        "subtotal": quantize_money(sum((s.subtotal for s in students), Decimal("0"))),
        "discount_total": quantize_money(
            sum((s.discount_total for s in students), Decimal("0"))
        ),
        "net_total": quantize_money(sum((s.net_total for s in students), Decimal("0"))),
        "iva_total": quantize_money(sum((s.iva_total for s in students), Decimal("0"))),
        "total": quantize_money(sum((s.total for s in students), Decimal("0"))),
        "families_with_discount": len({
            s.guardian_id for s in students if s.sibling_discount_applied
        }),
    }
    return BillingComposition(
        billing_month=billing_month,
        policy=policy,
        students=students,
        warnings=tuple(warnings),
        totals=totals,
    )
