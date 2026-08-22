#!/usr/bin/env bash
# Deploy the unified Finreg school-finance UI and parent collection workflow.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
CLIENT_KEY=cellen-rainha-njinga
SCHOOL_SLUG=rainha-njinga
TAX_ID=5000413178
source "$CELLEN_DIR/deploy/lib/wait_for_finreg_services.sh"

export FINREG_ENV=/etc/finreg.env
export CELLEN_WEB_ORIGIN=https://softensor.github.io
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
"$FINREG_DIR/.venv/bin/alembic" upgrade head
"$FINREG_DIR/.venv/bin/python" -m app.cli.validate_module_manifests >/dev/null
"$FINREG_DIR/.venv/bin/python" -m app.cli.refresh_company_manifest_fingerprints
"$FINREG_DIR/.venv/bin/python" -m app.cli.grant_integration_client_scopes \
  "$CLIENT_KEY" documents:read documents:write payments:write \
  receipts:read receipts:write reports:read billing_plans:read billing_plans:write \
  products:read products:write employees:write workspace:launch

cd "$CELLEN_DIR"
set -a
source .env
set +a
export PYTHONPATH="$CELLEN_DIR"
"$CELLEN_DIR/.venv/bin/alembic" upgrade head

systemctl restart finreg-api finreg-worker finreg-beat cellen-api
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
