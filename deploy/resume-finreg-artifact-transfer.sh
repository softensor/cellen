#!/usr/bin/env bash
# Resume only the post-merge Finreg Web artifact transfer after all Finreg and
# Cellen master checks have succeeded.
set -Eeuo pipefail

CELLEN_DIR=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
FINREG_REPO=softensor/finreg
VPS=${VPS:-jorgehel@167.235.158.77}

for command in git gh rsync ssh; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 2
  }
done
gh auth status >/dev/null

[[ $(git -C "$CELLEN_DIR" branch --show-current) == master ]] || {
  echo "Cellen must be on merged master before artifact transfer." >&2
  exit 2
}
git -C "$CELLEN_DIR" pull --ff-only origin master

CELLEN_SHA=$(git -C "$CELLEN_DIR" rev-parse HEAD)
FINREG_SHA=$(tr -d '[:space:]' <"$CELLEN_DIR/.github/finreg-packages-ref")
[[ $FINREG_SHA =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid Finreg package revision: $FINREG_SHA" >&2
  exit 1
}

RUN_ID=$(gh run list \
  --repo "$FINREG_REPO" --workflow release-gates.yml --branch master \
  --event push --limit 50 --json databaseId,headSha,conclusion \
  --jq ".[] | select(.headSha == \"$FINREG_SHA\" and .conclusion == \"success\") | .databaseId" \
  | head -1)
[[ -n $RUN_ID ]] || {
  echo "No successful Finreg release-gates run found for $FINREG_SHA." >&2
  exit 1
}

WEB_DIR=/tmp/finreg-web-$FINREG_SHA
if [[ -f $WEB_DIR/finreg-release.json ]] && \
   grep -F "\"commit\":\"$FINREG_SHA\"" "$WEB_DIR/finreg-release.json" >/dev/null; then
  echo "Reusing verified artifact $WEB_DIR."
else
  [[ ! -e $WEB_DIR ]] || {
    echo "Artifact directory exists with the wrong identity: $WEB_DIR" >&2
    exit 1
  }
  mkdir -p "$WEB_DIR"
  gh run download "$RUN_ID" \
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
echo "Verified artifact transferred. On the VPS run exactly:"
echo "cd /var/www/cellen && git pull --ff-only origin master && sudo bash deploy/release_cellen_finreg_from_vps.sh"
