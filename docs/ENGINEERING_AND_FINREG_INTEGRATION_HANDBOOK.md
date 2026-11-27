# Cellen Engineering and Finreg Integration Handbook

Status: canonical starting point for Cellen engineers and operators
Last reviewed: 2026-11-27 (headless invoicing: docs/FINREG_HEADLESS_INVOICING_PLAN.org)

## 1. Purpose

This handbook explains how to extend Cellen safely, how Cellen integrates the
generic Finreg product, and how to release and deploy both repositories without
creating a second or stale financial implementation.

Read the companion Finreg handbook first when a change affects finance:
`finreg/docs/ENGINEERING_AND_OPERATIONS_HANDBOOK.md`.

## 2. Product boundary

Cellen owns the school domain: schools, pupils, guardians, academic context,
communication, attendance, teaching, school-specific billing intent, and the
user experience that connects those concepts.

Finreg owns fiscal and financial truth: customers/parties, catalogue items,
documents, numbering, taxes, settlements, receipts, accounting, audit evidence,
SAF-T, and AGT workflows.

The integration rule is:

```text
Cellen school context and Cellen UI (the only interface a school sees)
  + pinned finreg-kit (backend connector, server to server)
  -> Finreg integration API and database (fiscal authority)
  -> FinregDocument ledger in Cellen (read model of what Finreg returned)
```

Finreg is headless for schools: Cellen's own screens list, open, issue,
correct and export fiscal documents, and Finreg does the fiscal work in the
background. Cellen never recreates Finreg's fiscal state machine: every
number, total, status, PDF and SAF-T file shown in Cellen was returned by
Finreg. Generic fiscal defects are fixed in Finreg and consumed through the
pinned connector kit.

## 3. Non-negotiable integration rules

1. Finreg is a separate product, repository, backend, database, Web release,
   and fiscal authority.
2. Cellen never generates official numbering, tax totals, receipts, accounting
   entries, or SAF-T independently for new Finreg-managed documents.
3. Cellen does not embed or launch Finreg UI. All Finreg interaction is
   server to server through the integrations API; the school never sees
   Finreg.
4. The backend consumes `softensor/finreg-kit` at the exact commit SHA in
   `.github/finreg-kit-ref`. The Flutter tree has no Finreg dependency; the
   legacy `.github/finreg-packages-ref` pin is only the source revision the
   backend contract tests read module manifests from.
5. Finreg credentials and tokens never reach the client.
6. Cellen owns all finance navigation. Native screens map to Finreg
   integration endpoints; there are no Finreg deep links.
7. Fiscal actions are native Cellen screens that call Finreg through the
   backend. Totals shown before issuing come from Finreg's preview; Cellen
   never computes tax. Fiscal mutations go through the outbox.
8. UI permission checks improve navigation; Finreg API permission, scope,
   tenant, and capability enforcement remains authoritative.
9. Integration mutations retain their instruction UUID/idempotency key across
   retries. Never create a new identity to bypass an uncertain result.
10. `shadow`, `pilot`, and `live` are controlled operational states—not UI
    labels—and promotion uses the guarded scripts.

Detailed authority is recorded in
[CELLEN_FINREG_AUTHORITY_MATRIX.org](CELLEN_FINREG_AUTHORITY_MATRIX.org) and
[FINREG_CELLEN_ARCHITECTURE_SPEC.org](FINREG_CELLEN_ARCHITECTURE_SPEC.org).

## 4. Repository map

