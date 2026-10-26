# School finance coverage backlog

Status: working backlog, agreed with the owner on 2026-10-26
Source: client-ask table (items 2.1a–3f) reviewed against Cellen `0218e6c` and FinReg `f62eab5`
Scope: school billing intent in Cellen + fiscal/calculation authority in FinReg

The boundary stays as recorded in `ENGINEERING_AND_FINREG_INTEGRATION_HANDBOOK.md`:
Cellen owns school context (pupils, guardians, academic year, enrollment, plan
intent); FinReg owns customers, catalogue, tax, numbering, documents, settlement,
receipts, receivables, reports and SAF-T. **No new Cellen code may emit a
locally numbered fiscal document for a FinReg-active school.**

Status legend: ✅ covered · 🛠 implemented, pending release · ⚠️ partial · ❌ missing · 🕘 legacy-only

## 1. Coverage matrix

| # | Client ask | Status today | Verified gap |
|---|---|---|---|
| 2.1a | Admin sets matrícula value | 🛠 Implemented, pending release | Was: in a FinReg school the charge was emitted by Cellen's local fiscal engine (`DocumentEmissionService`), a second issuer and a dual ledger. Now the fee is a durable FinReg billing instruction (`command_type = enrollment_fee`) and settlement is read back from FinReg. |
| 2.1b | Monthly propina value per student | ✅ Covered (FinReg) | `StudentBillingPlansScreen` → `PUT /finreg/billing-plans/{id}` → FinReg recurring billing. Caveat: the line price always comes from the catalogue item; a student-specific value is only expressible as a discount. |
| 2.2 | Extracurricular inscription + monthly fee, per-student registration | ⚠️ Partial | Billable through a `BillingItem` (category `activities`) and a plan line. Missing a modality registry: `Activity` is only a timetable label, with no price and no per-student registration. |
| 2.3 | School transport: monthly value, linked to student, in reports | ⚠️ Partial | Billable through a `BillingItem` (category `transport`) and a plan line. Missing the transport service/route/assignment domain; the student link is only the plan line. |
| 2.4 | Late fines 10% (days 10–30) / 15% (from day 10 of the next month), configurable | ❌ Missing | Cellen only flips invoices to overdue. FinReg has no late-fee/interest calculation; its statutory-interest work is still an open PGCA item. |
| 2.5 | 5% sibling discount, configurable, registered on guardian/student | ❌ Missing as a rule | Manual discounts exist end-to-end (contract `discount_percent`/`discount_amount`, plan-line `discount_pct`), but the plan dialog hardcodes 0 and there is no household rule or automatic application. |
| 3a | "Generate debts" button from student profiles | 🕘 Legacy-only | Legacy bulk/per-contract generation exists but returns 409 under FinReg, and the legacy dashboard is URL-only (`/admin/finance/legacy`). FinReg generates on schedule; there is no "run now". |
| 3b | Automatic computation of all amounts due | ⚠️ Partial | Recurring services are automatic through plans; matrícula is a separate path; there is no single profile-driven run. |
| 3c | Automatic fines + discounts | ❌ Missing | Same calculation engine as 2.4/2.5; nothing on either side. |
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

### Wave 2 — school service registries (2.2, 2.3)

Cellen owns the domain tables; FinReg keeps the catalogue and fiscal truth.

- `ExtracurricularModality` (name, category, default price, active) and
  `StudentModalityEnrollment` (child, modality, start/end, billing item,
  discount); generate the monthly plan line from the registration.
- `TransportRoute` (name, monthly price, billing item, active) and
  `StudentTransportAssignment` (child, route, stop, start/end); a transport
  change closes the old assignment and opens the new one, with the plan line
  following the effective date.
- Both registries surface on the student profile and feed the existing
  `PUT /finreg/billing-plans/{id}` payload; no new fiscal primitive.
- Reports: service-type breakdown (3e) reads these registries plus FinReg
  document lines.

Dependency: 3e's per-service report needs FinReg to expose `sales-by-product`
(or an equivalent line-level report) on the integration API; design the
registry first, add the report endpoint in the same release.

### Wave 3 — calculation rules (2.4, 2.5, 3c)

These are fiscal/calculation rules and belong in FinReg, not in Cellen screens.

- **Late fees** (2.4): configuration per company (grace day, first band 10%,
  second band 15%, band boundaries). FinReg computes the charge when a
  receivable becomes overdue and emits a dedicated document/line per its
  corrective-document rules. Cellen only displays the resulting documents and
  the policy configured for the school.
- **Sibling discount** (2.5): a household rule (guardian + children + rank)
  evaluated when a plan line is generated. Cellen supplies the household
  relation; FinReg applies the discount to the line and records the reason.
- **Automatic application** (3c): one FinReg generation run applies late fees
  and household discounts in a deterministic order and is idempotent per
  period. It must not recalculate an already-issued document; corrections use
  the existing corrective-document workflow.
- Acceptance must include a golden-case test per band and a replay test proving
  a second run in the same period creates nothing new.

Dependency: FinReg PGCA statutory-interest workstream; align the policy model
with it so there is one interest/fine engine, not two.

### Wave 4 — run and report surfaces (3a, 3b, 3e, 3f)

- **3a run-now**: expose FinReg's recurring-billing run trigger through the
  integration API (`POST /billing-plans/{id}/run` or equivalent) and add a
  "Gerar agora" action on the Cellen student profile. It must return the run
  result and be idempotent; the legacy `/finance/generate*` routes stay retired
  under FinReg.
- **3b unified run**: one action that generates all due amounts for a student
  (matrícula when still open, recurring plan lines, service lines) through
  FinReg; report per-item success/failure instead of a single boolean.
- **3e per-service report**: FinReg exposes `sales-by-product` (date range,
  grouping by catalogue item) and Cellen renders it with school terms
  (propinas, transporte, ballet, capoeira).
- **3f student/service debt**: FinReg exposes a per-customer, per-document
  receivable query including the school context (`pupil_id`); Cellen groups by
  student and service type. Do not recompute balances in Cellen.

## 3. Sequencing summary

| Wave | Items | Repos | Why now |
|---|---|---|---|
| 1 | 2.1a | Cellen + FinReg (read endpoint) | Live compliance risk: a FinReg pilot school currently issues matrícula outside FinReg. |
| 2 | 2.2, 2.3, 3e | Cellen (+ FinReg report endpoint) | Unlocks the service-type reporting ask and removes spreadsheet workarounds. |
| 3 | 2.4, 2.5, 3c | FinReg (+ Cellen display) | Fiscal calculation; must align with the PGCA interest workstream. |
| 4 | 3a, 3b, 3f | FinReg + Cellen | Operational convenience once the calculation engine is authoritative. |

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
