#!/usr/bin/env bash
# Release automatic payment references for the monthly bill from the Mac
# checkout.
#
#   bash deploy/release_payment_reference_autogen_from_mac.sh [expected-sha]
#
# A monthly run already issues the fiscal document, but no rail reference was
# opened, so the parent card read "Referência de pagamento não disponível"
# until an administrator pressed "Gerar referência". This release ships the
# auto-issuer, the parent document projection that carries the digits, and
# migration 0037.
#
# Pushes the reviewed commit, opens/reuses the pull request, waits for CI,
# merges to master (if it is not already merged), deploys the API on the
# production VPS, then waits for the dispatcher to mark the October
# instructions and prints their reference state.
#
# The Mac automation may already have committed and pushed the work to
# master; in that case the pull-request steps are skipped and only the
# deploy and verification run. Safe to re-run.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/payment-reference-autogen}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat(finance): issue payment references when the month is billed"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
EXPECTED_SHA=${1:-}

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
START_HEAD=$(git rev-parse HEAD)

gh auth status >/dev/null

unexpected_changes=$(git diff --name-only HEAD -- . ':(exclude).gitignore')
if [[ -n $unexpected_changes ]]; then
  echo "Tracked changes outside .gitignore are not committed:" >&2
  echo "$unexpected_changes" >&2
  exit 2
fi

# Fail closed on the one file this release cannot work without: a commit that
# lost the migration would deploy a model expecting columns the database does
# not have.
git cat-file -e HEAD:alembic/versions/0037_payment_reference_autogen.py || {
  echo "HEAD does not carry migration 0037; commit the release before running this." >&2
  exit 2
}

if [[ -n $EXPECTED_SHA ]]; then
  git merge-base --is-ancestor "$EXPECTED_SHA" HEAD || {
    echo "HEAD does not contain the reviewed commit $EXPECTED_SHA." >&2
    echo "HEAD: $(git rev-parse HEAD)" >&2
    exit 2
  }
fi

git fetch origin master
git merge-base --is-ancestor origin/master HEAD || {
  echo "HEAD is not based on the current origin/master; pull before releasing." >&2
  exit 2
}

if git merge-base --is-ancestor HEAD origin/master; then
  echo "==> HEAD is already merged into origin/master; skipping the pull request"
  git switch master
  git merge --ff-only origin/master
  MERGED_SHA=$(git rev-parse HEAD)
  git cat-file -e "$MERGED_SHA:alembic/versions/0037_payment_reference_autogen.py"
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
  # Allow CI a moment to register the push if the automation has only just
  # pushed; the discover loop above already tolerates it.
  wait_run backend_tests.yml
else
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git switch "$BRANCH"
  else
    git switch -c "$BRANCH"
  fi
  FEATURE_SHA=$(git rev-parse HEAD)
  git merge-base --is-ancestor "$START_HEAD" "$FEATURE_SHA" || {
    echo "Branch $BRANCH does not contain the checked-out release work." >&2
    echo "Checked out: $START_HEAD" >&2
    echo "On $BRANCH: $FEATURE_SHA" >&2
    exit 2
  }
  git cat-file -e "$FEATURE_SHA:alembic/versions/0037_payment_reference_autogen.py" || {
    echo "$BRANCH does not carry migration 0037." >&2
    exit 2
  }

  echo "==> Pushing $BRANCH at $FEATURE_SHA"
  git push -u origin "$BRANCH"

  PR_URL=$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)
  if [[ -z $PR_URL ]]; then
    # macOS ships bash 3.2, which mis-parses a quoted heredoc inside $(...) as
    # soon as its body contains an apostrophe; keep the body in a temp file.
    PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/cellen-pr-body.XXXXXX")
    cat > "$PR_BODY_FILE" <<'BODY'
The monthly run issues the fiscal document, but families had no rail reference to pay it: the parent card read "Referência de pagamento não disponível" until an administrator pressed "Gerar referência".

