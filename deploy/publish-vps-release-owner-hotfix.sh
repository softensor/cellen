#!/usr/bin/env bash
# Publish the VPS repository-owner correction and wait for its PR checks.
set -Eeuo pipefail

REPO_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
REPO=softensor/cellen
BRANCH=fix/vps-release-repository-owner

cd "$REPO_DIR"
gh auth status >/dev/null
git switch master
git pull --ff-only origin master

git fetch ./cellen-vps-release-owner-hotfix.bundle \
  "+$BRANCH:refs/remotes/bundle/vps-release-owner-hotfix"
FIX_SHA=$(git rev-parse refs/remotes/bundle/vps-release-owner-hotfix)

if git merge-base --is-ancestor "$FIX_SHA" HEAD; then
  echo "VPS repository-owner correction is already merged."
else
  git branch -f "$BRANCH" refs/remotes/bundle/vps-release-owner-hotfix
  git switch "$BRANCH"
  git push -u origin "$BRANCH"

  PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
    --json number --jq '.[0].number')
  if [[ -z $PR ]]; then
    gh pr create --repo "$REPO" --base master --head "$BRANCH" \
      --title "fix: pull VPS releases as repository owner" \
      --body "Run Git pulls as jorgehel while retaining root privileges for migrations, services, validation, and web activation." >/dev/null
    PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
      --json number --jq '.[0].number')
  fi
  [[ -n $PR ]] || { echo "Unable to resolve the hotfix PR." >&2; exit 1; }
  echo "Cellen PR: $PR"

  for _ in {1..60}; do
    COUNT=$(gh pr view "$PR" --repo "$REPO" --json statusCheckRollup \
      --jq '.statusCheckRollup | length')
    [[ $COUNT -gt 0 ]] && break
    sleep 5
  done
  [[ ${COUNT:-0} -gt 0 ]] || { echo "No PR checks appeared." >&2; exit 1; }
  gh pr checks "$PR" --repo "$REPO" --watch
  gh pr merge "$PR" --repo "$REPO" --merge --delete-branch

  git switch master
  git pull --ff-only origin master
fi

echo
echo "Hotfix is merged. On the VPS, run only:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