| Path | Responsibility |
|---|---|
| `app` | Cellen FastAPI backend and school-domain services |
| `alembic/versions` | Cellen database migrations |
| `mobile` | Flutter application for Web/mobile clients |
| `mobile/lib/core/router/router.dart` | Cellen route composition |
| `mobile/lib/features/admin/finance/school_finance_screen.dart` | The school finance shell (tabs); never depends on Finreg being reachable |
| `mobile/lib/features/admin/finance/fiscal/` | Native fiscal screens: invoices, credit notes, receipts, statement, SAF-T, fiscal log, setup |
| `app/routers/finreg_admin.py` | Backend for the native fiscal screens (`/finreg/admin/*`) |
| `app/services/finreg_ledger.py` | `FinregDocument` read model: fed by the outbox, events and refreshes |
| `app/services/finreg_errors.py` | Finreg failures translated to school language |
| `.github/finreg-kit-ref` | Immutable `softensor/finreg-kit` commit consumed by CI and every deploy |
| `.github/finreg-packages-ref` | Finreg source revision read by backend contract tests (manifest fixtures) |
| `.github/workflows/backend_tests.yml` | Backend required checks |
| `.github/workflows/flutter_build.yml` | Android, iOS, Web, current implementation validation, and package checkout |
| `deploy` | VPS migration, service, promotion, validation, and release entry points |
| `tests/test_finreg_integration_unit.py` | Cross-boundary integration regression tests |
| `docs` | Architecture, rollout, authority, and operator references |

Backend CI checks out `softensor/finreg-kit` at the pin using the read-only
`FINREG_READ_TOKEN` Actions secret, installs it into the test venv, and keeps a
`softensor/finreg` source checkout at `finreg-packages-ref` only so the
manifest-validation tests can read `backend/app/module_manifests/*.json`. The
Flutter builds check out neither repository: Finreg is not a mobile dependency.
Never point CI at a moving branch.

## 5. Request and UI composition

### Admin surface: native fiscal screens

The admin finance routes (`/admin/finance/invoices`, `credit-notes`,
`receipts`, `statement`, `saft`, `audit-log`, `fiscal-setup`) are Cellen
screens backed by `/api/v1/finreg/admin/*`:

- documents are listed from the local `FinregDocument` ledger, which the
  outbox fills on confirmation, the event poller updates, and a refresh pass
  re-reads from Finreg while a document can still change (draft, pending AGT);
- the official PDF and receipts are streamed from Finreg on demand;
- corrections (credit notes) are outbox instructions (`correction`) with one
  request id per dialog, so an unknown outcome is resent, never duplicated;
- one-off invoices show Finreg's `preview` totals, then issue under the same
  request id;
- every Finreg failure is shown through `finreg_errors.explain`.

There is no delegated launch: the `workspace-launch` route and the
`workspace:launch` scope are gone from Cellen.

### Parent surface: native Cellen screens

Guardians stay in Cellen. The parent routes proxy the integration API
(`/finreg/parent/documents`, `/finreg/parent/receipts`, `/finreg/parent/statement`
and the PDF downloads) and render documents, receipts, balances and statements
in native screens.

### Backend connector: finreg-kit

`app/services/finreg.py` wraps `softensor/finreg-kit`. `FINREG_BASE_URL` is the
Finreg origin (no `/api/v1`); the kit appends `/api/v1/integrations`. Requests
carry a scope bundle instead of a per-call token: `_READ_SCOPES`,
and `_WRITE_SCOPES`, one token per bundle per actor, cached
per (origin, client id, secret fingerprint, actor). Finreg caps token mints at
10 per client per 15 minutes; the bundles keep even a busy school far below
that. `actor_reference` stays in the JWT so Finreg audits per user.

The integration uses versioned school context, scoped OAuth credentials stored
server-side, idempotency keys, mappings, an outbox/event cursor, and capability
negotiation. Client secrets must never be compiled into Flutter or returned to
the browser.

## 6. Choosing where to make a change

| Requirement | Change first |
|---|---|
| Generic invoice, POS, product, customer, payment, receipt, report, or UI-state defect | Finreg |
| Tax, numbering, issuance, correction, AGT, audit, accounting, or SAF-T | Finreg with compliance review |
| A fiscal screen in Cellen needs data Finreg does not expose | Finreg integration API, then the kit pin, then Cellen |
| Pupil/guardian mapping or school billing context | Cellen integration layer |
| Attendance, teaching, communication, or unrelated school workflow | Cellen |
| School wording around an authoritative Finreg workflow | Usually profile/localization; avoid page duplication |

