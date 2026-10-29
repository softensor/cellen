#!/usr/bin/env bash
# Publish, review, merge and deploy the finance wiring + principia-pay probe
# release. Run from any directory inside the Cellen checkout on the Mac:
#   bash deploy/release_finance_wiring_from_mac.sh
#
# This release is additive: no migration. It collapses the FinReg card,
# removes the obsolete reference entry point, wires finance numbers to their
# detail screens, adds a live principia-pay probe, turns server faults into
# readable JSON errors, and settles all-skipped billing runs instead of
# leaving them "running" forever.
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/finance-wiring-rail-probe}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat(finance): wire finance navigation and make the rail status truthful"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
DB_NAME=${CELLEN_DB_NAME:-cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
API_BASE_URL=${CELLEN_API_URL:-https://167.235.158.77.nip.io/api/v1}
STUCK_RUN_ID=${CELLEN_STUCK_RUN_ID:-6bdf132a-80a7-4883-a3f1-2ee262638da5}

failed() {
  local status=$?
  echo "Release stopped at line $1 with status $status." >&2
  exit "$status"
}
trap 'failed $LINENO' ERR

for command in git gh ssh curl; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 2
  }
done

REPO_DIR=$(git rev-parse --show-toplevel)
cd "$REPO_DIR"

gh auth status >/dev/null

# The shared checkout keeps the local .gitignore edit; it is not part of the
# release and must not block it.
unexpected_changes=$(git diff --name-only HEAD -- . ':(exclude).gitignore')
if [[ -n $unexpected_changes ]]; then
  echo "Tracked changes outside .gitignore are not committed:" >&2
  echo "$unexpected_changes" >&2
  exit 2
fi

git switch "$BRANCH"
git fetch origin master
git merge-base --is-ancestor origin/master HEAD || {
  echo "$BRANCH is not based on the current origin/master." >&2
  exit 2
}

FEATURE_SHA=$(git rev-parse HEAD)
# Check the whole branch, not just HEAD: an automation commit on top must not
# let changes this release does not own through.
RELEASE_BASE=$(git merge-base origin/master HEAD)
changed=$(git diff --name-only "$RELEASE_BASE" "$FEATURE_SHA")

allowed_paths=$(cat <<'EOF'
app/routers/billing.py
app/routers/finance.py
app/services/billing_run.py
app/services/debt_control.py
app/services/principia_pay.py
deploy/release_finance_wiring_from_mac.sh
mobile/lib/core/api/api_client.dart
mobile/lib/core/api/api_exception.dart
mobile/lib/core/router/router.dart
mobile/lib/features/admin/finance/billing_run_screen.dart
mobile/lib/features/admin/finance/debt_control_screen.dart
mobile/lib/features/admin/finance/finance_dashboard_screen.dart
mobile/lib/features/admin/finance/finance_home_screen.dart
mobile/lib/features/admin/finance/finreg_sales_host_screen.dart
mobile/lib/features/admin/finance/principia_pay_screen.dart
mobile/lib/features/admin/finance/service_report_screen.dart
mobile/lib/features/parent/finance/parent_invoices_screen.dart
mobile/test/custom_roles_test.dart
mobile/test/fee_automation_screens_test.dart
mobile/test/finance_operations_screens_test.dart
mobile/test/finreg_finance_host_launcher_test.dart
mobile/test/parent_finance_payment_test.dart
mobile/test/platform_payments_screen_test.dart
tests/test_billing_run_api.py
tests/test_finance_phases.py
EOF
)
unexpected=$(grep -Fxv -f <(printf '%s\n' "$allowed_paths") <<<"$changed" || true)
if [[ -n $unexpected ]]; then
  echo "The release branch carries changes this release does not own:" >&2
  echo "$unexpected" >&2
  echo "An automation commit may have swept the shared tree; remove them and retry." >&2
  exit 2
fi

require_path() {
  local path=$1
  grep -Fx "$path" <<<"$changed" >/dev/null || {
    echo "The release branch does not contain $path." >&2
    exit 2
  }
}

require_path 'app/services/principia_pay.py'
require_path 'app/services/billing_run.py'
require_path 'mobile/lib/features/admin/finance/principia_pay_screen.dart'
require_path 'mobile/lib/features/admin/finance/finance_home_screen.dart'
require_path 'mobile/lib/features/admin/finance/debt_control_screen.dart'

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Makes the finance module navigable and the principia-pay card truthful:

- The FinReg entry card starts collapsed, with the live status in its header; the plan and \"Abrir no FinReg\" appear only when expanded.
- The obsolete \"Referências de pagamento\" entry point and the legacy \"Ref. Multicaixa\" chip are removed; principia-pay owns the flow.
- Finance numbers are links: KPIs, aging buckets, service rows, service reports, run results and student names open the matching filtered debt list, child profile or payment proofs.
- New live probe GET /billing/principia-pay/check and a \"Testar ligação\" action; a refused key or unreachable rail revokes the green tick and shows the rail's answer instead of a stored status.
- Reference creation converts unexpected failures into logged 4xx/5xx JSON errors, so a server fault no longer reaches the browser as a CORS-less network failure.
- A billing run whose students are all skipped now settles to completed with its skipped count instead of staying \"running\" forever; a still-composing run is not settled early.

Verified locally: backend billing/finance suites (77 passed, 2 skipped), Flutter suite 33/33, analyzer free of errors. No migration.

🤖 Generated with [Claude Code](https://claude.com/claude-code)")
fi
echo "==> Pull request: $PR_URL"

echo "==> Waiting for required checks to register"
checks_found=0
for attempt in $(seq 1 60); do
  checks_json=$(gh pr checks "$PR_URL" --json name 2>/dev/null || true)
  if [[ -n $checks_json && $checks_json != "[]" ]]; then
    checks_found=1
    break
  fi
  sleep 5
done
if [[ $checks_found -ne 1 ]]; then
  echo "No GitHub checks appeared within five minutes." >&2
  echo "Latest workflow runs for $BRANCH:" >&2
  gh run list --repo softensor/cellen --branch "$BRANCH" --limit 5 >&2 || true
  echo "If there are no runs, check Actions billing/enablement for softensor/cellen." >&2
  exit 1
fi

echo "==> Waiting for required checks"
gh pr checks "$PR_URL" --watch --fail-fast

echo "==> Merging reviewed pull request"
gh pr merge "$PR_URL" --merge --delete-branch

git fetch origin master
MERGED_SHA=$(git rev-parse origin/master)
git merge-base --is-ancestor "$FEATURE_SHA" "$MERGED_SHA" || {
  echo "Merged master does not contain the reviewed feature commit." >&2
  exit 2
}
git switch master
git merge --ff-only origin/master

echo "==> Waiting for the merged-master workflows (backend and Flutter/Pages)"
wait_run() {
  local workflow=$1 run_id=
  for _ in $(seq 1 180); do
    run_id=$(gh run list --workflow "$workflow" --branch master --event push \
      --limit 50 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$MERGED_SHA\") | .databaseId" | head -1)
    [[ -n $run_id ]] && break
    sleep 5
  done
  [[ -n $run_id ]] || {
    echo "No $workflow run appeared for $MERGED_SHA." >&2
    exit 1
  }
  gh run watch "$run_id" --exit-status
}
wait_run backend_tests.yml
wait_run flutter_build.yml

echo "==> Deploying merged revision $MERGED_SHA on $VPS_HOST"
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$MERGED_SHA'"

echo "==> Verifying public Cellen health"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo

echo "==> Verifying the live rail-probe route is served"
route_status=$(curl -s -m 20 -o /dev/null -w '%{http_code}' \
  "$API_BASE_URL/billing/principia-pay/check" 2>/dev/null || true)
case $route_status in
  401|403)
    echo "Live probe route answers HTTP $route_status (authenticated)."
    ;;
  404)
    echo "The deployed Cellen does not expose /billing/principia-pay/check." >&2
    exit 2
    ;;
  *)
    echo "Live probe route returned HTTP '$route_status'; refusing to accept the release." >&2
    exit 2
    ;;
