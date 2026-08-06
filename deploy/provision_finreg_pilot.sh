#!/usr/bin/env bash
# Provision the Rainha Njinga Finreg tenant and connect it to Cellen in shadow mode.
# Run on the verified VPS as: sudo bash deploy/provision_finreg_pilot.sh
set -Eeuo pipefail

CELLEN_DIR=/var/www/cellen
FINREG_DIR=/var/www/finreg
FINREG_ENV=/etc/finreg.env
CELLEN_ENV=/var/www/cellen/.env
SECRET_FILE=/etc/cellen-finreg-client-secret
SCHOOL_ID=65794af5-2831-4709-9b53-437bb5d50515
CLIENT_KEY=cellen-rainha-njinga
FINREG_URL=http://127.0.0.1:8003/api/v1

[[ ${EUID} -eq 0 ]] || { echo "Run this script with sudo." >&2; exit 1; }
for path in "$FINREG_ENV" "$CELLEN_ENV" "$FINREG_DIR/.venv/bin/python"; do
  [[ -e $path ]] || { echo "Required path missing: $path" >&2; exit 1; }
done
SCHOOL_EXISTS=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT count(*) FROM schools WHERE id = '$SCHOOL_ID'::uuid AND is_active = true")
[[ $SCHOOL_EXISTS == 1 ]] || { echo "Active Rainha Njinga record not found in Cellen." >&2; exit 1; }
EXISTING_CONNECTION=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT count(*) FROM finreg_school_connections WHERE school_id = '$SCHOOL_ID'::uuid")
[[ $EXISTING_CONNECTION == 0 ]] || {
  echo "Rainha Njinga already has a Finreg connection. Use the rollout diagnostics; do not reprovision." >&2
  exit 1
}

read -r -p "Verified legal name of Rainha Njinga: " LEGAL_NAME
read -r -p "Verified NIF: " TAX_ID
read -r -p "Finreg administrator email: " ADMIN_EMAIL
read -r -p "Finreg administrator full name: " ADMIN_NAME
read -r -s -p "New Finreg administrator password: " ADMIN_PASSWORD
echo
[[ -n $LEGAL_NAME && -n $TAX_ID && -n $ADMIN_EMAIL && -n $ADMIN_NAME && ${#ADMIN_PASSWORD} -ge 12 ]] || {
  echo "All legal/admin fields are required and the password must contain at least 12 characters." >&2
  exit 1
}
echo "This creates a real Finreg tenant for NIF $TAX_ID and leaves Cellen in SHADOW mode."
read -r -p "Type PROVISION to continue: " CONFIRM
[[ $CONFIRM == PROVISION ]] || { echo "Cancelled."; exit 1; }

WORK_DIR=$(mktemp -d /tmp/cellen-finreg-provision.XXXXXX)
trap 'rm -rf -- "$WORK_DIR"; unset ADMIN_PASSWORD' EXIT
chmod 700 "$WORK_DIR"
export LEGAL_NAME TAX_ID ADMIN_EMAIL ADMIN_NAME ADMIN_PASSWORD
python3 -c 'import json,os; print(json.dumps({
  "company_name": os.environ["LEGAL_NAME"], "tax_id": os.environ["TAX_ID"],
  "admin_email": os.environ["ADMIN_EMAIL"], "admin_full_name": os.environ["ADMIN_NAME"],
  "password": os.environ["ADMIN_PASSWORD"], "city": "Luanda"
}))' > "$WORK_DIR/register.json"

HTTP_STATUS=$(curl --silent --show-error --output "$WORK_DIR/register-response.json" \
  --write-out '%{http_code}' --request POST "$FINREG_URL/auth/register" \
  --header 'Content-Type: application/json' --data-binary @"$WORK_DIR/register.json")
[[ $HTTP_STATUS == 201 ]] || {
  echo "Finreg tenant creation failed (HTTP $HTTP_STATUS). No Cellen setting was changed." >&2
  python3 -m json.tool "$WORK_DIR/register-response.json" >&2 || true
  exit 1
}
COMPANY_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["company_id"])' "$WORK_DIR/register-response.json")

(
  set -a
  source "$FINREG_ENV"
  set +a
  cd "$FINREG_DIR/backend"
  export PYTHONPATH="$FINREG_DIR/backend"
  "$FINREG_DIR/.venv/bin/python" -m app.cli.create_integration_client \
    "$COMPANY_ID" "$CLIENT_KEY" --name "Cellen — Rainha Njinga" --vertical school --non-fiscal
) > "$WORK_DIR/client.env"
CLIENT_SECRET=$(sed -n 's/^FINREG_CLIENT_SECRET=//p' "$WORK_DIR/client.env")
[[ -n $CLIENT_SECRET ]] || { echo "Client provisioning did not return a secret." >&2; exit 1; }
printf '%s\n' "$CLIENT_SECRET" > "$WORK_DIR/client-secret"
install -o root -g jorgehel -m 0640 "$WORK_DIR/client-secret" "$SECRET_FILE"

export CELLEN_ENV CLIENT_KEY SECRET_FILE
python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["CELLEN_ENV"])
updates = {
    "FINREG_BASE_URL": "https://finreg.167.235.158.77.nip.io/api/v1",
    "FINREG_CLIENT_ID": os.environ["CLIENT_KEY"],
    "FINREG_CLIENT_SECRET_FILE": os.environ["SECRET_FILE"],
    "FINREG_TIMEOUT_SECONDS": "15",
    "FINREG_VERIFY_TLS": "true",
    "FINREG_INTEGRATION_ENABLED": "true",
}
lines = path.read_text().splitlines()
seen = set()
result = []
for line in lines:
    key = line.split("=", 1)[0] if "=" in line and not line.lstrip().startswith("#") else None
    if key in updates:
        result.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        result.append(line)
result.extend(f"{key}={value}" for key, value in updates.items() if key not in seen)
path.write_text("\n".join(result) + "\n")
PY

CONNECTION_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
sudo -u postgres psql -v ON_ERROR_STOP=1 -d cellen \
  --set=connection_id="$CONNECTION_ID" --set=school_id="$SCHOOL_ID" --set=company_id="$COMPANY_ID" \
  --set=legal_name="$LEGAL_NAME" --set=tax_id="$TAX_ID" <<'SQL'
BEGIN;
UPDATE schools SET legal_name = :'legal_name', nif = :'tax_id'
WHERE id = :'school_id'::uuid;
INSERT INTO finreg_school_connections
  (id, school_id, finreg_company_id, mode, kill_switch, last_event_sequence)
VALUES
  (:'connection_id'::uuid, :'school_id'::uuid, :'company_id'::uuid, 'shadow', false, 0)
ON CONFLICT (school_id) DO UPDATE SET
  finreg_company_id = EXCLUDED.finreg_company_id,
  mode = 'shadow', kill_switch = false, last_event_sequence = 0;
COMMIT;
SQL

systemctl restart cellen-api
sleep 5
curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null
echo "Provisioned company $COMPANY_ID. Rainha Njinga is connected in SHADOW mode."
echo "The integration client remains non-fiscal; pilot/live writes are intentionally impossible."
