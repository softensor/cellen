#!/usr/bin/env bash
# Deploy the unified Finreg school-finance UI and parent collection workflow.
#
# Usage:
#   sudo deploy/deploy_finreg_school_finance.sh
#   sudo deploy/deploy_finreg_school_finance.sh --cellen-only
#
# --cellen-only is the Cellen/kit cutover window: FinReg code, migrations and
# services are never touched (the certified production stays at its release);
# only the additive scope grant and manifest fingerprint refresh run against it.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

CELLEN_ONLY=0
case ${1:-} in
  "") ;;
  --cellen-only) CELLEN_ONLY=1 ;;
  *) echo "Unknown argument: $1" >&2; exit 1 ;;
esac

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
CLIENT_KEY=cellen-rainha-njinga
SCHOOL_SLUG=rainha-njinga
TAX_ID=5000413178
source "$CELLEN_DIR/deploy/lib/wait_for_finreg_services.sh"

export FINREG_ENV=/etc/finreg.env
export CELLEN_WEB_ORIGIN=https://softensor.github.io
if [[ $CELLEN_ONLY -eq 0 ]]; then
python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["FINREG_ENV"])
origin = os.environ["CELLEN_WEB_ORIGIN"]
lines = path.read_text().splitlines()
result = []
found = False
for line in lines:
    if line.startswith("CORS_ALLOWED_ORIGINS="):
        values = [value.strip() for value in line.split("=", 1)[1].split(",")]
        if origin not in values:
            values.append(origin)
        line = "CORS_ALLOWED_ORIGINS=" + ",".join(filter(None, values))
        found = True
    result.append(line)
if not found:
    result.append(f"CORS_ALLOWED_ORIGINS={origin}")
path.write_text("\n".join(result) + "\n")
PY
fi

for required in \
  "$FINREG_DIR/backend" \
  "$FINREG_DIR/.venv/bin/alembic" \
  "$CELLEN_DIR/.venv/bin/alembic"; do
  [[ -e $required ]] || { echo "Missing required path: $required" >&2; exit 1; }
done

cd "$FINREG_DIR/backend"
set -a
source /etc/finreg.env
set +a
export PYTHONPATH="$FINREG_DIR/backend"
if [[ $CELLEN_ONLY -eq 0 ]]; then
  "$FINREG_DIR/.venv/bin/alembic" upgrade head
  "$FINREG_DIR/.venv/bin/python" -m app.cli.validate_module_manifests >/dev/null
fi
"$FINREG_DIR/.venv/bin/python" -m app.cli.refresh_company_manifest_fingerprints
# The Finreg CLI (app.cli.grant_integration_client_scopes) queries
# IntegrationClient without loading the model registry, so a standalone run
# dies with NoReferencedTableError on the companies table. Load the registry
# and call grant() directly until Finreg fixes its CLI under change control.
"$FINREG_DIR/.venv/bin/python" -c '
import asyncio
import sys

from app.models.registry import load_model_registry

load_model_registry()

from app.cli.grant_integration_client_scopes import grant

asyncio.run(grant(sys.argv[1], sys.argv[2:]))
' "$CLIENT_KEY" \
  billing_plans:read billing_plans:write \
  capabilities:read \
  customers:read customers:write \
  documents:read documents:write \
  employees:write \
  events:read \
  mappings:read mappings:write \
  payments:write \
  products:read products:write \
  receipts:read receipts:write \
  receivables:read receivables:write \
  reports:read \
  workspace:launch

cd "$CELLEN_DIR"
set -a
source .env
set +a
export PYTHONPATH="$CELLEN_DIR"

echo "==> Installing the pinned connector kit"
KIT_PIN=$(cat "$CELLEN_DIR/.github/finreg-kit-ref" 2>/dev/null || true)
[[ $KIT_PIN =~ ^[0-9a-f]{40}$ ]] || {
  echo "Missing a valid revision in .github/finreg-kit-ref." >&2
  exit 2
}
KIT_REPO=${CELLEN_FINREG_KIT_DIR:-/var/www/finreg-kit}
[[ -d $KIT_REPO/.git ]] || {
  echo "finreg-kit checkout not found at $KIT_REPO." >&2
  exit 2
}
runuser -u jorgehel -- git -C "$KIT_REPO" fetch --quiet origin
runuser -u jorgehel -- \
  git -C "$KIT_REPO" cat-file -e "$KIT_PIN^{commit}" || {
  echo "finreg-kit revision $KIT_PIN is not present in $KIT_REPO." >&2
  exit 2
}
KIT_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/cellen-finreg-kit.XXXXXX")
runuser -u jorgehel -- \
  git -C "$KIT_REPO" archive "$KIT_PIN" | tar -x -C "$KIT_STAGE"
[[ -f $KIT_STAGE/src/finreg_kit/__init__.py ]] || {
  echo "The pinned finreg-kit does not contain src/finreg_kit." >&2
  exit 2
}
"$CELLEN_DIR/.venv/bin/pip" install \
  --disable-pip-version-check --no-deps --force-reinstall "$KIT_STAGE"
rm -rf "$KIT_STAGE"
"$CELLEN_DIR/.venv/bin/alembic" upgrade head

if [[ $CELLEN_ONLY -eq 1 ]]; then
  # FinReg is certified production: the Cellen cutover never restarts it.
  systemctl restart cellen-api
else
  systemctl restart finreg-api finreg-worker finreg-beat cellen-api
fi
wait_for_finreg_services

ACCEPTANCE_MODE=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 \
  -d cellen -c "SELECT fc.mode FROM schools s JOIN finreg_school_connections fc ON fc.school_id=s.id WHERE s.slug='$SCHOOL_SLUG'")
ACCEPTANCE_CHANNEL=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 \
  -d finreg -c "SELECT agt_channel FROM companies WHERE tax_id='$TAX_ID'")
[[ -n $ACCEPTANCE_MODE && -n $ACCEPTANCE_CHANNEL ]] || {
  echo "Unable to resolve deployed acceptance mode/channel." >&2
  exit 1
}

"$CELLEN_DIR/deploy/validate_cellen_finreg_release.sh" \
  --mode "$ACCEPTANCE_MODE" \
  --agt-channel "$ACCEPTANCE_CHANNEL"

echo "Unified Finreg school finance and parent collections deployed and accepted."
