#!/usr/bin/env bash
# Publish, verify, merge and transfer the coordinated all-role access release.
# Run once from the local Cellen repository on the iMac. Safe to resume.
# Production activation remains a separate, explicit VPS command.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
VPS=${VPS:-jorgehel@167.235.158.77}

FINREG_REPO=softensor/finreg
CELLEN_REPO=softensor/cellen
FINREG_BRANCH=feat/role-aware-host-workspaces
CELLEN_BRANCH=feat/school-role-access-policy
FINREG_BUNDLE=$FINREG_DIR/finreg-school-role-access-policy.bundle
CELLEN_BUNDLE=$CELLEN_DIR/cellen-school-role-access-policy-final.bundle

require_command() {
  command -v "$1" >/dev/null || {
    echo "Required command is unavailable: $1" >&2
    exit 2
  }
}

require_file() {
  [[ -f $1 ]] || { echo "Missing required file: $1" >&2; exit 2; }
}

bundle_head() {
  local bundle=$1 branch=$2 sha
  sha=$(git bundle list-heads "$bundle" "refs/heads/$branch" |
    awk 'NR == 1 {print $1}')
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || {
    echo "Could not resolve $branch from $bundle" >&2
    exit 2
  }
  printf '%s' "$sha"
}

open_pr() {
  local repository=$1 branch=$2 title=$3 body=$4 pr
  pr=$(gh pr list \
    --repo "$repository" \
    --head "$branch" \
    --base master \
    --state open \
    --json number \
    --jq '.[0].number')
  if [[ -z $pr ]]; then
    gh pr create \
      --repo "$repository" \
      --base master \
      --head "$branch" \
      --title "$title" \
      --body "$body" >/dev/null
    pr=$(gh pr list \
      --repo "$repository" \
      --head "$branch" \
      --base master \
      --state open \
      --json number \
      --jq '.[0].number')
  fi
  [[ -n $pr ]] || {
    echo "Could not resolve PR for $repository/$branch" >&2
    exit 1
  }
  printf '%s' "$pr"
}

wait_for_pr_checks() {
  local repository=$1 pr=$2 output status
  echo "Waiting for $repository PR #$pr checks..."
  for _ in {1..90}; do
    set +e
    output=$(gh pr checks "$pr" --repo "$repository" --watch 2>&1)
    status=$?
    set -e
    printf '%s\n' "$output"
    [[ $status -eq 0 ]] && return 0
    if [[ $output == *"no checks reported"* ]]; then
      echo "Checks are not registered yet; retrying in 5 seconds..."
      sleep 5
      continue
    fi
    return "$status"
  done
  echo "No PR checks appeared for $repository PR #$pr" >&2
  return 1
}

wait_for_master_run() {
  local repository=$1 workflow=$2 sha=$3 run_id=''
  echo "Waiting for $repository/$workflow at $sha..."
  for _ in {1..120}; do
    run_id=$(gh run list \
      --repo "$repository" \
      --workflow "$workflow" \
      --branch master \
      --event push \
      --limit 30 \
      --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" |
      head -1)
    if [[ -n $run_id ]] && \
       gh run view "$run_id" --repo "$repository" >/dev/null 2>&1; then
      gh run watch "$run_id" --repo "$repository" --exit-status
      return 0
    fi
    sleep 5
  done
  echo "No accessible $workflow run appeared for $sha" >&2
  return 1
}

publish_bundle_if_needed() {
  local directory=$1 repository=$2 bundle=$3 branch=$4 feature_sha=$5 remote_ref=$6
  git -C "$directory" fetch origin master
  git -C "$directory" fetch "$bundle" \
    "+$branch:refs/remotes/bundle/$remote_ref"

  local bundle_sha remote_sha
  bundle_sha=$(git -C "$directory" rev-parse "refs/remotes/bundle/$remote_ref")
  [[ $bundle_sha == "$feature_sha" ]] || {
    echo "Bundle identity mismatch: expected=$feature_sha actual=$bundle_sha" >&2
    exit 1
  }

  if git -C "$directory" merge-base --is-ancestor "$feature_sha" origin/master; then
    echo "$repository already contains $feature_sha; publication skipped."
    return 0
  fi

  remote_sha=$(git -C "$directory" ls-remote --heads origin "$branch" |
    awk 'NR == 1 {print $1}')
  if [[ -n $remote_sha && $remote_sha != "$feature_sha" ]]; then
    echo "Remote branch $repository/$branch points to unexpected $remote_sha." >&2
    echo "Refusing to overwrite it automatically." >&2
    exit 1
  fi

  git -C "$directory" switch master
  git -C "$directory" pull --ff-only origin master
  git -C "$directory" branch -f "$branch" "refs/remotes/bundle/$remote_ref"
  git -C "$directory" switch "$branch"
  if [[ $remote_sha == "$feature_sha" ]]; then
    echo "$repository/$branch is already published at $feature_sha."
  else
    git -C "$directory" push -u origin "$branch"
  fi
}

