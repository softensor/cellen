#!/usr/bin/env bash
# Release the billing payload + outbox hardening, then repair the FinReg
# instructions stranded in production so parents can pay October.
#
# Run from anywhere; the script locates the Cellen checkout from its own path:
#   bash ~/projects/cellen/deploy/release_billing_dispatch_repair_from_mac.sh
#
# Pushes the reviewed fix, opens/reuses the pull request, waits for CI, merges
# to master, deploys the API on the production VPS, then rebuilds the missing
# `products` in the 44 stranded instructions and waits for the dispatcher to
# confirm the October documents. Safe to re-run: the repair is idempotent and
# an existing PR is reused.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)

BRANCH=${CELLEN_RELEASE_BRANCH:-fix/billing-dispatch-products}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"fix(finance): ship billing products to FinReg and never wedge the outbox"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
EXPECTED_SHA=${1:-b04b3d7c3e34fc054dce318b4ea09ce7f738f25f}

failed() {
  local status=$?
  echo "Release stopped at line $1 with status $status." >&2
  exit "$status"
}
trap 'failed $LINENO' ERR

for command in git gh curl; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 2
  }
done

cd "$REPO_DIR"

gh auth status >/dev/null

unexpected_changes=$(git diff --name-only HEAD -- . ':(exclude).gitignore')
if [[ -n $unexpected_changes ]]; then
  echo "Tracked changes outside .gitignore are not committed:" >&2
  echo "$unexpected_changes" >&2
  exit 2
fi

git switch "$BRANCH"
FEATURE_SHA=$(git rev-parse HEAD)
if [[ $FEATURE_SHA != "$EXPECTED_SHA" ]]; then
  git merge-base --is-ancestor "$EXPECTED_SHA" "$FEATURE_SHA" || {
    echo "Refusing to release: $BRANCH does not contain the reviewed commit." >&2
    echo "Reviewed: $EXPECTED_SHA" >&2
    echo "On $BRANCH: $FEATURE_SHA" >&2
    exit 2
  }
  extra_paths=$(git diff --name-only "$EXPECTED_SHA".."$FEATURE_SHA" -- . ':(exclude)deploy/')
  if [[ -n $extra_paths ]]; then
    echo "Refusing to release: commits after the reviewed revision change files outside deploy/:" >&2
    echo "$extra_paths" >&2
    exit 2
  fi
fi

git fetch origin master
git merge-base --is-ancestor origin/master HEAD || {
  echo "$BRANCH is not based on the current origin/master." >&2
  exit 2
}

echo "==> Pushing $BRANCH at $FEATURE_SHA"
git push -u origin "$BRANCH"

PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
if [[ -z $PR_URL ]]; then
  # macOS ships bash 3.2, which mis-parses a quoted heredoc inside $(...) as
  # soon as its body contains an apostrophe ("school's"), swallowing the rest
  # of the file. Keep the body in a temp file and pass --body-file instead.
  PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/cellen-pr-body.XXXXXX")
  cat > "$PR_BODY_FILE" <<'BODY'
Monthly runs and plan rebuilds built the FinReg payload without the `products` list, although every plan line references its fiscal product by external id. The HTTP dispatcher resolved those ids from the payload, raised `KeyError` before creating any document, and the instruction stayed in `processing` — a state the outbox only selects as `pending`, so it was never retried. All 44 Rainha Njinga instructions were stranded there, which is why parents saw nothing to pay.

- **Payload** (`app/services/billing_run.py`): include `products` in both the monthly run and the plan-rebuild payloads; a plan line whose product is missing now raises a clear, non-retryable `product_not_declared` instead of a bare `KeyError`.
- **Outbox** (`app/services/finreg_dispatch.py`): an unexpected exception returns the instruction to `pending` with backoff and is logged; one bad instruction no longer stops the rest of the batch. Every FinReg call is idempotent, so a retry cannot duplicate a document.
- **Auto-generation**: import `SchoolFeePolicy`; its missing import made the opt-in daily sweep raise `NameError` silently.
- **Production repair** (`deploy/repair_stuck_finreg_instructions.py`): rebuilds `products` from the school's billing items and requeues the already-stranded instructions. The release runs it after deploying.

Verified: pytest billing run, dispatcher and FinReg unit tests; ruff fatal checks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body-file "$PR_BODY_FILE")
  rm -f "$PR_BODY_FILE"
fi
echo "==> Pull request: $PR_URL"

echo "==> Waiting for required checks to register"
checks_found=0
for attempt in $(seq 1 60); do
  checks_json=$(gh pr checks "$PR_URL" --json name 2>/dev/null || true)
  if [[ -n $checks_json && $checks_json != "[]" ]]; then
    checks_found=1
    break
  fi
  sleep 5
done
if [[ $checks_found -ne 1 ]]; then
  echo "No GitHub checks appeared within five minutes." >&2
  gh run list --repo softensor/cellen --branch "$BRANCH" --limit 5 >&2 || true
  exit 1
fi

echo "==> Waiting for required checks"
gh pr checks "$PR_URL" --watch --fail-fast

echo "==> Merging reviewed pull request"
gh pr merge "$PR_URL" --merge --delete-branch

