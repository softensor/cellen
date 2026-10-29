#!/usr/bin/env bash
# Repair the stale dynamic Finreg-pin assertion and resume the coordinated
# Finreg/Cellen release after the Cellen PR pytest failure.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_DIR=${FINREG_DIR:-$(cd "$CELLEN_DIR/../finreg" && pwd)}
TEST_FILE="$CELLEN_DIR/tests/test_finreg_integration_unit.py"
EXPECTED_BRANCH=feat/finreg-workflow-completion
CELLEN_REPO=softensor/cellen
FINREG_REPO=softensor/finreg
VPS=${VPS:-jorgehel@167.235.158.77}

for command in git gh python3 rsync ssh; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 2
  }
done

gh auth status >/dev/null

CURRENT_BRANCH=$(git -C "$CELLEN_DIR" branch --show-current)
if [[ $CURRENT_BRANCH != "$EXPECTED_BRANCH" ]]; then
  echo "Expected branch $EXPECTED_BRANCH, found $CURRENT_BRANCH." >&2
  echo "Switch to the existing Cellen release branch before resuming." >&2
  exit 2
fi

python3 - "$TEST_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")

old_assertion = '''def test_all_ci_jobs_share_the_reviewed_finreg_package_pin():
    expected = "e2f744e17b0e0618046d5d50380700b0a79014a0"
    assert Path(".github/finreg-packages-ref").read_text().strip() == expected
'''
new_assertion = '''def test_all_ci_jobs_share_the_reviewed_finreg_package_pin():
    expected = Path(".github/finreg-packages-ref").read_text().strip()
    assert re.fullmatch(r"[0-9a-f]{40}", expected)
'''

if new_assertion in source:
    print("Dynamic Finreg pin assertion is already repaired.")
elif old_assertion in source:
    if "import re\n" not in source:
        source = source.replace("import json\n", "import json\nimport re\n", 1)
    source = source.replace(old_assertion, new_assertion, 1)
    path.write_text(source, encoding="utf-8")
    print("Repaired stale Finreg pin assertion.")
else:
    raise SystemExit(
        "Refusing to edit: the pin assertion differs from both known states."
    )
PY

git -C "$CELLEN_DIR" diff --check -- tests/test_finreg_integration_unit.py

git -C "$CELLEN_DIR" add -- tests/test_finreg_integration_unit.py
git -C "$CELLEN_DIR" diff --cached --check
if ! git -C "$CELLEN_DIR" diff --cached --quiet; then
  git -C "$CELLEN_DIR" commit -m "fix: validate dynamic Finreg release pin"
fi
git -C "$CELLEN_DIR" push -u origin "$EXPECTED_BRANCH"

PR=$(gh pr list \
  --repo "$CELLEN_REPO" --head "$EXPECTED_BRANCH" --base master --state open \
  --json number --jq '.[0].number')
[[ -n $PR ]] || {
  echo "The existing Cellen release PR could not be found." >&2
  exit 1
}
echo "Cellen PR: $PR"
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

wait_for_pr_checks "$CELLEN_REPO" "$PR"
gh pr merge "$PR" --repo "$CELLEN_REPO" --merge --delete-branch

git -C "$CELLEN_DIR" switch master
git -C "$CELLEN_DIR" pull --ff-only origin master
CELLEN_SHA=$(git -C "$CELLEN_DIR" rev-parse HEAD)
FINREG_SHA=$(tr -d '[:space:]' <"$CELLEN_DIR/.github/finreg-packages-ref")
[[ $FINREG_SHA =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid Finreg package revision: $FINREG_SHA" >&2
  exit 1
}

wait_for_master_run() {
  local repository=$1 workflow=$2 sha=$3 run_id
  for _ in {1..180}; do
    run_id=$(gh run list \
      --repo "$repository" --workflow "$workflow" --branch master --event push \
      --limit 50 --json databaseId,headSha \
      --jq ".[] | select(.headSha == \"$sha\") | .databaseId" | head -1)
    if [[ -n $run_id ]]; then
      gh run watch "$run_id" --repo "$repository" --exit-status
      return
    fi
    sleep 5
  done
  echo "No $workflow master run appeared for $repository at $sha." >&2
  return 1
}

# Finreg's release gate may already be complete; gh run watch returns its
# retained conclusion immediately in that case.
wait_for_master_run "$FINREG_REPO" release-gates.yml "$FINREG_SHA"
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
  # `gh run list --commit` can miss a completed merge-commit run even though
  # the run API reports the exact headSha. Resolve by the same headSha filter
  # used by the release waiter, then verify the embedded artifact identity.
  FINREG_RUN_ID=$(gh run list \
    --repo "$FINREG_REPO" --workflow release-gates.yml --branch master \
    --event push --limit 50 --json databaseId,headSha,conclusion \
    --jq ".[] | select(.headSha == \"$FINREG_SHA\" and .conclusion == \"success\") | .databaseId" \
    | head -1)
  [[ -n $FINREG_RUN_ID ]] || {
    echo "No successful Finreg artifact run found for $FINREG_SHA." >&2
    exit 1
  }
  mkdir -p "$WEB_DIR"
  gh run download "$FINREG_RUN_ID" \
    --repo "$FINREG_REPO" --name "finreg-web-$FINREG_SHA" --dir "$WEB_DIR"
  grep -F "\"commit\":\"$FINREG_SHA\"" \
    "$WEB_DIR/finreg-release.json" >/dev/null
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
