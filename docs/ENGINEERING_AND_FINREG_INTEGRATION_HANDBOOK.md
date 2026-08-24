# Cellen Engineering and Finreg Integration Handbook

Status: canonical starting point for Cellen engineers and operators
Last reviewed: 2026-08-24

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
  + pinned current Finreg packages
  -> current Finreg page/repository
  -> Finreg API and database
```

Cellen must not maintain a reduced copy of a Finreg page or recreate its state
machine. Generic defects are fixed in Finreg and consumed through the pinned
Finreg revision. Cellen-specific presentation may frame, route, label, or add
school context, but it must preserve the authoritative Finreg workflow.

## 3. Non-negotiable integration rules

1. Finreg is a separate product, repository, backend, database, Web release,
   and fiscal authority.
2. Cellen never generates official numbering, tax totals, receipts, accounting
   entries, or SAF-T independently for new Finreg-managed documents.
3. Cellen embeds the current Finreg module implementation. Do not restore the
   retired local adapter/reduced finance UI pattern.
4. The exact Finreg dependency is the full commit SHA in
   `.github/finreg-packages-ref`.
5. The host passes delegated identity, tenant/company, language, permissions,
   capabilities, API URL, and exact initial route.
6. Browser routes must open the requested real Finreg route, not a generic
   landing page.
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
| `mobile/lib/features/admin/finance/finreg_sales_host_screen.dart` | Current embedded Finreg host and school contextual surfaces |
| `.github/finreg-packages-ref` | Immutable Finreg commit consumed by Cellen CI |
| `.github/workflows/backend_tests.yml` | Backend required checks |
| `.github/workflows/flutter_build.yml` | Android, iOS, Web, current implementation validation, and package checkout |
| `deploy` | VPS migration, service, promotion, validation, and release entry points |
| `tests/test_finreg_integration_unit.py` | Cross-boundary integration regression tests |
| `docs` | Architecture, rollout, authority, and operator references |

The Flutter build checks out `softensor/finreg` at the pinned SHA using the
read-only `FINREG_READ_TOKEN` Actions secret and exposes it as the expected
sibling package tree. Never point CI at a moving branch.

## 5. Request and UI composition

The host obtains Finreg capabilities from Cellen's authenticated integration
boundary, creates the delegated embedded session, and renders
`FinregEmbeddedModuleHost` with the requested route. Exact Cellen routes map to
exact Finreg routes. State, repositories, dialogs, mutations, and error handling
then come from the pinned Finreg implementation.

The backend integration uses `/api/v1/integrations`, versioned school context,
scoped OAuth credentials stored server-side, idempotency keys, mappings, an
outbox/event cursor, and capability negotiation. Client secrets must never be
compiled into Flutter or returned to the browser.

## 6. Choosing where to make a change

| Requirement | Change first |
|---|---|
| Generic invoice, POS, product, customer, payment, receipt, report, or UI-state defect | Finreg |
| Tax, numbering, issuance, correction, AGT, audit, accounting, or SAF-T | Finreg with compliance review |
| Shared embedded route or delegated-session behaviour | Finreg, then update Cellen pin/host |
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
4. Update embedded-host tests when route or provider lifecycle changes.
5. Release Finreg through a PR and obtain the immutable commit/artifact.
6. Update `.github/finreg-packages-ref` in Cellen.
7. Change only the Cellen route/context bridge required to expose it.
8. Validate Cellen Web/mobile builds and integration tests against that pin.

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

For Flutter changes, ensure the Finreg sibling checkout matches the pin:

```bash
cd /Users/jorgehel/projects/cellen
FINREG_SHA=$(cat .github/finreg-packages-ref)
git -C ../finreg fetch origin "$FINREG_SHA"
test "$(git -C ../finreg rev-parse "$FINREG_SHA")" = "$FINREG_SHA"

cd mobile
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build web --release
```

Run targeted Cellen integration tests after any host change:

```bash
cd /Users/jorgehel/projects/cellen
./.venv/bin/pytest tests/test_finreg_integration_unit.py
```

Warnings should be maintained as technical debt, but compiler errors, test
failures, stale dependency pins, and skipped required browser contracts block a
release.

## 9. Cross-repository release

The maintained entry point is in the Finreg repository:

```bash
cd /Users/jorgehel/projects/finreg
bash scripts/release_cellen_current_finreg_ui.sh
```

The script coordinates exact-SHA checks, Finreg PR/release gates, Cellen pin and
PR checks, immutable artifact download, identity verification, and transfer.
Remain at the terminal for SSH authentication. A line saying that release gates
passed does not mean production was deployed; GitHub publication, artifact
transfer, and VPS activation are separate stages.

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
| Acceptance evidence | `/home/jorgehel/backups/cellen-finreg-acceptance-*.org` |
| Other reserved port | `8002` (Condo Manager) |

Required Cellen configuration names include `FINREG_BASE_URL`,
`FINREG_WEB_URL`, `FINREG_CLIENT_ID`, `FINREG_CLIENT_SECRET_FILE`,
`FINREG_TIMEOUT_SECONDS`, `FINREG_VERIFY_TLS`, optional `FINREG_TLS_CA_FILE`,
and `FINREG_INTEGRATION_ENABLED`. Document names, never secret values.

## 11. VPS deployment

After both `master` commits pass CI and the matching Finreg artifact is present
under `/tmp/finreg-web-<Finreg SHA>` on the VPS:

```bash
ssh jorgehel@167.235.158.77
cd /var/www/cellen
git switch master
git pull --ff-only origin master
sudo bash deploy/release_cellen_finreg_from_vps.sh
```

That script is the normal combined deployment owner. It:

1. fast-forwards both repositories to `master`;
2. verifies the transferred artifact for the current Finreg revision;
3. runs `deploy_finreg_school_finance.sh` for migrations/configuration/services;
4. atomically activates the Finreg Web release when needed;
5. validates the Web release identity;
6. checks all four services and both APIs.

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
- real routes, actions, delegated identity, permissions, and state transitions
  work in the current embedded UI;
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