for command in git gh rsync ssh; do
  require_command "$command"
done
gh auth status >/dev/null
require_file "$FINREG_BUNDLE"
require_file "$CELLEN_BUNDLE"

FINREG_FEATURE_SHA=$(bundle_head "$FINREG_BUNDLE" "$FINREG_BRANCH")
CELLEN_FEATURE_SHA=$(bundle_head "$CELLEN_BUNDLE" "$CELLEN_BRANCH")

publish_bundle_if_needed \
  "$FINREG_DIR" "$FINREG_REPO" "$FINREG_BUNDLE" "$FINREG_BRANCH" \
  "$FINREG_FEATURE_SHA" role-aware-host-workspaces

git -C "$FINREG_DIR" fetch origin master
if ! git -C "$FINREG_DIR" merge-base --is-ancestor \
  "$FINREG_FEATURE_SHA" origin/master; then
  FINREG_PR=$(open_pr \
    "$FINREG_REPO" "$FINREG_BRANCH" \
    "feat: expose role-aware host workspaces" \
    "Derive host workspace grants from authoritative Finreg role permissions and resolve multi-role delegated launches without privilege elevation.")
  echo "Finreg PR: $FINREG_PR"
  wait_for_pr_checks "$FINREG_REPO" "$FINREG_PR"
  gh pr merge "$FINREG_PR" \
    --repo "$FINREG_REPO" \
    --merge \
    --delete-branch
fi
git -C "$FINREG_DIR" switch master
git -C "$FINREG_DIR" pull --ff-only origin master
FINREG_MASTER_SHA=$(git -C "$FINREG_DIR" rev-parse HEAD)
git -C "$FINREG_DIR" merge-base --is-ancestor \
  "$FINREG_FEATURE_SHA" "$FINREG_MASTER_SHA"
wait_for_master_run \
  "$FINREG_REPO" release-gates.yml "$FINREG_MASTER_SHA"

PINNED_FINREG_SHA=$(git -C "$CELLEN_DIR" show \
  "$CELLEN_FEATURE_SHA:.github/finreg-packages-ref" | tr -d '[:space:]')
[[ $PINNED_FINREG_SHA == "$FINREG_FEATURE_SHA" ]] || {
  echo "Cellen bundle pins unexpected Finreg source: $PINNED_FINREG_SHA" >&2
  exit 1
}

publish_bundle_if_needed \
  "$CELLEN_DIR" "$CELLEN_REPO" "$CELLEN_BUNDLE" "$CELLEN_BRANCH" \
  "$CELLEN_FEATURE_SHA" school-role-access-policy

git -C "$CELLEN_DIR" fetch origin master
if ! git -C "$CELLEN_DIR" merge-base --is-ancestor \
  "$CELLEN_FEATURE_SHA" origin/master; then
  CELLEN_PR=$(open_pr \
    "$CELLEN_REPO" "$CELLEN_BRANCH" \
    "feat: manage school access for every role" \
    "Give school administrators one composition-aware editor for every Cellen role, Cellen area grants and authoritative Finreg workspace grants, with matching backend and navigation enforcement.")
  echo "Cellen PR: $CELLEN_PR"
  wait_for_pr_checks "$CELLEN_REPO" "$CELLEN_PR"
  gh pr merge "$CELLEN_PR" \
    --repo "$CELLEN_REPO" \
    --merge \
    --delete-branch
fi
git -C "$CELLEN_DIR" switch master
git -C "$CELLEN_DIR" pull --ff-only origin master
CELLEN_MASTER_SHA=$(git -C "$CELLEN_DIR" rev-parse HEAD)
git -C "$CELLEN_DIR" merge-base --is-ancestor \
  "$CELLEN_FEATURE_SHA" "$CELLEN_MASTER_SHA"
wait_for_master_run \
  "$CELLEN_REPO" backend_tests.yml "$CELLEN_MASTER_SHA"
wait_for_master_run \
  "$CELLEN_REPO" flutter_build.yml "$CELLEN_MASTER_SHA"

WEB_DIR=/tmp/finreg-web-$FINREG_MASTER_SHA
if [[ -f $WEB_DIR/finreg-release.json ]] && \
   grep -F "\"commit\":\"$FINREG_MASTER_SHA\"" \
     "$WEB_DIR/finreg-release.json" >/dev/null; then
  echo "Reusing verified Finreg Web artifact: $WEB_DIR"
else
  [[ ! -e $WEB_DIR ]] || {
    echo "Existing artifact directory has the wrong identity: $WEB_DIR" >&2
    exit 1
  }
  git -C "$FINREG_DIR" switch master
  bash "$FINREG_DIR/scripts/download-web-release.sh" "$WEB_DIR"
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
