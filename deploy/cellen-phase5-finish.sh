#!/usr/bin/env bash
# Finish the Phase 5 cutover after the FinReg scope-grant CLI defect.
#
#   - grants the additive scope bundle using the registry-loading workaround
#     (the CLI skips load_model_registry(), so the companies FK cannot resolve)
#   - re-proves FinReg revision and service uptimes are unchanged
#   - runs the acceptance suite with the live mode/channel
#
# Run on the VPS:
#   sudo bash ~/cellen-phase5-finish.sh
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
CLIENT_KEY=cellen-rainha-njinga
SCHOOL_SLUG=rainha-njinga
TAX_ID=5000413178
FINREG_SHA_EXPECTED=${EXPECTED_FINREG_SHA:-4977a0b}

fail() { echo "PHASE 5 FINISH FAILED: $*" >&2; exit 1; }

FINREG_SHA_BEFORE=$(git -c "safe.directory=$FINREG_DIR" -C "$FINREG_DIR" rev-parse HEAD)
FINREG_UPTIME_BEFORE=$(systemctl show -p ActiveEnterTimestamp finreg-api finreg-worker finreg-beat)
[[ $FINREG_SHA_BEFORE == "$FINREG_SHA_EXPECTED"* ]] \
  || fail "FinReg is not at the certified revision ${FINREG_SHA_EXPECTED}... ($FINREG_SHA_BEFORE)"
curl -fsS -o /dev/null http://127.0.0.1:8001/health || fail "Cellen is not healthy"
curl -fsS -o /dev/null http://127.0.0.1:8003/health || fail "FinReg is not healthy"

echo "== Scopes before ========================================================="
sudo -u postgres psql -X -A -t -d finreg \
  -c "SELECT allowed_scopes FROM integration_clients WHERE client_key='$CLIENT_KEY'"

echo
echo "== Granting the additive scope bundle ===================================="
cd "$FINREG_DIR/backend"
set -a
# shellcheck disable=SC1091
source /etc/finreg.env
set +a
export PYTHONPATH="$FINREG_DIR/backend"
"$FINREG_DIR/.venv/bin/python" - <<'PY'
import asyncio

from app.models.registry import load_model_registry

# Non-ASGI CLI processes must populate the ORM table registry before the first
# mapper flush; the grant CLI forgets this, so integration_clients -> companies
# raises NoReferencedTableError. Same code path as the CLI, registry loaded.
load_model_registry()

from app.cli.grant_integration_client_scopes import grant

SCOPES = [
    "billing_plans:read", "billing_plans:write",
    "capabilities:read",
    "customers:read", "customers:write",
    "documents:read", "documents:write",
    "employees:write",
    "events:read",
    "mappings:read", "mappings:write",
    "payments:write",
    "products:read", "products:write",
    "receipts:read", "receipts:write",
    "receivables:read", "receivables:write",
    "reports:read",
    "workspace:launch",
]
asyncio.run(grant("cellen-rainha-njinga", SCOPES))
PY

echo
echo "== Scopes after =========================================================="
sudo -u postgres psql -X -A -t -d finreg \
  -c "SELECT allowed_scopes FROM integration_clients WHERE client_key='$CLIENT_KEY'"

echo
echo "== FinReg untouched check ================================================"
[[ $(git -c "safe.directory=$FINREG_DIR" -C "$FINREG_DIR" rev-parse HEAD) == "$FINREG_SHA_BEFORE" ]] \
  || fail "FinReg checkout changed"
[[ $(systemctl show -p ActiveEnterTimestamp finreg-api finreg-worker finreg-beat) == "$FINREG_UPTIME_BEFORE" ]] \
  || fail "a FinReg service was restarted"
echo "FinReg revision and service uptimes unchanged."

echo
echo "== Acceptance ============================================================"
MODE=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 -d cellen -c \
  "SELECT fc.mode FROM schools s JOIN finreg_school_connections fc ON fc.school_id=s.id WHERE s.slug='$SCHOOL_SLUG'")
CHANNEL=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 -d finreg -c \
  "SELECT agt_channel FROM companies WHERE tax_id='$TAX_ID'")
[[ -n $MODE && -n $CHANNEL ]] || fail "could not resolve acceptance mode/channel"
echo "Acceptance mode=$MODE channel=$CHANNEL"
"$CELLEN_DIR/deploy/validate_cellen_finreg_release.sh" --mode "$MODE" --agt-channel "$CHANNEL"

echo
echo "== Health ================================================================"
curl -fsS -o /dev/null -w 'Cellen health: %{http_code}\n' http://127.0.0.1:8001/health
curl -fsS -o /dev/null -w 'FinReg health: %{http_code}\n' http://127.0.0.1:8003/health
echo "PHASE 5 FINISH COMPLETE"
