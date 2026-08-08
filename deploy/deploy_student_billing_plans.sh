#!/usr/bin/env bash
# Deploy the Finreg-owned Student Billing Plan cutover on the verified VPS.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
CLIENT_KEY=cellen-rainha-njinga

for required in "$FINREG_DIR/backend" "$FINREG_DIR/.venv/bin/alembic" "$CELLEN_DIR/.venv/bin/python"; do
  [[ -e $required ]] || { echo "Missing required path: $required" >&2; exit 1; }
done

cd "$FINREG_DIR/backend"
set -a
source /etc/finreg.env
set +a
export PYTHONPATH="$FINREG_DIR/backend"
"$FINREG_DIR/.venv/bin/alembic" upgrade head
"$FINREG_DIR/.venv/bin/python" -m app.cli.validate_module_manifests >/dev/null
"$FINREG_DIR/.venv/bin/python" -m app.cli.set_company_profile \
  5000413178 school
"$FINREG_DIR/.venv/bin/python" -m app.cli.grant_integration_client_scopes \
  "$CLIENT_KEY" billing_plans:read billing_plans:write

systemctl restart finreg-api finreg-worker finreg-beat
systemctl restart cellen-api
sleep 8

systemctl is-active --quiet finreg-api
systemctl is-active --quiet finreg-worker
systemctl is-active --quiet finreg-beat
systemctl is-active --quiet cellen-api
curl --fail --silent --show-error http://127.0.0.1:8003/ready >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null

echo "Student Billing Plans deployed. Rainha Njinga remains in its configured safety mode."
