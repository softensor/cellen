#!/usr/bin/env bash
# Deploy the current merged Cellen/Finreg revisions and activate the matching
# CI-built Finreg Web artifact previously copied into /tmp by the local release.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
FINREG_URL=https://finreg.167.235.158.77.nip.io

for required in "$FINREG_DIR/.git" "$CELLEN_DIR/.git"; do
  [[ -e $required ]] || { echo "Missing required path: $required" >&2; exit 2; }
done

sudo -u jorgehel git -C "$FINREG_DIR" switch master
sudo -u jorgehel git -C "$FINREG_DIR" pull --ff-only origin master
sudo -u jorgehel git -C "$CELLEN_DIR" switch master
sudo -u jorgehel git -C "$CELLEN_DIR" pull --ff-only origin master

FINREG_SHA=$(git -C "$FINREG_DIR" rev-parse HEAD)
WEB_DIR=/tmp/finreg-web-$FINREG_SHA
[[ -f $WEB_DIR/finreg-release.json ]] || {
  echo "Missing transferred Finreg Web artifact: $WEB_DIR" >&2
  echo "Run the local release script first." >&2
  exit 2
}

bash "$CELLEN_DIR/deploy/deploy_finreg_school_finance.sh"

DEPLOYED_SHA=$(curl --fail --silent --show-error \
  "$FINREG_URL/finreg-release.json" | sed -n 's/.*"commit":"\([0-9a-f]\{40\}\)".*/\1/p')
if [[ $DEPLOYED_SHA != "$FINREG_SHA" ]]; then
  bash "$FINREG_DIR/scripts/deploy-web-release.sh" "$WEB_DIR" "$FINREG_SHA"
else
  echo "Finreg Web is already active: $FINREG_SHA"
fi

bash "$FINREG_DIR/scripts/validate-web-release.sh" "$FINREG_URL" "$FINREG_SHA"
systemctl is-active finreg-api finreg-worker finreg-beat cellen-api
curl --fail --silent --show-error http://127.0.0.1:8003/ready
echo
curl --fail --silent --show-error http://127.0.0.1:8001/health
echo
curl --fail --silent --show-error "$FINREG_URL/finreg-release.json"
echo

echo "Cellen and Finreg release completed: $FINREG_SHA"
