#!/usr/bin/env bash
# Publish, verify, merge and transfer the coordinated Finreg/Cellen governance
# release. Run this file once from the local Cellen repository on the iMac.
# It is resumable: merged branches and completed CI runs are reused.
set -Eeuo pipefail

CELLEN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
VPS=${VPS:-jorgehel@167.235.158.77}

FINREG_REPO=softensor/finreg
CELLEN_REPO=softensor/cellen
FINREG_BRANCH=feat/host-governance-boundary
CELLEN_BRANCH=feat/finreg-local-access-policy
FINREG_BUNDLE=$FINREG_DIR/finreg-host-governance-boundary.bundle
CELLEN_BUNDLE=$CELLEN_DIR/cellen-local-finreg-access-policy.bundle
FINREG_FEATURE_SHA=a7f8252000b26509299d8afd04d2dc6139137f93

require_file() {
  [[ -f $1 ]] || { echo "Missing required file: $1" >&2; exit 2; }
}

open_pr() {
  local repo=$1 branch=$2 title=$3 body=$4 pr
  pr=$(gh pr list --repo "$repo" --head "$branch" --base master --state open \
    --json number --jq '.[0].number')
  if [[ -z $pr ]]; then
    gh pr create --repo "$repo" --base master --head "$branch" \
      --title "$title" --body "$body" >/dev/null
    pr=$(gh pr list --repo "$repo" --head "$branch" --base master --state open \
      --json number --jq '.[0].number')
  fi
  [[ -n $pr ]] || { echo "Could not resolve PR for $repo/$branch" >&2; exit 1; }
  printf '%s' "$pr"
}

wait_for_pr_checks() {
  local repo=$1 pr=$2 count=0
  echo "Waiting for $repo PR #$pr checks..."
  for _ in {1..90}; do
    count=$(gh pr view "$pr" --repo "$repo" --json statusCheckRollup \
      --jq '.statusCheckRollup | length')
    [[ $count -gt 0 ]] && break
    sleep 5
  done
  [[ $count -gt 0 ]] || { echo "No PR checks appeared for $repo #$pr" >&2; exit 1; }
  gh pr checks "$pr" --repo "$repo" --watch
}

wait_for_master_run() {
  local repo=$1 workflow=$2 sha=$3 run_id=
  echo "Waiting for $repo $workflow at $sha..."
  for _ in {1..120}; do
    run_id=$(gh run list --repo "$repo" --workflow "$workflow" \
      --branch master --event push --limit 30 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)
    if [[ -n $run_id ]] && gh run view "$run_id" --repo "$repo" >/dev/null 2>&1; then
      gh run watch "$run_id" --repo "$repo" --exit-status
      return
    fi
    sleep 5
  done
  echo "No accessible $workflow run appeared for $sha" >&2
  exit 1
}

publish_bundle() {
  local directory=$1 bundle=$2 branch=$3 remote_ref=$4 expected_sha=$5
  cd "$directory"
  git switch master
  git pull --ff-only origin master
  git fetch "$bundle" "+$branch:refs/remotes/bundle/$remote_ref"
  local actual_sha
  actual_sha=$(git rev-parse "refs/remotes/bundle/$remote_ref")
  [[ $actual_sha == "$expected_sha" ]] || {
    echo "Bundle identity mismatch: expected=$expected_sha actual=$actual_sha" >&2
    exit 1
  }
  if git merge-base --is-ancestor "$expected_sha" HEAD; then
    echo "$branch is already contained in master."
    return
  fi
  git branch -f "$branch" "refs/remotes/bundle/$remote_ref"
  git switch "$branch"
  git push -u origin "$branch"
}

gh auth status >/dev/null
require_file "$FINREG_BUNDLE"
require_file "$CELLEN_BUNDLE"
CELLEN_FEATURE_SHA=$(git bundle list-heads "$CELLEN_BUNDLE" \
  "refs/heads/$CELLEN_BRANCH" |
  awk 'NR == 1 {print $1}')
