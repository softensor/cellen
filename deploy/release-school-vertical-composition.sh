#!/usr/bin/env bash
# Publish, merge, verify and transfer the coordinated Finreg/Cellen release.
# Run once from the local Cellen repository on the iMac.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=$(cd "$CELLEN_DIR/../finreg" && pwd)
FINREG_BRANCH=feat/vertical-composition-runtime
CELLEN_BRANCH=feat/school-vertical-composition
FINREG_BUNDLE="$FINREG_DIR/finreg-vertical-composition-runtime.bundle"
CELLEN_BUNDLE="$CELLEN_DIR/cellen-school-vertical-composition.bundle"
VPS=jorgehel@167.235.158.77

wait_for_checks() {
  local repository=$1 pr=$2 attempts=0
  until gh pr checks "$pr" --repo "$repository" --watch; do
    attempts=$((attempts + 1))
    [[ $attempts -lt 12 ]] || return 1
    echo "Checks are not registered yet; retrying in 10 seconds..."
    sleep 10
  done
}

open_pr() {
  local repository=$1 branch=$2 title=$3 body=$4 pr
  pr=$(gh pr list --repo "$repository" --head "$branch" --state open \
    --json number --jq '.[0].number')
  if [[ -z $pr ]]; then
    gh pr create --repo "$repository" --base master --head "$branch" \
      --title "$title" --body "$body" >/dev/null
    pr=$(gh pr list --repo "$repository" --head "$branch" --state open \
      --json number --jq '.[0].number')
  fi
  [[ -n $pr ]] || { echo "Could not resolve PR for $repository/$branch" >&2; exit 1; }
  printf '%s' "$pr"
}

cd "$FINREG_DIR"
git switch master
git pull --ff-only origin master
git fetch "$FINREG_BUNDLE" \
  "$FINREG_BRANCH:refs/remotes/bundle/vertical-composition-runtime"
git branch -f "$FINREG_BRANCH" refs/remotes/bundle/vertical-composition-runtime
git switch "$FINREG_BRANCH"
git push -u origin "$FINREG_BRANCH"
FINREG_PR=$(open_pr softensor/finreg "$FINREG_BRANCH" \
  "fix: isolate and localize embedded module runtime" \
  "Use an isolated delegated provider runtime for every embedded module, preserve the API base path, and synchronize host locale and errors.")
echo "Finreg PR: $FINREG_PR"
wait_for_checks softensor/finreg "$FINREG_PR"
gh pr merge "$FINREG_PR" --repo softensor/finreg --merge --delete-branch
git switch master
git pull --ff-only origin master
FINREG_SHA=$(git rev-parse HEAD)

cd "$CELLEN_DIR"
git switch master
git pull --ff-only origin master
git fetch "$CELLEN_BUNDLE" \
  "$CELLEN_BRANCH:refs/remotes/bundle/school-vertical-composition"
git branch -f "$CELLEN_BRANCH" refs/remotes/bundle/school-vertical-composition
git switch "$CELLEN_BRANCH"
git push -u origin "$CELLEN_BRANCH"
CELLEN_PR=$(open_pr softensor/cellen "$CELLEN_BRANCH" \
  "feat: compose Finreg workflows with school context" \
  "Render one manifest-driven workflow per capability, synchronize locale, combine school-owned people with authoritative Finreg processing, and expose fiscal/payroll readiness.")
echo "Cellen PR: $CELLEN_PR"
wait_for_checks softensor/cellen "$CELLEN_PR"
gh pr merge "$CELLEN_PR" --repo softensor/cellen --merge --delete-branch
git switch master
git pull --ff-only origin master

echo "Waiting for merged master release workflows..."
sleep 10
FINREG_RUN=$(gh run list --repo softensor/finreg --workflow release-gates.yml \
  --branch master --event push --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$FINREG_RUN" --repo softensor/finreg --exit-status
for workflow in backend_tests.yml flutter_build.yml; do
  CELLEN_RUN=$(gh run list --repo softensor/cellen --workflow "$workflow" \
    --branch master --event push --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$CELLEN_RUN" --repo softensor/cellen --exit-status
done

cd "$FINREG_DIR"
git switch master
git pull --ff-only origin master
FINREG_SHA=$(git rev-parse HEAD)
WEB_DIR="/tmp/finreg-web-$FINREG_SHA"
bash scripts/download-web-release.sh "$WEB_DIR"
rsync -az "$WEB_DIR/" "$VPS:$WEB_DIR/"

echo
echo "Local publication completed. On the VPS run exactly:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
