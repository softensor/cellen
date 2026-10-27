# School finance coverage backlog

Status: working backlog, agreed with the owner on 2026-10-26; updated 2026-10-27 (Phase 0 + Phase 1 implemented, pending release)
Source: client-ask table (items 2.1a–3f) reviewed against Cellen `0218e6c` and FinReg `f62eab5`
Scope: school billing intent in Cellen + fiscal/calculation authority in FinReg

The boundary stays as recorded in `ENGINEERING_AND_FINREG_INTEGRATION_HANDBOOK.md`,
now stated as **Cellen computes, FinReg issues**: Cellen owns school context
(pupils, guardians, academic year, enrollment), the per-school fee policy, the
modality/transport registries and the composition of each student's monthly
charge set; FinReg owns customers, catalogue, tax, numbering, documents,
settlement, receipts, receivables, reports and SAF-T. Every rate, threshold and
period is a per-school policy row, never a constant in code. **No new Cellen
code may emit a locally numbered fiscal document for a FinReg-active school.**

Status legend: ✅ covered · 🛠 implemented, pending release · ⚠️ partial · ❌ missing · 🕘 legacy-only

## 1. Coverage matrix

| # | Client ask | Status today | Verified gap |
|---|---|---|---|
| 2.1a | Admin sets matrícula value | 🛠 Implemented, pending release | Was: in a FinReg school the charge was emitted by Cellen's local fiscal engine (`DocumentEmissionService`), a second issuer and a dual ledger. Now the fee is a durable FinReg billing instruction (`command_type = enrollment_fee`) and settlement is read back from FinReg. |
| 2.1b | Monthly propina value per student | 🛠 Implemented, pending release | `StudentFinanceProfile` stores a per-student tuition override (plus billing guardian/day); the composer resolves override → year price → policy default and computes the plan line automatically. Migration `0034`. |
| 2.2 | Extracurricular inscription + monthly fee, per-student registration | 🛠 Implemented, pending release | `ExtracurricularModality` + `StudentModalityEnrollment` (migration `0034`). Inscription fee is one governed FinReg instruction (`command_type = modality_inscription_fee`) per enrollment; the monthly fee composes into the run. Admin screen and student finance tab included. |
| 2.3 | School transport: monthly value, linked to student, in reports | 🛠 Implemented, pending release | `TransportRoute` + effective-dated `StudentTransportAssignment` (migration `0034`); a route change closes the previous assignment, and the monthly price composes into the run. |
| 2.4 | Late fines 10% (days 10–30) / 15% (from day 10 of the next month), configurable | ❌ Missing | Cellen only flips invoices to overdue. FinReg has no late-fee/interest calculation; Phase 3 adds configurable bands (the director's 10%/15% are editable examples) with a FinReg-issued debit note. |
| 2.5 | 5% sibling discount, configurable, registered on guardian/student | 🛠 Implemented, pending release | Per-school `SchoolFeePolicy`: `sibling_discount_pct` (default 5), minimum children and scope (`additional_children` default / `all_children`). The composer applies it to the additional child's tuition line only; nothing hardcoded. |
| 3a | "Generate debts" button from student profiles | 🛠 Implemented, pending release | `POST /billing/runs/preview` + `POST /billing/runs`, unique per school/year/month; Phase 0 added the FinReg run-now endpoint. The "Gerar Dívidas" screen shows preview, blockers, results and run history. Legacy `/finance/generate*` stays retired under FinReg. |
| 3b | Automatic computation of all amounts due | 🛠 Implemented, pending release | One profile-driven run composes tuition + transport + modalities, with tax treatment taken from each `BillingItem`; matrícula remains the enrollment event under the same policy. Internal-mode parity emits the same amounts. |
| 3c | Automatic fines + discounts | ⚠️ Partial | Sibling discounts are automatic and configurable; late fines remain Phase 3. |
| 3d | Who paid / who is pending | ✅ Covered | Admin invoice status filters, delinquent report with ageing buckets, parent filters, FinReg receivables/statement. |
| 3e | Reports per service type (propinas, transporte, balé, capoeira…) | ⚠️ Partial | FinReg has `GET /reports/sales-by-product` internally, but the integration API exposes only sales-summary, delinquent and SAF-T; Cellen has no native equivalent. |
| 3f | Debts by student and by service type | ⚠️ Partial | Per-guardian statement and delinquent-by-guardian exist; there is no per-student or per-service breakdown in Cellen. |

## 2. Work packages

### Wave 1 — close the compliance defect (2.1a)

**Cellen**
- Build the enrollment-fee payload from the school's active `MATRICULA` billing
  item (product identity, SKU, IVA rate, `finreg_tax_option_code`,
  exemption reason) instead of constructing a local invoice.
- Persist the fee as a durable `FinregBillingInstruction`
  (`command_type = enrollment_fee`) in the same transaction as the enrollment;
  dispatch inline, with retry left to the outbox.
- Add `enrollments.fee_instruction_id` (migration `0033`) and expose
  `fee_instruction_id` / `fee_instruction_status` in `EnrollmentResponse`.
- Keep the enrollment `pending` while the fee is unpaid. Reconcile payment by
  reading FinReg document settlement; activate the enrollment only when the
  invoice is finalized and fully settled.
- Fail closed when the school has no active `MATRICULA` item or the item has no
  governed tax treatment.
- Mobile: show the fiscal-document marker from the instruction as well as the
  legacy invoice id; show issuance status in the payment column.
- Seed `finreg_tax_option_code` on every platform billing item so new schools
  can issue from day one.

**FinReg**
- Add a read-only `GET /integrations/documents/{external_id}/settlement`
  returning gross/paid/outstanding/settled for the mapped document. The generic
  FinReg kit client already supports arbitrary read paths, so no kit release is
  required.

**Acceptance**
- FinReg active + fake mode: creating an enrollment with a fee produces a
  `confirmed` instruction and no local `Invoice`; with the tax option removed
  the request is refused with 422.
- Pilot/live: a settlement on the issued document activates the pending
  enrollment within one dispatcher tick, and a partial settlement does not.
- Non-FinReg schools keep the `InternalPaymentControl` flow unchanged.

**Release order**: FinReg first (additive read endpoint), then Cellen. Neither
step changes the kit pin. Cellen must not dispatch the new flow before the
FinReg endpoint is deployed, or reconciliation logs `404` and retries harmlessly.

### Wave 2 — school service registries (2.2, 2.3) — delivered in Phase 1

Cellen owns the domain tables; FinReg keeps the catalogue and fiscal truth.

- `ExtracurricularModality` (name, inscription fee, monthly fee, billing item,
  active) and `StudentModalityEnrollment` (child, modality, start/end, status);
  the monthly plan line follows the registration. Delivered in migration `0034`.
- `TransportRoute` (name, monthly price, billing item, active) and
  `StudentTransportAssignment` (child, route, start/end, status); a transport
  change closes the old assignment and opens the new one, with the plan line
  following the effective date. Delivered in migration `0034`.
- Both registries surface in the student finance tab and feed the Phase 1
  composer; no new fiscal primitive.
- Reports: the service-type breakdown (3e) will read these registries plus
  FinReg document lines in Phase 2.

### Wave 3 — calculation rules (2.4, 2.5, 3c)

**Cellen computes, FinReg issues.** Phase 1 moved recurring fee composition and
the sibling discount into Cellen as per-school policy (`SchoolFeePolicy`), but
every fiscal document, numbering and settlement stay in FinReg. The remaining
item is late fees.

- **Late fees** (2.4): configuration per school (grace day, first band, second
  band, band boundaries — the director's 10% days 10–30 and 15% from day 10 of
  the next month are editable examples, not constants). Cellen computes from
  FinReg receivable read-backs and enqueues a `late_fee` instruction; FinReg
  issues the debit note per its corrective-document rules. No recalculation of
  an already-issued document.
- **Sibling discount** (2.5): delivered in Phase 1. The composer counts active
  profiles sharing a billing guardian and applies the policy percentage to the
  additional children's tuition lines (or to all children, if configured).
- **Automatic application** (3c): discounts are automatic now; fines will join
  the same deterministic, idempotent per-period run in Phase 3.
- Acceptance must include a golden-case test per band and a replay test proving
  a second run in the same period creates nothing new.

Dependency: FinReg PGCA statutory-interest workstream; align the policy model
with it so there is one interest/fine engine, not two.

### Wave 4 — run and report surfaces (3a, 3b, 3e, 3f)

- **3a run-now — delivered in Phase 1.** FinReg exposes the recurring run
  trigger (`POST /integrations/billing-plans/{external_id}/run` and bulk
  `POST /integrations/billing-plans/run`); Cellen previews and generates from
  the "Gerar Dívidas" screen. The legacy `/finance/generate*` routes stay
  retired under FinReg.
- **3b unified run — delivered in Phase 1.** One action composes all recurring
  amounts per student (tuition, transport, modalities); matrícula remains the
  enrollment event. Per-item success/failure is reported in the run.
- **3e per-service report** (Phase 2): FinReg exposes `sales-by-product` (date
  range, grouping by catalogue item) and Cellen renders it with school terms
  (propinas, transporte, ballet, capoeira).
- **3f student/service debt** (Phase 2): FinReg exposes a per-customer,
  per-document receivable query including the school context (`pupil_id`);
  Cellen groups by student and service type. Do not recompute balances in
  Cellen.

## 3. Sequencing summary

| Wave | Items | Repos | State |
|---|---|---|---|
| 1 | 2.1a | Cellen + FinReg (read endpoint) | 🛠 Implemented, pending release (migration `0033`). |
| Phase 0 | 3a run-now seam | FinReg (route-only, no migration) | 🛠 Implemented on `feat/billing-plan-run-now` (`8fb5b70`, 1768 tests), not pushed. |
| Phase 1 | 2.1b, 2.2, 2.3, 2.5, 3a, 3b | Cellen (migration `0034`) + FinReg Phase 0 | 🛠 Implemented, pending release. FinReg must deploy first. |
| Phase 2 | 3e, 3f, 3d polish | FinReg report/receivable read-backs + Cellen screens | Next. |
| Phase 3 | 2.4, 3c fines | Cellen policy + composer + FinReg debit-note route | Planned; align with the PGCA interest workstream. |
| Phase 4 | Reference payments (principia-pay) | Cellen + rail + FinReg linkage | Planned; reference only against a finalized factura, settlement lands in FinReg. |
| Phase 5 | Dunning + guardian portal | Cellen | Planned. |

## 4. Cross-cutting rules

1. A FinReg-active school never gets a locally numbered Cellen fiscal document.
   Legacy local documents remain readable; the code path is retired.
2. Retries reuse the same `FinregBillingInstruction` id and idempotency key.
   Never mint a new identity to get past an uncertain result.
3. Any new FinReg integration surface is added to the integration router and
   covered by `backend/tests/test_cellen_integration_contract.py`; the kit pin
   only moves when a typed kit resource is required.
4. Cellen renders school terms; FinReg renders fiscal truth. Reports join them
   by the documented mapping tables, never by re-deriving FinReg state.
5. Every item ships with the acceptance checks listed in its work package and a
   release note naming the exact revisions deployed.

## 5. Implementation log

- **2026-10-27 — Phase 0 (FinReg run-now) + Phase 1 (2.1b, 2.2, 2.3, 2.5,
  3a, 3b), pending release.**
  **FinReg** branch `feat/billing-plan-run-now` (`8fb5b70`, "Run a recurring
  billing plan on demand", 1768 tests passed, not pushed): recurring
  generation extracted into `app/services/recurring_generation.py`, shared by
  the Celery beat and the new `POST /integrations/billing-plans/{external_id}/run`
  and bulk `POST /integrations/billing-plans/run` routes; idempotent through
  the existing `(template_id, run_date)` document dedup; non-fiscal clients
  produce drafts only. Route-only, no migration, no kit release. FinReg must
  deploy first.
  **Cellen** (uncommitted working tree): migration `0034_fee_automation`
  (`down_revision = "0033"`) adds `school_fee_policies`,
  `extracurricular_modalities`, `student_modality_enrollments`,
  `transport_routes`, `student_transport_assignments`,
  `student_finance_profiles` and `billing_runs`.
  `app/services/billing_composer.py` composes each month per student (tuition
  override → year price → policy default; transport route; active modalities;
  sibling discount per policy scope on additional children's tuition lines;
  proration as an adjusted unit price; tax fields taken from each
  `BillingItem`). `app/services/billing_run.py` previews with zero FinReg
  calls, generates one `BillingRun` per school/year/month with one
  `billing_run` instruction per plan (`cellen-run-{plan}-{month}` idempotency),
  rebuilds plans by revision and reports per-item results; the dispatcher
  applies confirmed plan results and refreshes open runs, and the daily loop
  runs `auto_generate_due` for schools with `auto_generate` enabled.
  `app/routers/billing.py` adds fee-policy, modality/enrollment,
  transport/assignment, student profile/summary, preview/run/history and
  rebuild endpoints; guardian-link automation maintains the finance profile and
  marks plans stale when the sibling count changes; modality inscription fees
  reuse the Wave-1 instruction pattern (`command_type =
  modality_inscription_fee`); internal-mode schools compose the same amounts
  through the existing control flow. Tests: `tests/test_billing_automation.py`
  (16) and `tests/test_billing_run_api.py` (10); full Cellen suite 420 passed,
  2 skipped. Mobile: `fee_policy_screen`, `modalities_screen`,
  `transport_screen` and `billing_run_screen` (month → preview/blockers →
  generate → result/history), a finance tab in `child_detail_screen`, and a
  reworked `student_billing_plans_screen` with the server-owned plan identity;
  `test/fee_automation_screens_test.dart` (3 widget tests; full mobile suite
  21 passed, `dart format` clean). Migration rehearsed
  against a staged `0033` schema because the local pgserver lacks pgcrypto;
  CI postgres:16 is the full-history gate. Release order: FinReg, then Cellen.

- **2026-10-26 — 2.1a, pending release.** Cellen branch
  `feat/enrollment-fee-finreg`: migration `0033` adds
  `enrollments.fee_instruction_id`; `create_enrollment` pre-validates the
  primary guardian, the active `MATRICULA` catalogue item and its governed tax
  treatment, then stages one `enrollment_fee` instruction and dispatches inline
  (outbox retries the same identity); `list/get/update` expose
  `fee_instruction_status`; the dispatcher activates a pending enrollment when
  `GET /integrations/documents/{id}/settlement` reports `settled` in pilot/live.
  The platform seed now writes `finreg_tax_option_code`, and migration `0033`
  backfills rows created after `0027`. Tests:
  `tests/test_enrollment_fee_finreg.py` (7) and the updated source pins in
  `tests/test_internal_payment_control_unit.py`. FinReg side is the read-only
  settlement route, contract-pinned in
  `backend/tests/test_cellen_integration_contract.py`; FinReg must deploy first.
