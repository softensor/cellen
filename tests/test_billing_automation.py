# -*- coding: utf-8 -*-
"""Golden tests for the pure monthly fee composer.

No database, no HTTP, no FinReg: the composer is the single source of the
numbers the director sees in the preview and the numbers both fiscal paths
issue. These tests pin the director's cases exactly: the 5% sibling discount
on additional children, the per-service lines, and pro-rated months.
"""
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

import pytest

from app.services.billing_composer import (
    CatalogItem,
    FeePolicyConfig,
    ModalityCharge,
    StudentBillingInput,
    TransportCharge,
    advance_month,
    billing_date,
    compose_students,
    month_bounds,
)
from app.services.billing_profiles import plan_external_id
from app.services.billing_run import _plan_revision


# ─── builders ───────────────────────────────────────────────────────────────

def _catalog(
    *,
    name="Mensalidade",
    price="100000.00",
    rate="0",
    tax_option="IVA_ISE",
    reason="M10",
    active=True,
    item_id=None,
):
    return CatalogItem(
        id=item_id or uuid.uuid4(),
        code="MENS",
        name=name,
        unit_price=Decimal(price),
        iva_rate=Decimal(rate),
        tax_option_code=tax_option,
        exemption_reason=reason,
        exemption_legend=None,
        category=None,
        is_active=active,
    )


def _student(
    child_id,
    guardian_id,
    *,
    name="Ana",
    guardian_name="Maria",
    created_at=datetime(2026, 1, 1, 8, tzinfo=timezone.utc),
    item=None,
    override=None,
    starts_on=date(2026, 1, 1),
    ends_on=None,
    transport=None,
    modalities=(),
):
    item = item or _catalog()
    return StudentBillingInput(
        child_id=child_id,
        child_name=name,
        guardian_id=guardian_id,
        guardian_name=guardian_name,
        guardian_nif=None,
        enrollment_id=uuid.uuid4(),
        enrollment_date=starts_on,
        tuition_item=item,
        tuition_base_price=item.unit_price,
        tuition_override=Decimal(override) if override is not None else None,
        starts_on=starts_on,
        ends_on=ends_on,
        billing_day=1,
        plan_external_id=uuid.uuid4(),
        transport=transport,
        modalities=tuple(modalities),
        sort_created_at=created_at,
    )


def _transport(price="20000.00", *, name="Transporte", route="Rota A", rate="0"):
    return TransportCharge(
        assignment_id=uuid.uuid4(),
        route_id=uuid.uuid4(),
        route_name=route,
        monthly_price=Decimal(price),
        item=_catalog(name=name, price=price, rate=rate),
        start_date=date(2026, 1, 1),
    )


def _modality(name, price, *, rate="0"):
    return ModalityCharge(
        enrollment_id=uuid.uuid4(),
        modality_id=uuid.uuid4(),
        name=name,
        monthly_fee=Decimal(price),
        item=_catalog(name=name, price=price, rate=rate),
        start_date=date(2026, 1, 1),
    )


# ─── sibling discount ───────────────────────────────────────────────────────

def test_sibling_discount_hits_the_additional_child_tuition_only():
    guardian = uuid.uuid4()
    first = _student(
        uuid.uuid4(), guardian, name="Ana",
        created_at=datetime(2026, 1, 1, 8, tzinfo=timezone.utc),
    )
    second = _student(
        uuid.uuid4(), guardian, name="Bruno",
        created_at=datetime(2026, 1, 1, 9, tzinfo=timezone.utc),
        transport=_transport(),
        modalities=(_modality("Balé", "15000.00"),),
    )

    # Input order must not decide who pays the discounted tuition.
    composition = compose_students(
        [second, first], FeePolicyConfig(), "2026-09",
    )
    ana = composition.student(first.child_id)
    bruno = composition.student(second.child_id)

    assert (ana.sibling_index, ana.family_size, ana.sibling_discount_applied) == (1, 2, False)
    assert ana.lines[0].discount_pct == Decimal("0")
    assert ana.total == Decimal("100000.00")

    assert (bruno.sibling_index, bruno.family_size, bruno.sibling_discount_applied) == (2, 2, True)
    tuition, transport, ballet = bruno.lines
    assert tuition.service == "tuition"
    assert tuition.discount_pct == Decimal("5.00")
    assert tuition.discount_amount == Decimal("5000.00")
    assert tuition.line_net == Decimal("95000.00")
    # The discount is a tuition benefit; transport and activities stay whole.
    assert transport.discount_pct == Decimal("0")
    assert ballet.discount_pct == Decimal("0")
    assert bruno.subtotal == Decimal("135000.00")
    assert bruno.discount_total == Decimal("5000.00")
    assert bruno.total == Decimal("130000.00")

    assert composition.totals["students"] == 2
    assert composition.totals["discount_total"] == Decimal("5000.00")
    assert composition.totals["total"] == Decimal("230000.00")
    assert composition.totals["families_with_discount"] == 1