If both repositories change, Finreg is released first and Cellen pins the
resulting exact commit.

## 7. Extension procedure

### 7.1 Generic Finreg functionality

1. Implement and validate the change in `/Users/jorgehel/projects/finreg`.
2. Ensure the page is available through the stable Finreg route/capability.
3. Add actual widget/interaction and backend contract tests.
4. If the change alters an integration-client route, release the kit with the
   matching resource/operation and pin the new kit SHA.
5. Release Finreg through a PR and obtain the immutable commit/artifact.
6. Update `.github/finreg-kit-ref` (and `.github/finreg-packages-ref` for the
   manifest fixtures) in Cellen.
7. A new fiscal capability the school needs is a native Cellen screen over
   the integration API, never a link into Finreg.
8. Validate Cellen backend, Flutter, Web, and integration tests against the pin.

### 7.2 School-specific functionality

1. Define the school-domain source of truth and its Finreg external context.
2. Add migration-safe Cellen persistence if required.
3. Use confirmed mappings between Cellen and Finreg entities.
4. Dispatch integration mutations through the durable, idempotent adapter.
5. Represent pending, confirmed, failed, and unknown outcomes explicitly.
6. Add permission, school isolation, retry, and reconciliation tests.
7. Keep the official financial result in Finreg.

### 7.3 UI quality requirements

- Every action has real state handling: idle, progress, success, and governed
  failure.
- Critical actions cannot be double-submitted.
- Navigation preserves the requested current route.
- Delegated users never see standalone Finreg login.
- Errors are localized and do not expose raw exceptions.
- Browser back/forward and refresh retain a valid route/session outcome.
- Narrow and wide layouts remain usable.
- Tests exercise the current implementation; do not preserve obsolete UI
  simply because an old source-contract test expects it.

## 8. Local development and validation

For Cellen backend changes:

```bash
cd /Users/jorgehel/projects/cellen
git status --short
git diff --check
./.venv/bin/pytest
./.venv/bin/alembic heads
```

For backend work install the connector kit editable once into the venv:

```bash
cd /Users/jorgehel/projects/cellen
./.venv/bin/pip install -e ../finreg-kit
./.venv/bin/pytest tests/test_finreg_kit_adapter.py
```

For Flutter changes no Finreg checkout is needed:

```bash
cd /Users/jorgehel/projects/cellen/mobile
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build web --release
```

Run targeted Cellen integration tests after any fiscal screen or integration change:

```bash
cd /Users/jorgehel/projects/cellen
./.venv/bin/pytest tests/test_finreg_integration_unit.py tests/test_finreg_ledger.py tests/test_finreg_errors.py
```

Warnings should be maintained as technical debt, but compiler errors, test
failures, stale dependency pins, and skipped required browser contracts block a
release.

## 9. Cross-repository release

Finreg and Cellen now release independently.

- A Finreg change that alters the integration API is released in Finreg first,
  then `softensor/finreg-kit` is released with the matching operation and Cellen
  pins the new kit SHA.
- A change confined to Finreg's own UI never reaches schools: they only use
  Cellen's screens.
- A Cellen-only change (school domain, native screens) needs no Finreg
  release and no Finreg restart.

The Finreg repository still owns its own Web artifact release and identity
verification. Remain at the terminal for SSH authentication. A line saying that
release gates passed does not mean production was deployed; GitHub publication,
artifact transfer, and VPS activation are separate stages.

### Resume after SSH interruption

If both PRs are merged and the interruption occurred at `Authenticate now`, do
not republish the code. Resume only the artifact transfer from the Mac:

