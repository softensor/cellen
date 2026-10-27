#!/usr/bin/env bash
# Publish, review, merge, and deploy fee automation (Phase 1).
# Run from any directory inside the Cellen checkout on the Mac:
#   bash deploy/release_fee_automation_from_mac.sh
#
# FinReg must already be running the Phase 0 billing-plan run route. The
# script probes the deployed FinReg API and refuses to release until that
# route answers as an authenticated route rather than 404.
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/fee-automation}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat: automate school fees from per-school policy"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
FINREG_API_URL=${CELLEN_FINREG_API_URL:-https://finreg.167.235.158.77.nip.io/api/v1}

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
git diff-tree --no-commit-id --name-only -r "$FEATURE_SHA" \
  | grep -Fx 'alembic/versions/0034_fee_automation.py' >/dev/null || {
    echo "The release commit does not contain migration 0034." >&2
    exit 2
  }

echo "==> Verifying the FinReg billing-plan run route is deployed"
probe_status=$(curl -s -m 20 -o /dev/null -w '%{http_code}' \
  -X POST "$FINREG_API_URL/integrations/billing-plans/__release_probe__/run" \
  2>/dev/null || true)
case $probe_status in
  401|403) ;;
  404)
    echo "FinReg does not expose the billing-plan run route yet." >&2
    echo "Deploy the FinReg feat/billing-plan-run-now release first." >&2
    exit 2
    ;;
  *)
    echo "FinReg route probe returned HTTP '$probe_status'; refusing to release." >&2
    exit 2
    ;;
esac

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Adds per-school fee automation: a fee policy per school year (enrollment fee, default tuition item, sibling discount percentage/minimum/scope, due days, billing day, proration, auto-generate), extracurricular modality and school transport registries with effective-dated enrollments, per-student finance profiles, and one monthly billing run with preview, blockers, per-item results and plan rebuild.

Cellen computes tuition, transport and modality lines from each student's registrations, applies the sibling discount and proration, and sends one billing_run instruction per plan to FinReg; internal-mode schools compose the same amounts through the existing control flow. Migration 0034 adds the seven new tables.

FinReg must be deployed first: the run dispatches to the billing-plan run route added by FinReg feat/billing-plan-run-now.

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

echo "==> Deploying merged revision $MERGED_SHA on $VPS_HOST"
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$MERGED_SHA'"

echo "==> Verifying public Cellen health"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo
echo "Cellen fee automation released successfully at $MERGED_SHA."
