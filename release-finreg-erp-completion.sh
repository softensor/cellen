#!/usr/bin/env bash
# Publish the coordinated Finreg ERP workflow-completion release, wait for the
# exact CI revisions, transfer the immutable Web artifact, and print the single
# production activation command. Safe to resume after a network/CI interruption.
set -Eeuo pipefail

CELLEN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
VPS=${VPS:-jorgehel@167.235.158.77}

FINREG_REPO=softensor/finreg
CELLEN_REPO=softensor/cellen
FINREG_BRANCH=feat/erp-workflow-completion
CELLEN_BRANCH=feat/finreg-workflow-completion

require_command() {
  command -v "$1" >/dev/null || {
    echo "Required command is unavailable: $1" >&2
    exit 2
  }
}

wait_for_pr_checks() {
  local repository=$1 pr=$2 output status
  for _ in {1..120}; do
    set +e
    output=$(gh pr checks "$pr" --repo "$repository" --watch 2>&1)
    status=$?
    set -e
    printf '%s\n' "$output"
    [[ $status -eq 0 ]] && return 0
    if [[ $output == *"no checks reported"* ]]; then
      sleep 5
      continue
    fi
    return "$status"
  done
  echo "No PR checks appeared for $repository PR #$pr." >&2
  return 1
}

wait_for_master_run() {
  local repository=$1 workflow=$2 sha=$3 run_id
  for _ in {1..180}; do
    run_id=$(gh run list \
      --repo "$repository" \
      --workflow "$workflow" \
      --branch master \
      --event push \
      --limit 50 \
      --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)
    if [[ -n $run_id ]]; then
      gh run watch "$run_id" --repo "$repository" --exit-status
      return
    fi
    sleep 5
  done
  echo "No $workflow run appeared for $repository at $sha." >&2
  return 1
}

open_pr() {
  local repository=$1 branch=$2 title=$3 body=$4 pr
  pr=$(gh pr list \
    --repo "$repository" --head "$branch" --base master --state open \
    --json number --jq '.[0].number')
  if [[ -z $pr ]]; then
    gh pr create \
      --repo "$repository" --base master --head "$branch" \
      --title "$title" --body "$body" >/dev/null
    pr=$(gh pr list \
      --repo "$repository" --head "$branch" --base master --state open \
      --json number --jq '.[0].number')
  fi
  [[ -n $pr ]] || { echo "Unable to resolve $repository PR." >&2; exit 1; }
  printf '%s' "$pr"
}

prepare_branch() {
  local directory=$1 branch=$2
  git -C "$directory" fetch origin master
  if [[ $(git -C "$directory" branch --show-current) == master ]]; then
    local local_master remote_master
    local_master=$(git -C "$directory" rev-parse master)
    remote_master=$(git -C "$directory" rev-parse origin/master)
    [[ $local_master == "$remote_master" ]] || {
      echo "$directory master is behind origin/master; refusing to mix releases." >&2
      exit 1
    }
    git -C "$directory" switch -c "$branch"
  else
    [[ $(git -C "$directory" branch --show-current) == "$branch" ]] || {
      echo "$directory is on an unexpected branch." >&2
      exit 1
    }
  fi
}

publish_pr() {
  local directory=$1 repository=$2 branch=$3 title=$4 body=$5 pr
  git -C "$directory" push -u origin "$branch"
  pr=$(open_pr "$repository" "$branch" "$title" "$body")
  echo "$repository PR: $pr"
  wait_for_pr_checks "$repository" "$pr"
  gh pr merge "$pr" --repo "$repository" --merge --delete-branch
  git -C "$directory" switch master
  git -C "$directory" pull --ff-only origin master
}

for command in git gh rsync ssh; do
  require_command "$command"
done
gh auth status >/dev/null