esac

echo "==> Waiting for the stuck all-skipped billing run to settle"
run_state=
for _ in $(seq 1 24); do
  run_state=$(ssh "$VPS_HOST" \
    "sudo -u postgres psql -d '$DB_NAME' -Atc \"select status || '|' || coalesce(stats->>'skipped','') || '|' || coalesce(stats->>'generated','') from billing_runs where id = '$STUCK_RUN_ID'\"" \
    2>/dev/null || true)
  [[ -n $run_state && $run_state != running\|* ]] && break
  sleep 5
done
case $run_state in
  completed\|*)
    echo "All-skipped run settled: $run_state (status|skipped|generated)."
    ;;
  "")
    echo "ATTENTION: billing run $STUCK_RUN_ID was not found; settle check skipped."
    ;;
  running\|*)
    echo "The all-skipped run is still running two minutes after the deploy." >&2
    exit 2
    ;;
  *)
    echo "The all-skipped run is in an unexpected state: '$run_state'." >&2
    exit 2
    ;;
esac

callback_state=$(ssh "$VPS_HOST" \
  "sudo grep -q '^PRINCIPIA_PAY_CALLBACK_URL=' '$VPS_DIR/.env' && echo present || echo missing")
if [[ $callback_state != present ]]; then
  echo
  echo "ATTENTION: $VPS_DIR/.env has no PRINCIPIA_PAY_CALLBACK_URL."
  echo "Payments still reconcile by polling, but callbacks need it. Add it with:"
  echo "  ssh -tt $VPS_HOST \"echo 'PRINCIPIA_PAY_CALLBACK_URL=https://167.235.158.77.nip.io/api/v1/billing/principia-pay/callback' | sudo tee -a $VPS_DIR/.env && sudo systemctl restart cellen-api\""
  echo
fi

cat <<EOF

Cellen finance wiring is deployed at $MERGED_SHA.

Check the rail from the product (this is the diagnosis the card owed you):
  1. Open Cellen -> Financeiro -> Pagamentos por Referência.
  2. Press "Testar ligação".
     - "Ligação confirmada · N ms": the rail accepts the school's key.
     - "Sem ligação à principia-pay" with "Falha: ...": the shown message is
       the rail's actual answer; the server log has the full trace.
  3. Then open Controlo de Dívidas -> a student -> "Gerar referência".

The October run is now terminal: $run_state (status|skipped|generated).
Configure the tuition policy and generate the month again once the preview
amounts are confirmed.
EOF
