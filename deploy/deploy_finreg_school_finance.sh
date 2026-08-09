#!/usr/bin/env bash
# Deploy the unified Finreg school-finance UI and parent collection workflow.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
CLIENT_KEY=cellen-rainha-njinga

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
"$FINREG_DIR/.venv/bin/python" -m app.cli.grant_integration_client_scopes \
  "$CLIENT_KEY" documents:read documents:write payments:write \
  receipts:read receipts:write reports:read billing_plans:read billing_plans:write

cd "$CELLEN_DIR"
set -a
source .env
set +a
export PYTHONPATH="$CELLEN_DIR"
"$CELLEN_DIR/.venv/bin/alembic" upgrade head

systemctl restart finreg-api finreg-worker finreg-beat cellen-api
sleep 8

for service in finreg-api finreg-worker finreg-beat cellen-api; do
  systemctl is-active --quiet "$service"
done
curl --fail --silent --show-error http://127.0.0.1:8003/ready >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null

"$CELLEN_DIR/deploy/validate_cellen_finreg_release.sh" \
  --mode "${FINREG_ACCEPTANCE_MODE:-shadow}"

echo "Unified Finreg school finance and parent collections deployed and accepted."