def test_a_single_child_never_gets_the_sibling_discount():
    guardian = uuid.uuid4()
    only = _student(uuid.uuid4(), guardian)
    composition = compose_students([only], FeePolicyConfig(), "2026-09")
    student = composition.students[0]
    assert student.family_size == 1
    assert student.sibling_discount_applied is False
    assert student.lines[0].discount_pct == Decimal("0")
    assert composition.totals["families_with_discount"] == 0


def test_sibling_policy_is_configurable_not_hardcoded():
    guardian = uuid.uuid4()
    first = _student(
        uuid.uuid4(), guardian, name="Ana",
        created_at=datetime(2026, 1, 1, 8, tzinfo=timezone.utc),
    )
    second = _student(
        uuid.uuid4(), guardian, name="Bruno",
        created_at=datetime(2026, 1, 1, 9, tzinfo=timezone.utc),
    )

    # A school can require three children, raise the rate, or discount every
    # child instead of only the additional ones.
    threshold = compose_students(
        [first, second],
        FeePolicyConfig(sibling_discount_min_children=3),
        "2026-09",
    )
    assert threshold.totals["discount_total"] == Decimal("0")

    raised = compose_students(
        [first, second],
        FeePolicyConfig(sibling_discount_pct=Decimal("10.00")),
        "2026-09",
    )
    assert raised.student(second.child_id).discount_total == Decimal("10000.00")

    everyone = compose_students(
        [first, second],
        FeePolicyConfig(sibling_discount_scope="all_children"),
        "2026-09",
    )
    assert everyone.student(first.child_id).sibling_discount_applied is True
    assert everyone.student(second.child_id).sibling_discount_applied is True
    assert everyone.totals["discount_total"] == Decimal("10000.00")


# ─── multi-service composition ──────────────────────────────────────────────

def test_tuition_transport_and_two_modalities_compose_into_one_statement():
    student = _student(
        uuid.uuid4(),
        uuid.uuid4(),
        transport=_transport(),
        modalities=(
            _modality("Balé", "15000.00"),
            _modality("Capoeira", "12500.00"),
        ),
    )
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    composed = composition.students[0]

    assert [line.service for line in composed.lines] == [
        "tuition", "transport", "modality", "modality",
    ]
    assert [line.service_label for line in composed.lines] == [
        "Mensalidade", "Rota A", "Balé", "Capoeira",
    ]
    assert composed.lines[1].description == "Transporte — Rota A"
    assert composed.subtotal == Decimal("147500.00")
    assert composed.discount_total == Decimal("0")
    assert composed.net_total == Decimal("147500.00")
    assert composed.total == Decimal("147500.00")
    assert composition.totals["lines"] == 4


def test_iva_is_taken_from_the_catalogue_item_and_tax_metadata_is_carried():
    tuition_item = _catalog(rate="14", tax_option="IVA_14", reason=None)
    student = _student(uuid.uuid4(), uuid.uuid4(), item=tuition_item)
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    line = composition.students[0].lines[0]
    assert line.tax_rate == Decimal("14.00")
    assert line.tax_option_code == "IVA_14"
    assert line.iva_amount == Decimal("14000.00")
    assert line.line_total == Decimal("114000.00")
    assert composition.students[0].total == Decimal("114000.00")


def test_per_student_tuition_override_wins_over_the_catalogue_price():
    student = _student(uuid.uuid4(), uuid.uuid4(), override="120000.00")
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    line = composition.students[0].lines[0]
    assert line.base_unit_price == Decimal("120000.00")
    assert line.unit_price == Decimal("120000.00")
    assert composition.students[0].total == Decimal("120000.00")


# ─── proration ──────────────────────────────────────────────────────────────