[[ $CELLEN_FEATURE_SHA =~ ^[0-9a-f]{40}$ ]] || {
  echo "Could not resolve the Cellen bundle identity." >&2
  exit 1
}

publish_bundle "$FINREG_DIR" "$FINREG_BUNDLE" "$FINREG_BRANCH" \
  host-governance-boundary "$FINREG_FEATURE_SHA"

cd "$FINREG_DIR"
if ! git merge-base --is-ancestor "$FINREG_FEATURE_SHA" master; then
  FINREG_PR=$(open_pr "$FINREG_REPO" "$FINREG_BRANCH" \
    "feat: separate embedded modules from tenant control plane" \
    "Keep composition, entitlements and integration authority in Finreg; delegated hosts receive only operational ERP workspaces.")
  echo "Finreg PR: $FINREG_PR"
  wait_for_pr_checks "$FINREG_REPO" "$FINREG_PR"
  gh pr merge "$FINREG_PR" --repo "$FINREG_REPO" --merge --delete-branch
  git switch master
  git pull --ff-only origin master
fi
FINREG_MASTER_SHA=$(git rev-parse master)
wait_for_master_run "$FINREG_REPO" release-gates.yml "$FINREG_MASTER_SHA"

publish_bundle "$CELLEN_DIR" "$CELLEN_BUNDLE" "$CELLEN_BRANCH" \
  finreg-local-access-policy "$CELLEN_FEATURE_SHA"

cd "$CELLEN_DIR"
PINNED_FINREG_SHA=$(tr -d '[:space:]' < .github/finreg-packages-ref)
[[ $PINNED_FINREG_SHA == "$FINREG_FEATURE_SHA" ]] || {
  echo "Cellen pins unexpected Finreg source: $PINNED_FINREG_SHA" >&2
  exit 1
}
if ! git merge-base --is-ancestor "$CELLEN_FEATURE_SHA" master; then
  CELLEN_PR=$(open_pr "$CELLEN_REPO" "$CELLEN_BRANCH" \
    "feat: enforce local Finreg module access boundary" \
    "Allow school administrators to narrow finance-officer access inside the authoritative Finreg composition without inheriting tenant-owner controls.")
  echo "Cellen PR: $CELLEN_PR"
  wait_for_pr_checks "$CELLEN_REPO" "$CELLEN_PR"
  gh pr merge "$CELLEN_PR" --repo "$CELLEN_REPO" --merge --delete-branch
  git switch master
  git pull --ff-only origin master
fi
CELLEN_MASTER_SHA=$(git rev-parse master)
wait_for_master_run "$CELLEN_REPO" backend_tests.yml "$CELLEN_MASTER_SHA"
wait_for_master_run "$CELLEN_REPO" flutter_build.yml "$CELLEN_MASTER_SHA"

cd "$FINREG_DIR"
git switch master
git pull --ff-only origin master
FINREG_MASTER_SHA=$(git rev-parse HEAD)
WEB_DIR=/tmp/finreg-web-$FINREG_MASTER_SHA
if [[ -f $WEB_DIR/finreg-release.json ]] && \
   grep -F "$FINREG_MASTER_SHA" "$WEB_DIR/finreg-release.json" >/dev/null; then
  echo "Reusing verified Finreg Web artifact: $WEB_DIR"
else
  [[ ! -e $WEB_DIR ]] || {
    echo "Existing artifact directory has the wrong identity: $WEB_DIR" >&2
    exit 1
  }
  bash scripts/download-web-release.sh "$WEB_DIR"
fi

for attempt in 1 2 3; do
  if rsync -az --partial --timeout=120 \
    -e "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=6" \
    "$WEB_DIR/" "$VPS:$WEB_DIR/"; then
    break
  fi
  [[ $attempt -lt 3 ]] || exit 1
  echo "Artifact transfer failed; retrying in 10 seconds..."
  sleep 10
done

echo
echo "Local publication, CI verification and artifact transfer completed."
echo "Finreg master: $FINREG_MASTER_SHA"
echo "Cellen master: $CELLEN_MASTER_SHA"
echo
echo "On the VPS run only:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
