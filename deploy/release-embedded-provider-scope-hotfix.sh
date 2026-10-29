#!/usr/bin/env bash
# Publish the embedded-provider fix in Finreg, pin it in Cellen, wait for the
# exact merged CI releases, and transfer the matching Finreg Web artifact.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
VPS=${VPS:-jorgehel@167.235.158.77}
FINREG_REPO=softensor/finreg
CELLEN_REPO=softensor/cellen
FINREG_BRANCH=fix/embedded-provider-scope
CELLEN_BRANCH=fix/pin-embedded-provider-scope

wait_for_pr_checks() {
  local repo=$1 pr=$2 count
  echo "Waiting for $repo PR #$pr checks to appear..."
  for _ in {1..60}; do
    count=$(gh pr view "$pr" --repo "$repo" --json statusCheckRollup \
      --jq '.statusCheckRollup | length')
    [[ $count -gt 0 ]] && break
    sleep 5
  done
  [[ ${count:-0} -gt 0 ]] || { echo "No PR checks appeared for $repo #$pr" >&2; exit 1; }
  gh pr checks "$pr" --repo "$repo" --watch
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
  [[ -n $pr ]] || { echo "Unable to resolve PR for $repo/$branch" >&2; exit 1; }
  printf '%s' "$pr"
}

wait_for_master_run() {
  local repo=$1 workflow=$2 sha=$3 run_id= conclusion= rerun_done=false
  echo "Waiting for $repo $workflow at $sha..."
  for _ in {1..90}; do
    run_id=$(gh run list --repo "$repo" --workflow "$workflow" --branch master \
      --event push --limit 20 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)
    if [[ -n $run_id ]] && \
       gh run view "$run_id" --repo "$repo" --json status >/dev/null 2>&1; then
      if gh run watch "$run_id" --repo "$repo" --exit-status; then
        return 0
      fi
      conclusion=$(gh run view "$run_id" --repo "$repo" --json conclusion \
        --jq '.conclusion' 2>/dev/null || true)
      if [[ -n $conclusion && $conclusion != success ]]; then
        echo "$workflow concluded with $conclusion for $sha" >&2
        echo "Failed job log:" >&2
        gh run view "$run_id" --repo "$repo" --log-failed || true
        gh run view "$run_id" --repo "$repo" --json jobs \
          --jq '.jobs[] | {name, conclusion, url}' || true
        if [[ $rerun_done == false ]]; then
          echo "Rerunning failed jobs once..."
          gh run rerun "$run_id" --repo "$repo" --failed
          rerun_done=true
          sleep 10
          continue
        fi
        exit 1
      fi
    fi
    echo "GitHub has not exposed the run details yet; retrying..."
    sleep 5
  done
  echo "No accessible $workflow run appeared for $sha" >&2
  exit 1
}

gh auth status >/dev/null

cd "$FINREG_DIR"
git switch master
git pull --ff-only origin master
git fetch ./finreg-embedded-provider-scope.bundle \
  "+$FINREG_BRANCH:refs/remotes/bundle/embedded-provider-scope"
FINREG_FIX_SHA=$(git rev-parse refs/remotes/bundle/embedded-provider-scope)
if git merge-base --is-ancestor "$FINREG_FIX_SHA" HEAD; then
  echo "Finreg fix is already merged; skipping duplicate publication."
else
  git branch -f "$FINREG_BRANCH" refs/remotes/bundle/embedded-provider-scope
  git switch "$FINREG_BRANCH"
  git push -u origin "$FINREG_BRANCH"
  FINREG_PR=$(open_pr "$FINREG_REPO" "$FINREG_BRANCH" \
    "fix: scope embedded Finreg providers" \
    "Propagate delegated embedded authentication, API, and router overrides through nested Riverpod scopes, with a host-shaped regression test.")
  echo "Finreg PR: $FINREG_PR"
  wait_for_pr_checks "$FINREG_REPO" "$FINREG_PR"
  gh pr merge "$FINREG_PR" --repo "$FINREG_REPO" --merge --delete-branch
  git switch master
  git pull --ff-only origin master
fi
FINREG_MASTER_SHA=$(git rev-parse HEAD)
wait_for_master_run "$FINREG_REPO" release-gates.yml "$FINREG_MASTER_SHA"

cd "$CELLEN_DIR"
git switch master
git pull --ff-only origin master
git fetch ./cellen-embedded-provider-scope.bundle \
  "+$CELLEN_BRANCH:refs/remotes/bundle/embedded-provider-scope"
CELLEN_FIX_SHA=$(git rev-parse refs/remotes/bundle/embedded-provider-scope)
if git merge-base --is-ancestor "$CELLEN_FIX_SHA" HEAD; then
  echo "Cellen pin is already merged; skipping duplicate publication."
else
  git branch -f "$CELLEN_BRANCH" refs/remotes/bundle/embedded-provider-scope
  git switch "$CELLEN_BRANCH"
  git push -u origin "$CELLEN_BRANCH"
  CELLEN_PR=$(open_pr "$CELLEN_REPO" "$CELLEN_BRANCH" \
    "chore: pin embedded provider scope fix" \
    "Pin the verified nested-provider Finreg fix and add a single identity-checked VPS release command.")
  echo "Cellen PR: $CELLEN_PR"
  wait_for_pr_checks "$CELLEN_REPO" "$CELLEN_PR"
  gh pr merge "$CELLEN_PR" --repo "$CELLEN_REPO" --merge --delete-branch
  git switch master
  git pull --ff-only origin master
fi
CELLEN_MASTER_SHA=$(git rev-parse HEAD)
wait_for_master_run "$CELLEN_REPO" backend_tests.yml "$CELLEN_MASTER_SHA"
wait_for_master_run "$CELLEN_REPO" flutter_build.yml "$CELLEN_MASTER_SHA"

cd "$FINREG_DIR"
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
rsync -az --partial --timeout=120 \
  -e "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=6" \
  "$WEB_DIR/" "$VPS:$WEB_DIR/"

echo
echo "Local publication and artifact transfer completed."
echo "Finreg master: $FINREG_MASTER_SHA"
echo "Cellen master: $CELLEN_MASTER_SHA"
echo "On the VPS, run only:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
