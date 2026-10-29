#!/usr/bin/env bash
# Publish the bundled matrícula fix and verify its GitHub Pages deployment.
# Run locally with authenticated gh access: bash deploy/release-matricula-registration.sh
set -Eeuo pipefail

ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
REPO=softensor/cellen
BRANCH=fix/matricula-new-pupil-registration
BUNDLE=$ROOT/cellen-matricula-registration.bundle
for command in git gh mktemp; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 2; }
done
[[ -f $BUNDLE ]] || { echo "Missing bundle: $BUNDLE" >&2; exit 2; }
gh auth status >/dev/null
FIX_SHA=$(git bundle list-heads "$BUNDLE" "refs/heads/$BRANCH" | awk 'NR == 1 {print $1}')
[[ $FIX_SHA =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid bundle branch." >&2; exit 2; }

# A separate checkout preserves all local edits and untracked files.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cellen-matricula-release.XXXXXX")
echo "Release checkout: $WORK"
gh repo clone "$REPO" "$WORK/repo" -- --branch master --single-branch
cd "$WORK/repo"
git bundle verify "$BUNDLE"
git fetch "$BUNDLE" "refs/heads/$BRANCH:refs/heads/$BRANCH"

wait_for_run() {
  local event=$1 branch=$2 sha=$3 run_id= conclusion=
  for ((attempt=0; attempt<120; attempt++)); do
    run_id=$(gh run list --repo "$REPO" --workflow flutter_build.yml \
      --branch "$branch" --event "$event" --commit "$sha" --limit 20 \
      --json databaseId --jq '.[0].databaseId // empty')
    [[ -n $run_id ]] && break
    sleep 5
  done
  [[ -n $run_id ]] || { echo "No Flutter workflow appeared for $sha." >&2; exit 1; }
  gh run watch "$run_id" --repo "$REPO" --exit-status
  conclusion=$(gh run view "$run_id" --repo "$REPO" --json conclusion --jq .conclusion)
  [[ $conclusion == success ]] || { echo "Flutter workflow failed: $run_id" >&2; exit 1; }
  VERIFIED_RUN=$run_id
}

if git merge-base --is-ancestor "$FIX_SHA" origin/master; then
  echo "Fix already merged; verifying its release."
  MERGED_SHA=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master \
    --state merged --json mergeCommit --jq '.[0].mergeCommit.oid // empty')
  [[ -n $MERGED_SHA ]] || { echo "Cannot identify the merged release commit." >&2; exit 1; }
else
  git switch "$BRANCH"
  # Reject stale/conflicting releases before publication. No force pushes.
  git merge-base --is-ancestor origin/master HEAD || {
    echo "master advanced since this bundle was prepared. Rebase and validate a fresh bundle." >&2
    exit 1
  }
  git push -u origin "$BRANCH"
  PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master \
    --state open --json number --jq '.[0].number // empty')
  if [[ -z $PR ]]; then
    cat > "$WORK/pr-body.md" <<'BODY'
Allow a new pupil or child to be registered from Nova Matrícula. Saving the existing registration form returns to enrollment with the new record selected and the enrollment details preserved.

Validation: the Flutter pull-request workflow must pass analysis, tests, and builds before merging. The master workflow then builds and deploys Cellen Web to GitHub Pages.
BODY
    gh pr create --repo "$REPO" --base master --head "$BRANCH" \
      --title "fix: register new pupils during matrícula" --body-file "$WORK/pr-body.md"
    PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master \
      --state open --json number --jq '.[0].number // empty')
  fi
  [[ -n $PR ]] || { echo "Cannot identify release PR." >&2; exit 1; }
  wait_for_run pull_request "$BRANCH" "$FIX_SHA"
  gh pr checks "$PR" --repo "$REPO" --watch
  gh pr merge "$PR" --repo "$REPO" --merge --match-head-commit "$FIX_SHA"
  MERGED_SHA=$(gh pr view "$PR" --repo "$REPO" --json mergeCommit --jq '.mergeCommit.oid // empty')
  [[ -n $MERGED_SHA ]] || { echo "PR has not merged yet." >&2; exit 1; }
fi

wait_for_run push master "$MERGED_SHA"
DEPLOYMENT=$(gh run view "$VERIFIED_RUN" --repo "$REPO" --json jobs \
  --jq '.jobs[] | select(.name == "Deploy Web") | .conclusion')
[[ $DEPLOYMENT == success ]] || { echo "GitHub Pages deployment was not successful." >&2; exit 1; }
echo "Cellen matrícula fix deployed from $MERGED_SHA"
gh api "repos/$REPO/pages" --jq .html_url
