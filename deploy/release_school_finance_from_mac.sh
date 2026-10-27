#!/usr/bin/env bash
# Publish, review, merge and deploy the school-finance phases 2–5.
# Run from any directory inside the Cellen checkout on the Mac:
#   bash deploy/release_school_finance_from_mac.sh
#
# FinReg must already be running the integration routes this release calls
# (GET /integrations/receivables, the host debit-note route, the report
# read-backs). The script probes them and refuses to release until they answer
# as authenticated routes rather than 404.
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/school-finance-phases}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat: school debt control, late fees, dunning and rail payments"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
FINREG_API_URL=${CELLEN_FINREG_API_URL:-https://finreg.167.235.158.77.nip.io/api/v1}
PAGES_URL=${CELLEN_PAGES_URL:-https://softensor.github.io/cellen/}

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
git diff --name-only "$RELEASE_BASE" "$FEATURE_SHA" \
  | grep -Fx 'alembic/versions/0035_late_fees_dunning_pay.py' >/dev/null || {
    echo "The release branch does not contain migration 0035." >&2
    exit 2
  }

probe_finreg() {
  local path=$1 status
  status=$(curl -s -m 20 -o /dev/null -w '%{http_code}' \
    "$FINREG_API_URL/integrations/$path" 2>/dev/null || true)
  case $status in
    401|403) ;;
    404)
      echo "FinReg does not expose /integrations/$path yet." >&2
      echo "Deploy the FinReg feat/school-finance-phases release first." >&2
      exit 2
      ;;
    *)
      echo "FinReg route probe /integrations/$path returned HTTP '$status'; refusing to release." >&2
      exit 2
      ;;
  esac
}

echo "==> Verifying the FinReg school-finance routes are deployed"
probe_finreg "receivables?limit=1"
probe_finreg "reports/sales-by-product?date_from=2026-01-01&date_to=2026-01-31"

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Completes the school finance module so Cellen owns every finance screen while FinReg remains the only fiscal issuer:

- Debt control: FinReg receivables read model grouped by student, guardian and school service, with aging buckets, per-student and per-service reports, and a cross-engine dashboard (billed/collected/outstanding).
- Late fees: per-school configurable bands (anchor, day window, percentage, optional caps), incremental escalation, dry-run preview, idempotent per document and band; FinReg issues the corrective debit note in pilot/live, internal mode emits the same ND locally, shadow mode only previews.
- Dunning: per-school reminder ladder with a delivery audit; only the latest due rung fires, and in-app/email/WhatsApp/skipped-SMS outcomes are recorded.
- principia-pay: a parent can open a reference only against a finalized FinReg factura, the webhook is HMAC-verified and the poll authoritative, settlement posts a FinReg payment (and receipt where fiscal), and a 30-second reconciler repairs missed callbacks.
- Background automation: the daily Luanda-midnight chain assesses late fees and sends dunning; the dispatcher reconciles late-fee and rail references. Migration 0035 adds the policy columns and tracking tables.

FinReg must be deployed first (integration receivables/debit-note/report routes).

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
echo "==> Verifying the financial module is served"
PAGES_STATUS=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$PAGES_URL" || true)
echo "Pages $PAGES_URL -> HTTP $PAGES_STATUS (a cached service worker may still show the previous build)"
echo
echo "Cellen school-finance release completed at $MERGED_SHA."
