#!/usr/bin/env bash
# Release the "school issues the reference, the family pays it" API from the
# Mac checkout (PR #52, squash bb87e55).
#
#   bash deploy/release_reference_handoff_from_mac.sh
#
# Backend only. The new fields (debt rows' `payment_reference`, the
# dashboard month's `references`) are additions the current web app ignores,
# so the API can ship before the web bundle. No migration.
#
# GitHub Actions quota is exhausted, so nothing here may start a workflow:
# this script commits itself with [skip ci] (deploy/** is in the backend
# tests path filter) and never waits for CI. The merged tree was verified in
# the container: pytest 476 passed / 2 skipped, flutter test 50/50.
#
# Safe to re-run.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
SCRIPT_PATH=deploy/release_reference_handoff_from_mac.sh

FEATURE_SHA=bb87e55
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}

failed() {
  local status=$?
  echo "Release stopped at line $1 with status $status." >&2
  exit "$status"
}
trap 'failed $LINENO' ERR

cd "$REPO_DIR"

echo "==> Checking the checkout"
[[ $(git branch --show-current) == master ]] || {
  echo "Switch to master first (git switch master)." >&2
  exit 2
}
git fetch origin master
git merge --ff-only origin/master
git merge-base --is-ancestor "$FEATURE_SHA" HEAD || {
  echo "master does not contain $FEATURE_SHA (PR #52)." >&2
  exit 2
}

# Commit this script without starting a workflow. Only this file is staged;
# anything else in the tree stays as it is.
if [[ -n $(git status --porcelain -- "$SCRIPT_PATH") ]]; then
  echo "==> Committing $SCRIPT_PATH with [skip ci]"
  git add -- "$SCRIPT_PATH"
  git commit --quiet -m "chore(deploy): release script for the reference handoff [skip ci]" \
    -- "$SCRIPT_PATH"
  git push origin master
fi

RELEASE_SHA=$(git rev-parse HEAD)
[[ $RELEASE_SHA == $(git rev-parse origin/master) ]] || {
  echo "Local master is not origin/master; push or pull first." >&2
  exit 2
}
# Anything merged after PR #52 must be deploy scripts only: this release was
# verified for bb87e55, not for whatever else may have landed.
unexpected=$(git diff --name-only "$FEATURE_SHA" "$RELEASE_SHA" | grep -v '^deploy/' || true)
if [[ -n $unexpected ]]; then
  echo "master has changes after $FEATURE_SHA outside deploy/:" >&2
  echo "$unexpected" >&2
  exit 2
fi
echo "    releasing $RELEASE_SHA (contains $FEATURE_SHA)"

echo "==> Deploying on $VPS_HOST"
DEPLOY_STARTED=$(ssh "$VPS_HOST" date +%s)
# macOS ssh -tt can exit non-zero after a successful remote run; the checks
# below decide whether the release is live, not this exit status.
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$RELEASE_SHA'" \
  || echo "    (ssh returned non-zero; verifying the server state instead)"

echo "==> Verifying the live API"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo
ssh "$VPS_HOST" 'sudo bash -s' "$RELEASE_SHA" "$DEPLOY_STARTED" <<'REMOTE'
set -euo pipefail
expected=$1
started=$2
cd /var/www/cellen
live=$(runuser -u jorgehel -- git rev-parse HEAD)
[[ $live == "$expected" ]] || { echo "VPS checkout is $live, expected $expected" >&2; exit 1; }
grep -q '_month_references' app/services/debt_control.py
grep -q 'active_rail_references' app/routers/billing.py
# A checkout can move while the old process keeps serving: the service must
# have (re)started after this release began.
since=$(systemctl show -p ActiveEnterTimestamp --value cellen-api)
since_epoch=$(date -d "$since" +%s)
(( since_epoch >= started )) || { echo "cellen-api was not restarted (active since $since)" >&2; exit 1; }
echo "    VPS at $live, cellen-api active since $since"
echo "==> What the month card will show (read-only)"
month=$(TZ=Africa/Luanda date +%Y-%m)
runuser -u postgres -- psql -d cellen -P pager=off -c "
  SELECT s.name AS school,
         count(*) AS documents,
         count(*) FILTER (WHERE i.payment_reference_status = 'created') AS sent,
         count(*) FILTER (WHERE i.payment_reference_status IS NULL) AS waiting,
         count(*) FILTER (WHERE i.payment_reference_status = 'failed') AS failed,
         count(*) FILTER (WHERE r.status = 'paid') AS paid
    FROM finreg_billing_instructions i
    JOIN schools s ON s.id = i.school_id
    LEFT JOIN payment_references r ON r.id = i.payment_reference_id
   WHERE i.command_type = 'billing_run'
     AND i.status = 'confirmed'
     AND i.payload->>'billing_month' = '$month'
   GROUP BY s.name ORDER BY s.name"
REMOTE

cat <<EOF

API live at $RELEASE_SHA.

The new screens arrive with the web bundle: GitHub Pages only deploys
through Actions, which the quota blocks. Until then the current app keeps
working unchanged against this API.
EOF
