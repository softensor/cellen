#!/usr/bin/env bash
# Publish, review, merge, and deploy the internal-payment payer and confirmation hotfix.
# Run from the Cellen checkout on the Mac:
#   bash deploy/release_internal_payment_guardian_from_mac.sh
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-fix/internal-payments-by-guardian}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"fix: index internal payments by payer and preserve confirmation page"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}

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
git show "$FEATURE_SHA:app/models/finance.py" \
  | grep -F "billing_guardian_id" >/dev/null || {
    echo "The release commit does not index internal payments by guardian." >&2
    exit 2
  }
git show "$FEATURE_SHA:mobile/lib/features/admin/finance/internal_payments_screen.dart" \
  | grep -F "Navigator.pop(dialogContext, true)" >/dev/null || {
    echo "The release commit does not contain the confirmation navigation fix." >&2
    exit 2
  }
git cat-file -e "$FEATURE_SHA:alembic/versions/0032_internal_payments_by_guardian.py" || {
    echo "The release commit does not contain the payer backfill migration." >&2
    exit 2
  }

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Indexes internal payment controls by the paying guardian while keeping guardian, pupil, and billing item optional for generic records. Backfills existing charges from guardian links, makes parent access use the payer directly, and fixes confirmation dialogs so only the dialog closes and the Financeiro page remains visible.")
fi
echo "==> Pull request: $PR_URL"

echo "==> Waiting for GitHub checks to appear"
checks_found=0
for ((attempt = 1; attempt <= 60; attempt++)); do
  checks_json=$(gh pr checks "$PR_URL" --json name 2>/dev/null || true)
  if [[ -n $checks_json && $checks_json != "[]" ]]; then
    checks_found=1
    break
  fi
  sleep 5
done
[[ $checks_found -eq 1 ]] || {
  echo "No GitHub checks appeared within five minutes." >&2
  exit 1
}

echo "==> Waiting for required checks"
gh pr checks "$PR_URL" --watch --fail-fast

echo "==> Merging reviewed pull request"
gh pr merge "$PR_URL" --merge --delete-branch

git fetch origin master
MERGED_SHA=$(git rev-parse origin/master)
git merge-base --is-ancestor "$FEATURE_SHA" "$MERGED_SHA" || {
  echo "Merged master does not contain the reviewed hotfix." >&2
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
echo "Cellen internal-payment payer and confirmation hotfix released successfully at $MERGED_SHA."
