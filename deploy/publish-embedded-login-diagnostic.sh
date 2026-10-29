#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY=softensor/cellen
BRANCH=ops/embedded-login-diagnostic
BUNDLE=cellen-embedded-login-diagnostic.bundle

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

git switch master
git pull --ff-only origin master
git fetch "./$BUNDLE" \
  "$BRANCH:refs/remotes/bundle/embedded-login-diagnostic"
git branch -f "$BRANCH" refs/remotes/bundle/embedded-login-diagnostic
git switch "$BRANCH"
git diff --check
git push -u origin "$BRANCH"

PR_NUMBER=$(
  gh pr list \
    --repo "$REPOSITORY" \
    --head "$BRANCH" \
    --state open \
    --json number \
    --jq '.[0].number'
)

if [[ -z "$PR_NUMBER" ]]; then
  gh pr create \
    --repo "$REPOSITORY" \
    --base master \
    --head "$BRANCH" \
    --title "ops: add embedded Finreg login diagnostic" \
    --body "Add one VPS diagnostic command covering the Cellen host session and Finreg delegated authentication path."
  PR_NUMBER=$(
    gh pr list \
      --repo "$REPOSITORY" \
      --head "$BRANCH" \
      --state open \
      --json number \
      --jq '.[0].number'
  )
fi

if [[ -z "$PR_NUMBER" ]]; then
  printf 'Could not resolve the diagnostic pull request.\n' >&2
  exit 1
fi

printf 'Cellen PR: %s\n' "$PR_NUMBER"

set +e
CHECK_OUTPUT=$(gh pr checks "$PR_NUMBER" --repo "$REPOSITORY" --watch 2>&1)
CHECK_STATUS=$?
set -e
printf '%s\n' "$CHECK_OUTPUT"

if (( CHECK_STATUS != 0 )) &&
  ! grep -Fq 'no checks reported' <<<"$CHECK_OUTPUT"; then
  printf 'Pull-request checks did not pass.\n' >&2
  exit "$CHECK_STATUS"
fi

gh pr merge "$PR_NUMBER" --repo "$REPOSITORY" --merge --delete-branch

printf 'Waiting for the merged master reference...\n'
sleep 5

git switch master
git pull --ff-only origin master

printf 'Merged Cellen revision: '
git rev-parse HEAD

if ! git ls-tree -r HEAD --name-only |
  grep -Fxq 'deploy/diagnose_finreg_embedded_login.sh'; then
  printf 'Diagnostic script is missing from merged master.\n' >&2
  exit 1
fi

printf 'Diagnostic script is present in merged master.\n'
printf 'Local publication completed successfully.\n'
