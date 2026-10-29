#!/usr/bin/env bash
# Publish the reviewed Finreg demo provisioner and invoke it on the VPS.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
REPO=softensor/finreg
BRANCH=feat/demo-vertical-tenants
VPS=${VPS:-jorgehel@167.235.158.77}

for command in git gh ssh; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 2; }
done
gh auth status >/dev/null

git -C "$FINREG_DIR" fetch origin master
if [[ $(git -C "$FINREG_DIR" branch --show-current) == master ]]; then
  git -C "$FINREG_DIR" pull --ff-only origin master
  git -C "$FINREG_DIR" switch -c "$BRANCH"
fi
[[ $(git -C "$FINREG_DIR" branch --show-current) == "$BRANCH" ]] || {
  echo "Finreg must be on master or $BRANCH." >&2
  exit 2
}

git -C "$FINREG_DIR" add -- \
  scripts/provision_demo_tenants.py \
  scripts/provision_demo_tenants_on_vps.sh \
  backend/tests/test_demo_tenant_provisioner.py
git -C "$FINREG_DIR" diff --cached --check
if ! git -C "$FINREG_DIR" diff --cached --quiet; then
  git -C "$FINREG_DIR" commit -m "feat: provision isolated vertical demo tenants"
fi
git -C "$FINREG_DIR" push -u origin "$BRANCH"

PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
  --json number --jq '.[0].number')
if [[ -z $PR ]]; then
  gh pr create --repo "$REPO" --base master --head "$BRANCH" \
    --title "feat: provision isolated vertical demo tenants" \
    --body "Add an idempotent API-driven demo provisioner for generic, school, retail, hotel, clinic and restaurant tenants, with module-specific sample records and explicit production confirmation." >/dev/null
  PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --base master --state open \
    --json number --jq '.[0].number')
fi
echo "Finreg PR: $PR"

for _ in {1..120}; do
  set +e
  output=$(gh pr checks "$PR" --repo "$REPO" --watch 2>&1)
  status=$?
  set -e
  printf '%s\n' "$output"
  [[ $status -eq 0 ]] && break
  [[ $output == *"no checks reported"* ]] || exit "$status"
  sleep 5
done
[[ ${status:-1} -eq 0 ]] || { echo "PR checks did not complete." >&2; exit 1; }

gh pr merge "$PR" --repo "$REPO" --merge --delete-branch
git -C "$FINREG_DIR" switch master
git -C "$FINREG_DIR" pull --ff-only origin master
SHA=$(git -C "$FINREG_DIR" rev-parse HEAD)

for _ in {1..180}; do
  RUN_ID=$(gh run list --repo "$REPO" --workflow release-gates.yml --branch master \
    --event push --limit 50 --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$SHA\") | .databaseId" | head -1)
  [[ -z $RUN_ID ]] || break
  sleep 5
done
[[ -n ${RUN_ID:-} ]] || { echo "No master release gate appeared for $SHA." >&2; exit 1; }
gh run watch "$RUN_ID" --repo "$REPO" --exit-status

ssh -t "$VPS" \
  "cd /var/www/finreg && git pull --ff-only origin master && sudo bash scripts/provision_demo_tenants_on_vps.sh"