def test_student_starting_mid_month_is_prorated_by_calendar_days():
    # September has 30 days; joining on the 16th means 15 billable days.
    student = _student(
        uuid.uuid4(), uuid.uuid4(), starts_on=date(2026, 9, 16),
    )
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    line = composition.students[0].lines[0]
    assert line.proration_factor == Decimal("0.500000")
    assert line.base_unit_price == Decimal("100000.00")
    assert line.unit_price == Decimal("50000.00")
    assert line.line_total == Decimal("50000.00")


def test_proration_rounds_half_up_on_awkward_day_counts():
    # Ten of 30 days -> 0.333333; 100000 x 0.333333 = 33333.30.
    student = _student(
        uuid.uuid4(), uuid.uuid4(),
        starts_on=date(2026, 1, 1), ends_on=date(2026, 9, 10),
    )
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    line = composition.students[0].lines[0]
    assert line.proration_factor == Decimal("0.333333")
    assert line.unit_price == Decimal("33333.30")


def test_full_month_and_no_charge_proration_policies():
    student = _student(
        uuid.uuid4(), uuid.uuid4(), starts_on=date(2026, 9, 16),
    )
    full = compose_students(
        [student], FeePolicyConfig(proration_policy="full_month"), "2026-09",
    )
    assert full.students[0].lines[0].unit_price == Decimal("100000.00")
    assert full.students[0].lines[0].proration_factor is None

    nothing = compose_students(
        [student], FeePolicyConfig(proration_policy="no_charge"), "2026-09",
    )
    assert nothing.students[0].lines == ()
    assert "partial_month_not_charged" in nothing.students[0].warnings
    assert "nothing_to_bill" in nothing.students[0].warnings
    assert nothing.totals["total"] == Decimal("0")


def test_a_student_outside_the_month_gets_no_lines_and_a_warning():
    student = _student(
        uuid.uuid4(), uuid.uuid4(), starts_on=date(2026, 10, 5),
    )
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    composed = composition.students[0]
    assert composed.lines == ()
    assert "not_enrolled_this_month" in composed.warnings
    assert composition.totals["students"] == 1


def test_zero_tuition_is_reported_instead_of_billed():
    student = _student(uuid.uuid4(), uuid.uuid4(), override="0.00")
    composition = compose_students([student], FeePolicyConfig(), "2026-09")
    assert composition.students[0].lines == ()
    assert "tuition_amount_zero" in composition.students[0].warnings


# ─── date helpers ───────────────────────────────────────────────────────────

def test_advance_month_clamps_to_the_shorter_month():
    assert advance_month(date(2026, 1, 31)) == date(2026, 2, 28)
    assert advance_month(date(2024, 1, 31)) == date(2024, 2, 29)
    assert advance_month(date(2026, 3, 31)) == date(2026, 4, 30)
    assert advance_month(date(2026, 12, 15)) == date(2027, 1, 15)


def test_billing_date_clamps_the_configured_day():
    assert billing_date("2026-02", 31) == date(2026, 2, 28)
    assert billing_date("2026-11", 0) == date(2026, 11, 1)
    assert billing_date("2026-10", 10) == date(2026, 10, 10)


def test_month_bounds_rejects_malformed_months():
    assert month_bounds("2026-02") == (date(2026, 2, 1), date(2026, 2, 28))
    with pytest.raises(ValueError):
        month_bounds("2026-13")
    with pytest.raises(ValueError):
        month_bounds("October")


# ─── stable identities ──────────────────────────────────────────────────────

def test_plan_external_id_is_deterministic_and_year_scoped():
    child, year = uuid.uuid4(), uuid.uuid4()
    first = plan_external_id(child, year)
    assert first == plan_external_id(child, year)
    assert first != plan_external_id(child, uuid.uuid4())
    assert first != plan_external_id(uuid.uuid4(), year)
    assert first.version == 5


def test_plan_revision_changes_only_when_the_payload_changes():
    plan = {"external_id": "abc", "template": {"lines": [{"unit_price": "100.00"}]}}
    products = [{"external_id": "p", "data": {"unit_price": "100.00"}}]
    first = _plan_revision({"plan": plan, "products": products})
    assert first == _plan_revision({"plan": plan, "products": products})

    changed = {
        "plan": {"external_id": "abc", "template": {"lines": [{"unit_price": "95.00"}]}},
        "products": products,
    }
    assert first != _plan_revision(changed)