git fetch origin master
MERGED_SHA=$(git rev-parse origin/master)
git merge-base --is-ancestor "$FEATURE_SHA" "$MERGED_SHA" || {
  echo "Merged master does not contain the reviewed feature commit." >&2
  exit 2
}
git switch master
git merge --ff-only origin/master

echo "==> Waiting for the merged-master backend tests"
wait_run() {
  local workflow=$1 run_id=
  for _ in $(seq 1 180); do
    run_id=$(gh run list --workflow "$workflow" --branch master --event push \
      --limit 50 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$MERGED_SHA\") | .databaseId" | head -1)
    [[ -n $run_id ]] && break
    sleep 5
  done
  [[ -n $run_id ]] || {
    echo "No $workflow run appeared for $MERGED_SHA." >&2
    exit 1
  }
  gh run watch "$run_id" --exit-status
}
wait_run backend_tests.yml

echo "==> Deploying merged revision $MERGED_SHA on $VPS_HOST"
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$MERGED_SHA'"

echo "==> Verifying public Cellen health"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo

repair_instructions() {
  ssh -tt "$VPS_HOST" \
    "sudo runuser -u postgres -- env PYTHONPATH='$VPS_DIR' DATABASE_URL=postgresql+asyncpg:///cellen SECRET_KEY=cellen-repair PLATFORM_ADMIN_EMAIL=ops@example.invalid PLATFORM_ADMIN_PASSWORD=repair '$VPS_DIR/.venv/bin/python' '$VPS_DIR/deploy/repair_stuck_finreg_instructions.py' --dsn postgresql+asyncpg:///cellen --apply"
}

wait_for_dispatch() {
  local attempt processing counts
  for attempt in $(seq 1 40); do
    counts=$(ssh "$VPS_HOST" \
      "sudo -u postgres psql -d cellen -tAc \"select status || '=' || count(*) from finreg_billing_instructions group by status order by status\"" \
      | tr '\n' ' ')
    processing=$(ssh "$VPS_HOST" \
      "sudo -u postgres psql -d cellen -tAc \"select count(*) from finreg_billing_instructions where status = 'processing'\"")
    echo "  outbox: ${counts:-empty}"
    if [[ ${processing:-1} -eq 0 ]]; then
      return 0
    fi
    sleep 15
  done
  return 1
}

echo "==> Repairing the instructions stranded in processing"
repair_instructions

echo "==> Waiting for the dispatcher to confirm the documents"
if ! wait_for_dispatch; then
  echo "Instructions are still in processing after ten minutes; check:" >&2
  echo "  sudo journalctl -u cellen-api --since '20 minutes ago' | grep -i finreg" >&2
  exit 1
fi

unsettled=$(ssh "$VPS_HOST" \
  "sudo -u postgres psql -d cellen -tAc \"select count(*) from finreg_billing_instructions where status <> 'confirmed'\"")
if [[ ${unsettled:-1} -ne 0 ]]; then
  echo "==> $unsettled instruction(s) not confirmed; requeueing the retryable ones"
  repair_instructions
  if ! wait_for_dispatch; then
    echo "Instructions are still in processing after ten minutes; check:" >&2
    echo "  sudo journalctl -u cellen-api --since '20 minutes ago' | grep -i finreg" >&2
    exit 1
  fi
  unsettled=$(ssh "$VPS_HOST" \
    "sudo -u postgres psql -d cellen -tAc \"select count(*) from finreg_billing_instructions where status <> 'confirmed'\"")
fi

documents=$(ssh "$VPS_HOST" \
  "sudo -u postgres psql -d cellen -tAc \"select count(*) from finreg_billing_instructions where command_type = 'billing_run' and finreg_document_id is not null\"")
run_status=$(ssh "$VPS_HOST" \
  "sudo -u postgres psql -d cellen -tAc \"select status from billing_runs order by created_at desc limit 1\"")
echo "  October documents issued: $documents"
echo "  Latest billing run: $run_status"
if [[ ${unsettled:-1} -ne 0 ]]; then
  echo "Some instructions did not confirm:" >&2
  ssh "$VPS_HOST" \
    "sudo -u postgres psql -d cellen -P pager=off -c \"select command_type, status, error_code, left(error_detail, 200) from finreg_billing_instructions where status <> 'confirmed' order by updated_at desc\"" >&2
  exit 1
fi
[[ ${documents:-0} -gt 0 ]] || {
  echo "No FinReg document was issued; inspect the instruction errors:" >&2
  echo "  sudo -u postgres psql -d cellen -c \"select command_type, status, error_code, left(error_detail, 200) from finreg_billing_instructions order by updated_at desc limit 10;\"" >&2
  exit 1
}

cat <<EOF

The billing dispatch fix is deployed at $MERGED_SHA and the stranded
instructions were repaired; $documents October document(s) now carry a FinReg id.

Check the parent portal:
  1. Log in as a parent; the home should show the October debt, not
     "Sem faturas pendentes".
  2. Faturas -> open the October document -> the payment form is available.

If a school still has no documents, inspect the outbox:
  sudo -u postgres psql -d cellen -c "select command_type, status, error_code, left(error_detail, 200) from finreg_billing_instructions order by updated_at desc limit 20;"
EOF
