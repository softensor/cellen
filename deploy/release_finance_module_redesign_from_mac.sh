#!/usr/bin/env bash
# Release the Cellen finance module redesign from the Mac checkout.
# (Archived: already released as a06f0bf / PR #48.)
#
#   bash deploy/release_finance_module_redesign_from_mac.sh
#
# Pushes feat/finance-module-redesign, opens the pull request if it does not
# exist yet, waits for CI, merges to master (which publishes the Flutter web
# bundle to GitHub Pages), then deploys the API on the production VPS and
# verifies both. Safe to re-run: an existing PR is reused.
set -Eeuo pipefail

BRANCH=${CELLEN_RELEASE_BRANCH:-feat/finance-module-redesign}
PR_TITLE=${CELLEN_RELEASE_TITLE:-"feat(finance): one coherent school finance workflow"}
VPS_HOST=${CELLEN_VPS_HOST:-jorgehel@167.235.158.77}
VPS_DIR=${CELLEN_VPS_DIR:-/var/www/cellen}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
WEB_URL=${CELLEN_WEB_URL:-https://softensor.github.io/cellen}
EXPECTED_SHA=${1:-efd2f64270d0b175bc4d3915a040bb465f59b385}

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

REPO_DIR=$(git rev-parse --show-toplevel)
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
  echo "Refusing to release an unexpected commit." >&2
  echo "Expected: $EXPECTED_SHA" >&2
  echo "On $BRANCH: $FEATURE_SHA" >&2
  echo "If a later commit on this branch is intended, pass its SHA as the argument." >&2
  exit 2
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
    --body "Redesigns the school finance area as one workflow-ordered module. The finance entry screen becomes six tabs (Painel, Dívidas e cobrança, Pagamentos, Configuração, Encarregados, Funcionários); every debt workflow — generate, control, late fees, payment arrangements, reminders, credits — lives in one hub; the home leads with the current month's generation state, totals, due date and failures; new screens cover late fees (dry-run preview plus bulk issue) and per-guardian account statements (FinReg's statement with an internal-ledger fallback); and /billing/dashboard gains a \`month\` block so the home card needs no extra call. Drill-downs now push so Back keeps its place, and the unreferenced legacy finance screens are deleted.

Verified: backend pytest, full flutter test suite, dart format and flutter analyze.

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
      | grep -q 'Multas por Atraso'; then
    bundle_ok=1
    break
  fi
  sleep 15
done
[[ $bundle_ok -eq 1 ]] || {
  echo "The Pages bundle does not contain the new late-fees screen yet." >&2
  echo "Open $WEB_URL and hard-refresh; if the tab is missing, re-run the" >&2
  echo "flutter_build workflow for $MERGED_SHA." >&2
  exit 1
}

cat <<EOF

Cellen finance redesign is deployed at $MERGED_SHA.

Walk the director's path (Rainha Njinga, FinReg pilot/live):
  1. Financeiro -> tabs Painel | Dívidas e cobrança | Pagamentos | Configuração | Encarregados | Funcionários.
  2. Painel: the month card reads "Outubro 2026 · dívidas por gerar" with its
     due date and "Gerar dívidas do mês"; after generating it reads
     "dívidas geradas" with students, total and "Ver execução".
  3. Dívidas e cobrança: gerar, controlo, multas, acordos, lembretes, créditos.
  4. Multas por atraso: the preview lists what would be charged; "Gerar multas
     do mês" issues them.
  5. Pagamentos -> Extrato de contas: pick a guardian and "Ver Extrato".
  6. Back from any drill-down returns to the same tab.
EOF
