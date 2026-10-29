#!/usr/bin/env bash
# Pin Cellen's embedded Finreg/vertical packages to the currently reviewed
# Finreg master, publish through a PR, and wait for both Cellen CI workflows.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
REPO=softensor/cellen
BRANCH=chore/pin-current-finreg-verticals
PIN_FILE=.github/finreg-packages-ref

wait_for_master_run() {
  local workflow=$1 sha=$2 run_id
  for _ in {1..180}; do
    run_id=$(gh run list --repo "$REPO" --workflow "$workflow" \
      --branch master --event push --limit 50 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)
    if [[ -n $run_id ]]; then
      gh run watch "$run_id" --repo "$REPO" --exit-status
      return
    fi
    sleep 5
  done
  echo "No $workflow run appeared for Cellen $sha." >&2
  exit 1
}

for command in git gh; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 2
  }
done
gh auth status >/dev/null

git -C "$FINREG_DIR" fetch origin master
FINREG_SHA=$(git -C "$FINREG_DIR" rev-parse origin/master)
[[ $FINREG_SHA =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid Finreg master revision: $FINREG_SHA" >&2
  exit 1
}

cd "$CELLEN_DIR"
CURRENT_BRANCH=$(git branch --show-current)
if [[ $CURRENT_BRANCH == master ]]; then
  git fetch origin master
  [[ $(git rev-parse master) == $(git rev-parse origin/master) ]] || {
    echo "Cellen master is behind origin/master; update it first." >&2
    exit 1
  }
  git switch -c "$BRANCH"
elif [[ $CURRENT_BRANCH != "$BRANCH" ]]; then
  echo "Expected master or $BRANCH, found $CURRENT_BRANCH." >&2
  exit 1
fi

printf '%s\n' "$FINREG_SHA" >"$PIN_FILE"
git add "$PIN_FILE"
git diff --cached --check
if ! git diff --cached --quiet; then
  git commit -m "chore: pin current Finreg vertical corrections"
fi
git push -u origin "$BRANCH"

PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
  --json number --jq '.[0].number')
if [[ -z $PR ]]; then
  gh pr create --repo "$REPO" --base master --head "$BRANCH" \
    --title "chore: pin current Finreg vertical corrections" \
    --body "Build Cellen and its school vertical against the reviewed Finreg release containing the cross-module UI reliability, permission visibility, localized error handling, local issuance and POS transaction corrections." >/dev/null
  PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
    --json number --jq '.[0].number')
fi
[[ -n $PR ]] || { echo "Unable to resolve the Cellen pull request." >&2; exit 1; }
echo "Cellen PR: #$PR"

for _ in {1..120}; do
  set +e
  output=$(gh pr checks "$PR" --repo "$REPO" --watch 2>&1)
  status=$?
  set -e
  printf '%s\n' "$output"
  [[ $status -eq 0 ]] && break
  if [[ $output == *"no checks reported"* ]]; then
    sleep 5
    continue
  fi
  exit "$status"
done

gh pr merge "$PR" --repo "$REPO" --merge --delete-branch
git switch master
git pull --ff-only origin master
CELLEN_SHA=$(git rev-parse HEAD)
wait_for_master_run backend_tests.yml "$CELLEN_SHA"
wait_for_master_run flutter_build.yml "$CELLEN_SHA"

echo
echo "Cellen master: $CELLEN_SHA"
echo "Pinned Finreg: $FINREG_SHA"
echo "On the VPS run exactly:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
