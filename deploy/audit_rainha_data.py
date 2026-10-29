#!/usr/bin/env python3
"""Read-only audit of the Rainha Njinga test school, Cellen and FinReg.

Run on the VPS as the postgres OS user so both databases can be read over
the local socket without a password:

    sudo -u postgres /var/www/cellen/.venv/bin/python - < audit_rainha_data.py

(pipe the file in over ssh as in the hand-off command). It only issues
SELECTs. The output is the basis for the reset plan: how many people, how
much local finance, which FinReg documents/receivables exist, and the
connection mode.
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
from uuid import UUID

import asyncpg

DEFAULT_SLUG = "rainha-njinga"
DEFAULT_SCHOOL_ID = UUID("65794af5-2831-4709-9b53-437bb5d50515")


def money(value) -> str:
    return f"{float(value or 0):,.2f}"


def header(title: str) -> None:
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


async def table_counts(conn: asyncpg.Connection, column: str, value) -> list[tuple[str, int]]:
    rows = await conn.fetch(
        """
        select table_name
        from information_schema.columns
        where table_schema = 'public' and column_name = $1
        order by table_name
        """,
        column,
    )
    out: list[tuple[str, int]] = []
    for row in rows:
        name = row["table_name"]
        try:
            count = await conn.fetchval(
                f'select count(*) from public."{name}" where "{column}" = $1', value
            )
        except asyncpg.PostgresError as exc:  # pragma: no cover - defensive
            out.append((f"{name} (ERROR: {exc})", -1))
            continue
        out.append((name, count))
    return out


def print_counts(counts: list[tuple[str, int]], *, show_zero: bool = False) -> None:
    shown = [(name, n) for name, n in counts if n != 0 or show_zero]
    if not shown:
        print("  (no scoped tables found)")
        return
    width = max(len(name) for name, _ in shown)
    for name, n in shown:
        print(f"  {name:<{width}}  {n}")


async def grouped(conn: asyncpg.Connection, sql: str, *args) -> None:
    rows = await conn.fetch(sql, *args)
    if not rows:
        print("  (none)")
        return
    for row in rows:
        print("  " + " | ".join(str(v) for v in row.values()))


async def audit_cellen(dsn: str, slug: str) -> UUID | None:
    conn = await asyncpg.connect(dsn)
    try:
        header(f"Cellen — school '{slug}'")
        school = await conn.fetchrow(
            "select id, name, slug, currency, is_active, features from public.schools where slug = $1",
            slug,
        )
        if school is None:
            print(f"  SCHOOL NOT FOUND for slug '{slug}'")
            return None
        school_id = school["id"]
        print(f"  id:       {school_id}")
        print(f"  name:     {school['name']}")
        print(f"  currency: {school['currency']}   active: {school['is_active']}")
        print(f"  features: {school['features']}")
        if school_id != DEFAULT_SCHOOL_ID:
            print(
                f"  ATTENTION: expected school id {DEFAULT_SCHOOL_ID}; "
                "this is a different school."
            )

        print("\n-- school years")
        await grouped(
            conn,
            "select id, year_label, start_date, end_date, is_active "
            "from public.school_years where school_id = $1 order by start_date",
            school_id,
        )

        print("\n-- users by roles")
        await grouped(
            conn,
            "select roles::text as roles, count(*) as users "
            "from public.users where school_id = $1 group by roles order by roles::text",
            school_id,
        )

        print("\n-- people and family links")
        for sql in (
            "select count(*) as guardians from public.guardians where school_id = $1",
            "select count(*) as children, count(*) filter (where is_active) as active "
            "from public.children where school_id = $1",
            "select count(*) as child_guardian_links from public.child_guardians where school_id = $1",
            "select count(*) as enrollments, count(*) filter (where status = 'active') as active "
            "from public.enrollments where school_id = $1",
            "select count(*) as student_finance_profiles from public.student_finance_profiles where school_id = $1",
            "select count(*) as contracts from public.contracts where school_id = $1",
        ):
            print("  " + " | ".join(f"{k}={v}" for k, v in (await conn.fetchrow(sql, school_id)).items()))

        print("\n-- finance state")
        await grouped(
            conn,
            "select status, count(*) as runs, coalesce(sum((stats->>'skipped')::int), 0) as skipped "
            "from public.billing_runs where school_id = $1 group by status order by status",
            school_id,
        )
        await grouped(
            conn,
            "select status, count(*) as instructions from public.finreg_billing_instructions "
            "where school_id = $1 group by status order by status",
            school_id,
        )
        await grouped(
            conn,
            "select document_type, status, count(*) as invoices, "
            "coalesce(sum(gross_total), 0) as gross_total "
            "from public.invoices where school_id = $1 "
            "group by document_type, status order by document_type, status",
            school_id,
        )
        await grouped(
            conn,
            "select status, count(*) as payments, coalesce(sum(amount), 0) as amount "
            "from public.payments where school_id = $1 group by status order by status",
            school_id,
        )
        await grouped(
            conn,
            "select provider, status, count(*) as references, "
            "coalesce(sum(amount), 0) as amount "
            "from public.payment_references where school_id = $1 "
            "group by provider, status order by provider, status",
            school_id,
        )
        await grouped(
            conn,
            "select status, count(*) as plans from public.payment_plans "
            "where school_id = $1 group by status order by status",
            school_id,
        )
        await grouped(
            conn,
            "select category, status, count(*) as controls, "
            "coalesce(sum(amount), 0) as amount "
            "from public.internal_payment_controls where school_id = $1 "
            "group by category, status order by category, status",
            school_id,
        )

        print("\n-- FinReg connection")
        conn_row = await conn.fetchrow(
            "select finreg_company_id, mode, kill_switch, last_event_sequence, last_sync_at "
            "from public.finreg_school_connections where school_id = $1",
            school_id,
        )
        if conn_row is None:
            print("  (no connection row — school is in internal mode)")
        else:
            for key, value in conn_row.items():
                print(f"  {key}: {value}")
        principal = await conn.fetchrow(
            "select status, client_id, last_error from public.principia_pay_connections "
            "where school_id = $1",
            school_id,
        )
        print(f"  principia-pay: {dict(principal) if principal else '(none)'}")

        print("\n-- every Cellen table scoped by school_id (non-zero)")
        counts = await table_counts(conn, "school_id", school_id)
        print_counts(counts)

        print("\n-- dependent tables without school_id")
        dep = {
            "invoice_lines": (
                "select count(*) from public.invoice_lines il "
                "join public.invoices i on i.id = il.invoice_id where i.school_id = $1"
            ),
            "payment_allocations": (
                "select count(*) from public.payment_allocations pa "
                "join public.payments p on p.id = pa.payment_id where p.school_id = $1"
            ),
            "payment_plan_installments": (
                "select count(*) from public.payment_plan_installments ppi "
                "join public.payment_plans pp on pp.id = ppi.plan_id where pp.school_id = $1"
            ),
        }
        for name, sql in dep.items():
            print(f"  {name}: {await conn.fetchval(sql, school_id)}")

        return conn_row["finreg_company_id"] if conn_row else None
    finally:
        await conn.close()


async def audit_finreg(dsn: str, company_id: UUID | None) -> None:
    conn = await asyncpg.connect(dsn)
    try:
        header("FinReg — company")
        if company_id is None:
            print("  SKIPPED: Cellen has no FinReg company id for this school.")
            return
        company = await conn.fetchrow(
            "select id, name, tax_id, agt_channel, vertical_profile, is_active "
            "from public.companies where id = $1",
            company_id,
        )
        if company is None:
            print(f"  COMPANY NOT FOUND: {company_id}")
            return
        for key, value in company.items():
            print(f"  {key}: {value}")

        print("\n-- document series (numbering)")
        await grouped(
            conn,
            "select document_type, series_code, next_number, is_active, agt_remote_status "
            "from public.document_series where company_id = $1 "
            "order by document_type, series_code",
            company_id,
        )

        print("\n-- documents")
        await grouped(
            conn,
            "select document_type, issuance_environment, document_status, "
            "count(*) as documents, coalesce(sum(gross_total), 0) as gross_total "
            "from public.documents where company_id = $1 "
            "group by document_type, issuance_environment, document_status "
            "order by document_type, issuance_environment, document_status",
            company_id,
        )

        print("\n-- payments")
        await grouped(
            conn,
            "select count(*) as payments, coalesce(sum(amount), 0) as amount "
            "from public.payments where company_id = $1",
            company_id,
        )

        print("\n-- payment references")
        await grouped(
            conn,
            "select provider, status, count(*) as references, "
            "coalesce(sum(amount), 0) as amount "
            "from public.payment_references where company_id = $1 "
            "group by provider, status order by provider, status",
            company_id,
        )

        print("\n-- integration receivables / settlements")
        await grouped(
            conn,
            "select status, count(*) as receivables, "
            "coalesce(sum(amount - paid_amount), 0) as outstanding "
            "from public.integration_receivables where company_id = $1 "
            "group by status order by status",
            company_id,
        )
        await grouped(
            conn,
            "select count(*) as settlements, coalesce(sum(amount), 0) as amount "
            "from public.integration_settlements where company_id = $1",
            company_id,
        )

        print("\n-- customers / templates / mappings")
        for sql in (
            "select count(*) as customers from public.customers where company_id = $1",
            "select count(*) as recurring_templates from public.recurring_invoice_templates where company_id = $1",
            "select count(*) as entity_mappings from public.external_entity_mappings where company_id = $1",
            "select count(*) as integration_events from public.integration_events where company_id = $1",
            "select count(*) as idempotency_records from public.integration_idempotency_records where company_id = $1",
        ):
            print("  " + " | ".join(f"{k}={v}" for k, v in (await conn.fetchrow(sql, company_id)).items()))

        print("\n-- go-live archives")
        await grouped(
            conn,
            "select status, count(*) as archives, coalesce(sum(row_count), 0) as rows "
            "from public.go_live_archives where company_id = $1 "
            "group by status order by status",
            company_id,
        )

        print("\n-- every FinReg table scoped by company_id (non-zero)")
        counts = await table_counts(conn, "company_id", company_id)
        print_counts(counts)
    finally:
        await conn.close()


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", default=os.environ.get("CELLEN_SCHOOL_SLUG", DEFAULT_SLUG))
    parser.add_argument(
        "--cellen-dsn",
        default=os.environ.get("CELLEN_DSN", "postgresql:///cellen"),
    )
    parser.add_argument(
        "--finreg-dsn",
        default=os.environ.get("FINREG_DSN", "postgresql:///finreg"),
    )
    args = parser.parse_args()

    try:
        company_id = await audit_cellen(args.cellen_dsn, args.slug)
        await audit_finreg(args.finreg_dsn, company_id)
    except asyncpg.PostgresError as exc:
        print(f"AUDIT FAILED: {exc}", file=sys.stderr)
        sys.exit(2)
    print("\nAudit complete (read-only; nothing was changed).")


if __name__ == "__main__":
    asyncio.run(main())
