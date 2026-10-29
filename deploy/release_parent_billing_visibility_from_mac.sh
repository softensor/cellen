#!/usr/bin/env bash
# Release the parent billing visibility + in-person payment fix from the Mac.
#
# Run from anywhere; the script locates the Cellen checkout from its own path:
#   bash ~/projects/cellen/deploy/release_parent_billing_visibility_from_mac.sh
#
# Pushes fix/parent-billing-visibility, opens the pull request if it does not
# exist yet, waits for CI, merges to master (which publishes the Flutter web
# bundle to GitHub Pages), then deploys the API on the production VPS and
# verifies both. Safe to re-run: an existing PR is reused.
#
# The reviewed fix commit is pinned. Later commits on the branch are allowed
# only when they touch nothing outside deploy/ (release-script bookkeeping),
# so an unintended code change can never ride along.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)

BRANCH=${CELLEN_RELEASE_BRANCH:-fix/parent-billing-visibility}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"fix(finance): parents see the billed month and the desk records in-person payments"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
WEB_URL=${CELLEN_WEB_URL:-https://softensor.github.io/cellen}
EXPECTED_SHA=${1:-06b63786dd2e860e6a52c9a60b2ab27627f85e7a}

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
    # Moving an ops script into deploy/ is bookkeeping: its old root path
    # disappears and the same basename exists under deploy/ at the new tip.
    unexpected=()
    while IFS= read -r path; do
      [[ -n $path ]] || continue
      base=${path##*/}
      if ! git cat-file -e "$FEATURE_SHA:$path" 2>/dev/null \
         && git cat-file -e "$FEATURE_SHA:deploy/$base" 2>/dev/null; then
        continue
      fi
      unexpected+=("$path")
    done <<< "$extra_paths"
    if [[ ${#unexpected[@]} -gt 0 ]]; then
      echo "Refusing to release: commits after the reviewed revision change files outside deploy/:" >&2
      printf '%s\n' "${unexpected[@]}" >&2
      exit 2
    fi
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
  PR_URL=$(gh pr create \
    --base master \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "The parent home read only local invoices, so a month billed through FinReg showed **Sem faturas pendentes**. \`/finreg/parent/documents\` also read only one-off draft context and the run snapshot (which carries no amounts), and the document PDF, receipts and statement were keyed on the outbox instruction instead of the fiscal document, so a second parent saw nothing.

- **One projection for the family** (\`app/services/parent_finance.py\`): Cellen's instruction supplies pupil, month and composed amount; FinReg's receivable feed supplies the authoritative balance, due date and status. If the feed fails the composed amounts and local payments are the fallback, never \"paid\"; an unconfirmed instruction or an unfinalized draft reads *Em processamento* and is not payable. Visibility covers the payer **or any guardian linked to the pupil**.
- **Parent surface**: home and Faturas merge FinReg documents; Extrato/Recibos parse both engines; the PDF now downloads the FinReg document id.
- **Payments at the desk** (\`POST /finance/payments/record\`): cash, transfer, card, cheque or Multicaixa collected in person settles an internal invoice or a FinReg document (issuing the legal receipt), idempotent on a key, resumable after a lost answer, and visible to the family immediately. Wired into Controlo de dívidas, the finance home, the Pagamentos hub and a new *Registar pagamento* screen.
- **Family scope on the rail**: principia-pay references accept a linked child as the family payer.

Verified: backend pytest (full), flutter test (full), dart format, flutter analyze.

🤖 Generated with [Claude Code](https://claude.com/claude-code)")
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

echo "==> Waiting for the merged-master workflows (backend and Flutter/Pages)"
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
wait_run flutter_build.yml

echo "==> Deploying merged revision $MERGED_SHA on $VPS_HOST"
ssh -tt "$VPS_HOST" \
  "cd '$VPS_DIR' && git switch master && git pull --ff-only origin master && sudo bash deploy/release_cellen_from_vps.sh '$MERGED_SHA'"

echo "==> Verifying public Cellen health"
curl --fail --silent --show-error "$PUBLIC_HEALTH_URL"
echo

echo "==> Waiting for the new web bundle on GitHub Pages"
bundle_ok=0
for attempt in $(seq 1 24); do
  if curl --fail --silent --show-error \
      "$WEB_URL/main.dart.js?sha=$MERGED_SHA" 2>/dev/null \
      | grep -q '/admin/finance/record-payment'; then
    bundle_ok=1
    break
  fi
  sleep 15
done
[[ $bundle_ok -eq 1 ]] || {
  echo "The Pages bundle does not contain the record-payment screen yet." >&2
  echo "Open $WEB_URL and hard-refresh; if the screen is missing, re-run the" >&2
  echo "flutter_build workflow for $MERGED_SHA." >&2
  exit 1
}

cat <<EOF

The parent billing visibility + in-person payment fix is deployed at $MERGED_SHA.

Walk the two paths:
  Parent (Rainha Njinga, October billed):
    1. Log in as a parent; the home shows "<child> · outubro 2026" with the
       balance and Em Atraso, not "Sem faturas pendentes".
    2. Faturas -> open the October document -> the PDF opens and the
       Multicaixa/rail payment form is available.
    3. A second guardian of the same child sees the same document.
  School desk:
    4. Financeiro -> Pagamentos -> Registar pagamento (or Controlo de dívidas
       -> open a debt -> Registar pagamento).
    5. Cash at the counter: submit the outstanding amount; the debt clears,
       the family's portal shows Pago and the receipt appears in the parent
       Recibos list.
EOF