```bash
cd /Users/jorgehel/projects/finreg
FINREG_SHA=$(cat /Users/jorgehel/projects/cellen/.github/finreg-packages-ref)
WEB_DIR="/tmp/finreg-web-$FINREG_SHA"

test -f "$WEB_DIR/finreg-release.json"
grep -F "\"commit\":\"$FINREG_SHA\"" "$WEB_DIR/finreg-release.json"
ssh jorgehel@167.235.158.77 true
rsync -az --partial --timeout=180 \
  -e "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=6" \
  "$WEB_DIR/" "jorgehel@167.235.158.77:$WEB_DIR/"
```

If the artifact is absent, download it from the successful Finreg `master`
release run using `scripts/download-web-release.sh`; do not rebuild an
unidentified local directory and call it the released artifact.

## 10. Production VPS topology

This is sanitized, time-sensitive operational data. Verify live state before a
destructive or fiscal action.

| Item | Value |
|---|---|
| Host | `jorgehel-vps` / `167.235.158.77` |
| Cellen checkout | `/var/www/cellen` |
| Cellen environment | `/var/www/cellen/.env` |
| Cellen virtualenv | `/var/www/cellen/.venv` |
| Cellen database | PostgreSQL `cellen` |
| Cellen service/API | `cellen-api`, `127.0.0.1:8001` |
| Cellen public API origin | `https://167.235.158.77.nip.io` |
| Finreg checkout | `/var/www/finreg` |
| Finreg environment | `/etc/finreg.env` |
| Finreg database | PostgreSQL `finreg` |
| Finreg services/API | `finreg-api`, `finreg-worker`, one `finreg-beat`, `127.0.0.1:8003` |
| Finreg public origin | `https://finreg.167.235.158.77.nip.io` |
| Integration secret file | `/etc/cellen-finreg-client-secret` |
| Connector kit checkout | `/var/www/finreg-kit` (read-only mirror, fetched at deploy) |
| Acceptance evidence | `/home/jorgehel/backups/cellen-finreg-acceptance-*.org` |
| Other reserved port | `8002` (Condo Manager) |

Required Cellen configuration names include `FINREG_BASE_URL`,
`FINREG_WEB_URL`, `FINREG_CLIENT_ID`, `FINREG_CLIENT_SECRET_FILE`,
`FINREG_TIMEOUT_SECONDS`, `FINREG_VERIFY_TLS`, optional `FINREG_TLS_CA_FILE`,
and `FINREG_INTEGRATION_ENABLED`. `FINREG_BASE_URL` is the Finreg origin, not
the API mount point: a legacy value ending in `/api/v1` is normalized, but new
deployments write the origin. `FINREG_WEB_URL` and `CELLEN_WEB_URL` are no longer used by
the integration (there is no delegated launch). Document names, never secret
values.

## 11. VPS deployment

Every Cellen deploy needs the connector kit installed in the venv, because
`app.services.finreg` imports it at startup. Both release scripts read the
40-hex `.github/finreg-kit-ref`, verify the commit exists in
`/var/www/finreg-kit`, export the pinned tree with `git archive`, and
`pip install --no-deps --force-reinstall` it into `/var/www/cellen/.venv`.

A Cellen-only release:

```bash
ssh jorgehel@167.235.158.77
cd /var/www/cellen
git switch master
git pull --ff-only origin master
sudo bash deploy/release_cellen_from_vps.sh <expected-master-sha>
```

The Cellen/kit cutover window (no Finreg code, migration or restart; only the
additive scope grant and manifest fingerprint refresh touch Finreg data):

```bash
cd /var/www/cellen
sudo bash deploy/deploy_finreg_school_finance.sh --cellen-only
```

A release that also changes Finreg (the script restarts all four services):

```bash
cd /var/www/cellen
sudo bash deploy/release_cellen_finreg_from_vps.sh
```

`release_cellen_finreg_from_vps.sh` fast-forwards both repositories, verifies
the transferred Finreg Web artifact, runs `deploy_finreg_school_finance.sh`,
activates the Web release, validates its identity, and checks all four services
and both APIs.

Do not deploy by copying source directories, manually replacing the active Web
directory, or running a feature branch on the VPS.

## 12. Acceptance and operational modes

