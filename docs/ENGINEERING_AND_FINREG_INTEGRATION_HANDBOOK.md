# Cellen Engineering and Finreg Integration Handbook

Status: canonical starting point for Cellen engineers and operators
Last reviewed: 2026-10-26

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
Cellen school context
  + delegated identity and permissions
  + pinned finreg-kit (backend connector)
  -> Finreg integration API and database (fiscal authority)
  -> single-use delegated launch of standalone Finreg in the browser
```

Cellen must not maintain a reduced copy of a Finreg page or recreate its state
machine. Generic defects are fixed in Finreg and consumed through the pinned
connector kit on the backend and the delegated launch in the browser.
Cellen-specific presentation may frame, label, or add school context, but the
authoritative Finreg workflow runs inside Finreg itself.

## 3. Non-negotiable integration rules

1. Finreg is a separate product, repository, backend, database, Web release,
   and fiscal authority.
2. Cellen never generates official numbering, tax totals, receipts, accounting
   entries, or SAF-T independently for new Finreg-managed documents.
3. Cellen does not embed Finreg packages. The admin surface is a launcher:
   Finreg opens standalone after a single-use delegated code is exchanged.
4. The backend consumes `softensor/finreg-kit` at the exact commit SHA in
   `.github/finreg-kit-ref`. The Flutter tree has no Finreg dependency; the
   legacy `.github/finreg-packages-ref` pin is only the source revision the
   backend contract tests read module manifests from.
5. The host mints a launch with the external user id, display name and host
   roles; it never passes Finreg credentials or tokens to the client.
6. Deep links land on the corresponding Finreg workspace home (for example
   `/admin/finance/invoices` selects the billing workspace). Cellen does not
   synthesize Finreg sub-page routes; the admin navigates inside Finreg.
7. Cellen-native screens are appropriate for school context such as student
   billing plans or guardian collection views. Fiscal actions still call
   Finreg.
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
| `mobile/lib/features/admin/finance/finreg_sales_host_screen.dart` | Finreg workspace launcher ("Abrir no FinReg") plus Cellen-native school finance surfaces |
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

### Admin surface: delegated launch

The host reads the authoritative Finreg manifest through the backend
(`GET /api/v1/finreg/capabilities`), shows one tab per operational workspace,
and on tap calls `POST /api/v1/finreg/workspace-launch/{capability_id}`. The
backend asks Finreg for a single-use delegated launch (scope `workspace:launch`,
60-second code) and returns `{url, target_path, expires_in}`. The app opens that
URL in the system browser with `LaunchMode.externalApplication`
(`webOnlyWindowName: '_blank'` on web); Finreg exchanges the code, establishes
the delegated session, and renders the workspace.

No Finreg token, client secret, or SDK type ever reaches the client. Deep links
(`/admin/finance/invoices`, `/admin/finance/receipts`, …) select the matching
workspace tab via `initialCapabilityId`; the landing sub-page is Finreg's own
workspace home, by the accepted workspace-level decision.

### Parent surface: native Cellen screens

Guardians stay in Cellen. The parent routes proxy the integration API
(`/finreg/parent/documents`, `/finreg/parent/receipts`, `/finreg/parent/statement`
and the PDF downloads) and render documents, receipts, balances and statements
in native screens.

### Backend connector: finreg-kit

`app/services/finreg.py` wraps `softensor/finreg-kit`. `FINREG_BASE_URL` is the
Finreg origin (no `/api/v1`); the kit appends `/api/v1/integrations`. Requests
carry a scope bundle instead of a per-call token: `_READ_SCOPES`,
`_WRITE_SCOPES` and `_LAUNCH_SCOPES`, one token per bundle per actor, cached
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
| Delegated launch or Finreg workspace behaviour | Finreg, then update Cellen's launch contract |
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
7. Launch behaviour is manifest-driven: a new operational workspace appears as
   a tab without a Cellen change. Only the title/icon registry and contextual
   panes live in Cellen.
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

Run targeted Cellen integration tests after any host or launcher change:

```bash
cd /Users/jorgehel/projects/cellen
./.venv/bin/pytest tests/test_finreg_integration_unit.py
```

Warnings should be maintained as technical debt, but compiler errors, test
failures, stale dependency pins, and skipped required browser contracts block a
release.

## 9. Cross-repository release

Finreg and Cellen now release independently.

- A Finreg change that alters the integration API is released in Finreg first,
  then `softensor/finreg-kit` is released with the matching operation and Cellen
  pins the new kit SHA.
- A change confined to Finreg's own UI requires no Cellen release: the delegated
  launch opens whatever Finreg is serving.
- A Cellen-only change (school domain, launcher, native screens) needs no
  Finreg release and no Finreg restart.

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
deployments write the origin. Document names, never secret values.

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
sudo bash deploy/validate_cellen_finreg_release.sh --mode shadow
```

Use the actual controlled state when appropriate:

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
- delegated launch opens the correct Finreg workspace in the browser and a
  reused code is refused;
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
