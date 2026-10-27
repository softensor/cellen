#!/usr/bin/env bash
# Publish, review, merge and deploy principia-pay owner activation.
# Run from any directory inside the Cellen checkout on the Mac:
#   bash deploy/release_platform_payments_from_mac.sh
#
# This release is additive: migration 0036 creates the platform_settings
# singleton, and the platform console gains the Pagamentos screen that saves
# the product token encrypted, live-verifies it against the rail, and lists
# every school with the rail's own onboarding state.
#
# After the deploy it issues the pilot school's current month through the
# product's own billing service and runs the corrected acceptance gate, so a
# single command ends with the release either proven or visibly failed.
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/platform-payment-activation}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat: activate principia-pay from the platform owner console"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
API_BASE_URL=${CELLEN_API_URL:-https://167.235.158.77.nip.io/api/v1}
SCHOOL_SLUG=${CELLEN_SCHOOL_SLUG:-rainha-njinga}
SKIP_ACCEPTANCE=${CELLEN_SKIP_ACCEPTANCE:-0}

failed() {
  local status=$?
  echo "Release stopped at line $1 with status $status." >&2
  exit "$status"
}
trap 'failed $LINENO' ERR

for command in git gh ssh scp curl; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 2
  }
done

REPO_DIR=$(git rev-parse --show-toplevel)
cd "$REPO_DIR"
GENERATE_SCRIPT=${CELLEN_GENERATE_SCRIPT:-$REPO_DIR/deploy/generate-current-month-billing.sh}

gh auth status >/dev/null

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
# let a branch without the migration through, nor block one that has it.
RELEASE_BASE=$(git merge-base origin/master HEAD)
changed=$(git diff --name-only "$RELEASE_BASE" "$FEATURE_SHA")

# The shared checkout can be swept by an automation commit ("auto: ...")
# that stages the whole working tree. Such a commit would push bundles,
# documents and local state into the public PR. The branch may carry the
# release's own paths (and the pre-existing .gitignore edit the clean check
# already tolerates) and nothing else.
allowed_paths=$(cat <<'EOF'
.gitignore
alembic/versions/0036_platform_payments.py
app/main.py
app/models/platform_settings.py
app/routers/platform_payments.py
app/schemas/platform_payments.py
app/services/principia_pay.py
app/services/principia_pay_client.py
deploy/generate-current-month-billing.sh
deploy/release_platform_payments_from_mac.sh
deploy/validate_cellen_finreg_release.sh
docs/SCHOOL_FINANCE_COVERAGE_BACKLOG.md
mobile/lib/core/router/router.dart
mobile/lib/features/platform/dashboard/platform_dashboard_screen.dart
mobile/lib/features/platform/payments/platform_payments_screen.dart
mobile/test/platform_payments_screen_test.dart
tests/conftest.py
tests/test_platform_payments.py
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

require_path 'alembic/versions/0036_platform_payments.py'
require_path 'app/routers/platform_payments.py'
require_path 'app/services/principia_pay.py'
require_path 'app/schemas/platform_payments.py'
require_path 'app/models/platform_settings.py'
require_path 'mobile/lib/features/platform/payments/platform_payments_screen.dart'
require_path 'deploy/validate_cellen_finreg_release.sh'
require_path 'deploy/generate-current-month-billing.sh'

if [[ $SKIP_ACCEPTANCE != 1 ]]; then
  [[ -f $GENERATE_SCRIPT ]] || {
    echo "Missing $GENERATE_SCRIPT." >&2
    echo "Set CELLEN_GENERATE_SCRIPT to the acceptance helper." >&2
    exit 2
  }
fi

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Adds owner-console activation for the principia-pay rail, mirroring the flow already proven in Mwenenzo:

- A singleton platform_settings row stores the product token encrypted (secret_box), shows only its non-secret prefix, and is authoritative once it exists: deactivation in the console beats a leftover environment token.
- Saving is save-then-probe: the token is committed before the rail is asked who it is. Only a verified connected token is armed; a refused token stays stored with attention and the rail's reason, never used.
- The platform Pagamentos screen lists every school with the rail's own per-client onboarding state and can register a school as its own rail client, so money never pools between schools.
- Product-tier rail reads verify the token and list clients; no API key or callback secret ever comes back.
- Migration 0036 creates the singleton table.

Also corrects the production acceptance gate to the shipped billing invariant: Cellen's run pauses every plan and owns its documents, so the gate requires a paused plan with at least one Cellen-issued document and the nightly FinReg sweep adding none.

After deploying, the release script issues the pilot school's current month through the product's own billing service and runs acceptance.

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

echo "==> Waiting for the merged-master workflows (backend and Pages)"
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

echo "==> Verifying the owner payment routes are served"
route_status=$(curl -s -m 20 -o /dev/null -w '%{http_code}' \
  "$API_BASE_URL/platform/payments/status" 2>/dev/null || true)
case $route_status in
  401|403)
    echo "Owner payment status route answers HTTP $route_status (authenticated)."
    ;;
  404)
    echo "The deployed Cellen does not expose /platform/payments/status." >&2
    exit 2
    ;;
  *)
    echo "Owner payment status route returned HTTP '$route_status'; refusing to accept the release." >&2
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

if [[ $SKIP_ACCEPTANCE == 1 ]]; then
  echo "==> Acceptance skipped (CELLEN_SKIP_ACCEPTANCE=1)."
else
  echo "==> Issuing the pilot school's current month through the product"
  scp -q "$GENERATE_SCRIPT" "$VPS_HOST:/tmp/cellen-generate-current-month.sh"
  scp -q "$REPO_DIR/deploy/validate_cellen_finreg_release.sh" \
    "$VPS_HOST:/tmp/cellen-validate-release.sh"
  ssh -tt "$VPS_HOST" \
    "sudo env SCHOOL_SLUG='$SCHOOL_SLUG' bash /tmp/cellen-generate-current-month.sh"

  echo "==> Running production acceptance"
  ssh -tt "$VPS_HOST" \
    "sudo bash /tmp/cellen-validate-release.sh --mode pilot --agt-channel offline"
fi

cat <<EOF

Cellen principia-pay activation is deployed at $MERGED_SHA.

One-time activation, in the product (the token is never printed or stored in
a script):
  1. Open the principia-pay dashboard -> Produtos -> Cellen and mint/copy a
     product token (ppt_...). The raw token is shown once.
  2. Open Cellen as the platform owner -> Plataforma -> Pagamentos, paste the
     token and press Activar. A failed verification keeps the paste but does
     not arm the rail; press Activar again after fixing it.
  3. Register each school from the same screen, then configure that client's
     provider credentials on the principia-pay dashboard.
EOF
