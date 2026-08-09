#!/usr/bin/env bash
# Promote Rainha Njinga from shadow to a controlled fiscal pilot.
# Requires the human approvals documented in RAINHA_NJINGA_FINREG_ROLLOUT.org.
set -Eeuo pipefail

CELLEN_DIR=/var/www/cellen
FINREG_DIR=/var/www/finreg
FINREG_ENV=/etc/finreg.env
SCHOOL_ID=65794af5-2831-4709-9b53-437bb5d50515
CLIENT_KEY=cellen-rainha-njinga
CLIENT_PROMOTED=false
CHANNEL_PROMOTED=false
MODE_PROMOTED=false
PLANS_PROMOTED=false

rollback_client() {
  if [[ $MODE_PROMOTED == true ]]; then
    sudo -u postgres psql -d cellen -c \
      "UPDATE finreg_school_connections SET mode='shadow' WHERE school_id='$SCHOOL_ID'::uuid AND mode='pilot'" || true
  fi
  if [[ $CLIENT_PROMOTED == true && -n ${COMPANY_ID:-} ]]; then
    cd "$FINREG_DIR/backend" || return
    "$FINREG_DIR/.venv/bin/python" -m app.cli.set_integration_client_mode \
      "$COMPANY_ID" "$CLIENT_KEY" --non-fiscal --confirm-company-id "$COMPANY_ID" || true
  fi
  if [[ $PLANS_PROMOTED == true && -n ${COMPANY_ID:-} ]]; then
    sudo -u postgres psql -d finreg -c \
      "UPDATE recurring_invoice_templates rit SET generation_mode='draft' FROM external_entity_mappings m, integration_clients ic WHERE rit.id=m.entity_id AND m.integration_client_id=ic.id AND rit.company_id='$COMPANY_ID'::uuid AND ic.client_key='$CLIENT_KEY' AND m.entity_type='recurring_template'" || true
  fi
  if [[ $CHANNEL_PROMOTED == true ]]; then
    cd "$FINREG_DIR/backend" || return
    "$FINREG_DIR/.venv/bin/python" -m app.cli.set_agt_channel \
      5000413178 disabled || true
  fi
}
trap rollback_client ERR

[[ ${EUID} -eq 0 ]] || { echo "Run this script with sudo." >&2; exit 1; }
read -r -p "Signed reconciliation/accounting approval reference: " APPROVAL_REFERENCE
CHANNEL=offline
[[ -n $APPROVAL_REFERENCE ]] || {
  echo "Approval reference is required." >&2; exit 1;
}

COMPANY_ID=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT finreg_company_id FROM finreg_school_connections WHERE school_id = '$SCHOOL_ID'::uuid AND mode = 'shadow' AND kill_switch = false")
[[ -n $COMPANY_ID ]] || { echo "A healthy shadow connection was not found." >&2; exit 1; }

READINESS=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT (last_sync_at IS NOT NULL)::int || '|' ||
          (SELECT count(*) FROM finreg_entity_mappings WHERE school_id = '$SCHOOL_ID'::uuid AND (status <> 'confirmed' OR last_error_code IS NOT NULL)) || '|' ||
          (SELECT count(*) FROM finreg_billing_instructions WHERE school_id = '$SCHOOL_ID'::uuid AND status IN ('unknown','processing'))
   FROM finreg_school_connections WHERE school_id = '$SCHOOL_ID'::uuid")
[[ $READINESS == "1|0|0" ]] || {
  echo "Shadow readiness failed (sync-present|mapping-errors|unknown-commands = $READINESS)." >&2; exit 1;
}

set -a
source "$FINREG_ENV"
set +a
echo "Company: $COMPANY_ID"
echo "Approval: $APPROVAL_REFERENCE"
echo "Channel: $CHANNEL"
read -r -p "Type PILOT-$COMPANY_ID to enable fiscal writes: " CONFIRM
[[ $CONFIRM == "PILOT-$COMPANY_ID" ]] || { echo "Cancelled."; exit 1; }

BACKUP_DIR=/home/jorgehel/backups
install -d -o jorgehel -g jorgehel -m 0700 "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
sudo -u postgres pg_dump -Fc cellen > "$BACKUP_DIR/cellen-before-rainha-pilot-$STAMP.dump"
sudo -u postgres pg_dump -Fc finreg > "$BACKUP_DIR/finreg-before-rainha-pilot-$STAMP.dump"
chown jorgehel:jorgehel "$BACKUP_DIR"/*"$STAMP.dump"
chmod 600 "$BACKUP_DIR"/*"$STAMP.dump"

cd "$FINREG_DIR/backend"
export PYTHONPATH="$FINREG_DIR/backend"
"$FINREG_DIR/.venv/bin/python" -m app.cli.set_agt_channel \
  5000413178 "$CHANNEL"
CHANNEL_PROMOTED=true
"$FINREG_DIR/.venv/bin/python" -m app.cli.ensure_offline_series 5000413178
"$FINREG_DIR/.venv/bin/python" -m app.cli.set_integration_client_mode \
  "$COMPANY_ID" "$CLIENT_KEY" --fiscal --confirm-company-id "$COMPANY_ID"
CLIENT_PROMOTED=true
sudo -u postgres psql -v ON_ERROR_STOP=1 -d finreg -c \
  "UPDATE recurring_invoice_templates rit SET generation_mode='finalize' FROM external_entity_mappings m, integration_clients ic WHERE rit.id=m.entity_id AND m.integration_client_id=ic.id AND rit.company_id='$COMPANY_ID'::uuid AND ic.client_key='$CLIENT_KEY' AND m.entity_type='recurring_template'"
PLANS_PROMOTED=true

sudo -u postgres psql -v ON_ERROR_STOP=1 -d cellen \
  --set=school_id="$SCHOOL_ID" <<'SQL'
UPDATE finreg_school_connections
SET mode = 'pilot', kill_switch = false
WHERE school_id = :'school_id'::uuid AND mode = 'shadow';
\if :ROW_COUNT
\else
  \echo 'Shadow connection changed concurrently; stopping'
  \quit
\endif
SQL
MODE_PROMOTED=true

systemctl restart finreg-api finreg-worker finreg-beat cellen-api
sleep 5
curl --fail --silent --show-error http://127.0.0.1:8003/ready >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null
CLIENT_PROMOTED=false
CHANNEL_PROMOTED=false
MODE_PROMOTED=false
PLANS_PROMOTED=false
printf '%s RainhaNjinga company=%s channel=%s approval=%s mode=pilot\n' \
  "$(date --iso-8601=seconds)" "$COMPANY_ID" "$CHANNEL" "$APPROVAL_REFERENCE" \
  >> /var/log/cellen-finreg-rollout.log
chmod 600 /var/log/cellen-finreg-rollout.log
echo "Rainha Njinga is in PILOT. Monitor every fiscal command and event."
echo "AGT channel: $CHANNEL"
echo "Approval reference: $APPROVAL_REFERENCE"