- **Auto-issuer** (`app/services/principia_pay.py`): a confirmed `billing_run` instruction is one finalized FinReg document. For every school whose PrincipiaPay connection is already active, the dispatcher tick reads the receivables feed once per school and opens one reference per open document. It never registers a school that has not opted in; it is idempotent (an existing active reference is returned, not duplicated); a settled or missing debt is skipped once; a rail outage retries with capped exponential backoff. Attempt state lives on the outbox instruction (migration 0037).
- **Dispatcher** (`app/services/scheduled_tasks.py`): the pass runs every tick, isolated from the rest of the outbox so one rail problem cannot block dispatch or settlement reconciliation.
- **Parent card** (`app/services/parent_finance.py`): `/finreg/parent/documents` now attaches the document's active reference as `payment_reference` plus `multicaixa_entity`/`multicaixa_ref`, which the already-deployed app renders as the Multicaixa box. No app release is needed.

Verified: full backend pytest suite, a staged alembic rehearsal of 0037 up/down, and new tests covering created / skipped / retried / opted-out paths, the parent card and the parent create endpoint.

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
fi

echo "==> Deploying merged revision $MERGED_SHA on $VPS_HOST"
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$MERGED_SHA'"

echo "==> Verifying public Cellen health"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo

echo "==> Waiting for the dispatcher to issue the October references"
# The dispatcher ticks every 30 seconds and takes 25 documents per school per
# tick, so ~90 seconds covers the 44 existing documents. The remote loop runs
# under one sudo session, so the VPS asks for its password once (twice in
# total, including the deploy above).
if ! ssh -tt "$VPS_HOST" 'sudo bash -s' <<'REMOTE'
for attempt in $(seq 1 8); do
  state=$(runuser -u postgres -- psql -d cellen -tAc "
    SELECT coalesce(payment_reference_status, 'pending') || '=' || count(*)
    FROM finreg_billing_instructions
    WHERE command_type = 'billing_run'
      AND status = 'confirmed'
      AND finreg_document_id IS NOT NULL
    GROUP BY 1 ORDER BY 1" | tr '\n' ' ')
  refs=$(runuser -u postgres -- psql -d cellen -tAc "
    SELECT count(*) FROM payment_references
    WHERE provider = 'principia_pay' AND status = 'active'")
  echo "attempt $attempt: instructions ${state:-none} | active references ${refs:-0}"
  [[ -n $state ]] || {
    echo "No confirmed monthly instruction with a FinReg document was found." >&2
    exit 1
  }
  case "$state" in
    *pending=*|*failed=*) sleep 15 ;;
    *) exit 0 ;;
  esac
done
exit 1
REMOTE
then
  echo "The auto-issuer has not finished; inspect the dispatcher log and" >&2
  echo "the instruction state with:" >&2
  echo "  sudo journalctl -u cellen-api --since '10 minutes ago' | grep -i 'auto payment references'" >&2
  echo "  sudo -u postgres psql -d cellen -c \"select payment_reference_status, payment_reference_error, count(*) from finreg_billing_instructions where command_type = 'billing_run' group by 1, 2;\"" >&2
  echo "If every row is still pending, the platform rail switch is off:" >&2
  echo "open Pagamentos -> Pagamentos por referência and check the connection." >&2
  exit 1
fi

cat <<EOF

Payment references are live at $MERGED_SHA.

Check the parent portal:
  1. Log in as a guardian. The October invoice card no longer says
     "Referência de pagamento não disponível": it shows the Multicaixa
     entity, reference number and amount under "Pagar via Multicaixa".
  2. An administrator still sees the same reference under
     Pagamentos -> Referências Multicaixa, and "Gerar referência" on a
     document returns the existing one instead of creating another.

New months get their reference automatically within 30 seconds of the
billing run being confirmed, for every school whose PrincipiaPay
connection is active.
EOF