The combined acceptance suite is:

```bash
cd /var/www/cellen
sudo bash deploy/validate_cellen_finreg_release.sh --mode pilot --agt-channel offline
```

Use the actual controlled state when appropriate (Rainha Njinga runs `pilot` /
`offline`; `shadow` was only the initial provisioning mode):

- `shadow` requires AGT `disabled` and non-fiscal draft behaviour.
- `pilot` allows only the documented `offline` or approved `sandbox` channel.
- `live` requires AGT `production`, complete credentials, confirmed series,
  reconciliation, and external approval.

Promotions use the scripts in `deploy/promote_finreg_pilot.sh`,
`deploy/promote_finreg_agt_sandbox.sh`, and `deploy/promote_finreg_live.sh`.
Never change mode directly in the database merely to pass acceptance.

The acceptance report checks repositories, services, health, migrations,
tenant/profile fingerprint, scopes, secret permissions, mapping/outbox errors,
scheduler idempotency, SAF-T authority, and new journal errors. A non-zero
failure count blocks release acceptance.

## 13. Verification and incident response

Read-only first response:

```bash
systemctl status cellen-api finreg-api finreg-worker finreg-beat --no-pager
curl -fsS http://127.0.0.1:8001/health
curl -fsS http://127.0.0.1:8003/ready
curl -fsS https://finreg.167.235.158.77.nip.io/finreg-release.json
journalctl -u cellen-api -u finreg-api -u finreg-worker -u finreg-beat \
  --since "10 minutes ago" --no-pager
```

For an integration outage:

1. preserve logs, correlation IDs, instruction UUIDs, and current modes;
2. close the Cellen kill switch if new dispatches are unsafe;
3. do not delete the outbox or mappings;
4. restore connectivity and verify Finreg `/capabilities`;
5. retry the same durable records with the same identifiers;
6. reconcile confirmed, failed, and unknown outcomes before reopening writes.

For an issued-document error, use Finreg corrective workflows. Never update the
issued content from Cellen or directly in PostgreSQL.

## 14. Definition of done

A Cellen/Finreg change is complete only when:

- the ownership matrix is respected;
- Cellen pins the reviewed exact Finreg SHA;
- the native fiscal screens show the change without opening Finreg, and every
  value they show was returned by Finreg;
- parent document, receipt and statement screens work natively from the
  integration proxy;
- backend, Flutter, Web, Android/iOS as applicable, and integration tests pass;
- both exact `master` revisions have successful required workflows;
- the immutable Finreg artifact matches the deployed release metadata;
- VPS migrations, services, health checks, acceptance, and journals pass;
- no secret or production payload was committed or printed.

## 15. Authoritative references

- [FINREG_CELLEN_INDEX.org](FINREG_CELLEN_INDEX.org)
- [FINREG_CELLEN_ARCHITECTURE_SPEC.org](FINREG_CELLEN_ARCHITECTURE_SPEC.org)
- [CELLEN_FINREG_AUTHORITY_MATRIX.org](CELLEN_FINREG_AUTHORITY_MATRIX.org)
- [FINREG_INTEGRATION_RUNBOOK.org](FINREG_INTEGRATION_RUNBOOK.org)
- [CROSS_REPOSITORY_MODULE_RELEASE_RUNBOOK.org](CROSS_REPOSITORY_MODULE_RELEASE_RUNBOOK.org)
- [FINREG_AGT_MODE_RUNBOOK.org](FINREG_AGT_MODE_RUNBOOK.org)
- [SERVER_DEPLOYMENT_CONFIG.org](SERVER_DEPLOYMENT_CONFIG.org)
- [GITHUB_TERMINAL_RELEASE_RUNBOOK.org](GITHUB_TERMINAL_RELEASE_RUNBOOK.org)

When documentation and deployed code disagree, stop and inspect the exact
release. Architecture and compliance documents own boundaries and fiscal
controls; version-controlled scripts own the mechanical release sequence; live
credentials and modes remain external operational state.