# Finreg: tracked edits belong to the reviewed ERP completion set. Add only the
# new implementation/test/migration paths, never local bundles or evidence.
prepare_branch "$FINREG_DIR" "$FINREG_BRANCH"
if ! git -C "$FINREG_DIR" diff --quiet || \
   ! git -C "$FINREG_DIR" diff --cached --quiet; then
  git -C "$FINREG_DIR" add -u
  git -C "$FINREG_DIR" add -- \
    apps/finreg_app/lib/core/providers/tax_options_provider.dart \
    apps/finreg_app/lib/core/widgets/workflow_state.dart \
    apps/finreg_app/test/action_callback_contract_test.dart \
    apps/finreg_app/test/dashboard_workflow_contract_test.dart \
    apps/finreg_app/test/pos_catalog_workflow_contract_test.dart \
    apps/finreg_app/test/workflow_state_test.dart \
    backend/alembic/versions/a2c7e4f9b1d6_add_payroll_components.py \
    backend/alembic/versions/b4e9f2a6c8d1_add_payroll_statutory_filings.py \
    backend/alembic/versions/c6a1e8f3b5d2_add_webhook_delivery_history.py \
    backend/alembic/versions/d7b2f9a4c6e1_add_commission_ledger.py \
    backend/alembic/versions/f1a6c3e8b2d4_add_effective_tax_options.py \
    backend/app/core/secret_box.py \
    backend/app/core/tax_policy.py \
    backend/app/core/workflow_registry.py \
    backend/app/services/approval_policy_service.py \
    backend/app/services/commission_service.py \
    backend/app/tasks/webhook_delivery.py \
    backend/app/workflow_manifests \
    backend/tests/test_commission_lifecycle.py \
    backend/tests/test_accounting_country_pack.py \
    backend/tests/test_company_subscription_profile.py \
    backend/tests/test_flutter_api_contract.py \
    backend/tests/test_operational_diagnostics_contract.py \
    backend/tests/test_shared_approval_policy.py \
    backend/tests/test_tax_policy.py \
    backend/tests/test_vertical_package_contract.py \
    backend/tests/test_webhook_delivery.py \
    backend/tests/test_workflow_registry.py \
    scripts/serve_web_e2e.py
  git -C "$FINREG_DIR" diff --cached --check
  git -C "$FINREG_DIR" commit -m "feat: complete operational ERP workflows"
fi
publish_pr \
  "$FINREG_DIR" "$FINREG_REPO" "$FINREG_BRANCH" \
  "feat: complete operational ERP workflows" \
  "Connect the core UI actions to authoritative APIs, add manifest-driven workflow state, effective Angola tax/payroll controls, approval and commission lifecycles, durable webhooks, diagnostics, and release regression coverage."
FINREG_SHA=$(git -C "$FINREG_DIR" rev-parse HEAD)
wait_for_master_run "$FINREG_REPO" release-gates.yml "$FINREG_SHA"

# Cellen consumes one immutable, already-verified Finreg revision.
prepare_branch "$CELLEN_DIR" "$CELLEN_BRANCH"
printf '%s\n' "$FINREG_SHA" >"$CELLEN_DIR/.github/finreg-packages-ref"
git -C "$CELLEN_DIR" add -u
git -C "$CELLEN_DIR" add -- \
  .github/finreg-packages-ref \
  alembic/versions/0027_billing_item_finreg_tax_option.py \
  alembic/versions/0028_employee_tax_id.py \
  alembic/versions/0029_align_required_workflow_columns.py \
  tests/test_flutter_api_contract.py \
  mobile/test/action_callback_contract_test.dart \
  release-finreg-erp-completion.sh
git -C "$CELLEN_DIR" diff --cached --check
if ! git -C "$CELLEN_DIR" diff --cached --quiet; then
  git -C "$CELLEN_DIR" commit -m "feat: complete school finance workflows"
fi
publish_pr \
  "$CELLEN_DIR" "$CELLEN_REPO" "$CELLEN_BRANCH" \
  "feat: complete Finreg-backed school workflows" \
  "Pin the verified Finreg release, align school billing and employee contracts, connect the operational finance UI, and ship one resumable release and production acceptance path."
CELLEN_SHA=$(git -C "$CELLEN_DIR" rev-parse HEAD)
wait_for_master_run "$CELLEN_REPO" backend_tests.yml "$CELLEN_SHA"
wait_for_master_run "$CELLEN_REPO" flutter_build.yml "$CELLEN_SHA"

WEB_DIR=/tmp/finreg-web-$FINREG_SHA
if [[ -f $WEB_DIR/finreg-release.json ]] && \
   grep -F "\"commit\":\"$FINREG_SHA\"" "$WEB_DIR/finreg-release.json" >/dev/null; then
  echo "Reusing verified artifact $WEB_DIR."
else
  [[ ! -e $WEB_DIR ]] || {
    echo "Artifact directory exists with the wrong identity: $WEB_DIR" >&2
    exit 1
  }
  bash "$FINREG_DIR/scripts/download-web-release.sh" "$WEB_DIR"
fi

for attempt in 1 2 3; do
  if rsync -az --partial --timeout=120 \
    -e "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=6" \
    "$WEB_DIR/" "$VPS:$WEB_DIR/"; then
    break
  fi
  [[ $attempt -lt 3 ]] || exit 1
  sleep 10
done

echo
echo "Finreg master: $FINREG_SHA"
echo "Cellen master: $CELLEN_SHA"
echo "Release and artifact transfer completed. On the VPS run exactly:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
