#!/usr/bin/env bash
# Promote Rainha Njinga after a signed, complete pilot billing/settlement cycle.
set -Eeuo pipefail

SCHOOL_ID=65794af5-2831-4709-9b53-437bb5d50515
CHANNEL_CHANGED=false
MODE_CHANGED=false

rollback_channel() {
  if [[ $MODE_CHANGED == true ]]; then
    sudo -u postgres psql -d cellen -c \
      "UPDATE finreg_school_connections SET mode='pilot' WHERE school_id='$SCHOOL_ID'::uuid AND mode='live'" || true
  fi
  if [[ $CHANNEL_CHANGED == true ]]; then
    cd /var/www/finreg/backend || return
    ../.venv/bin/python -m app.cli.set_agt_channel 5000413178 sandbox || true
    systemctl restart finreg-api finreg-worker finreg-beat cellen-api || true
  fi
}
trap rollback_channel ERR
[[ ${EUID} -eq 0 ]] || { echo "Run this script with sudo." >&2; exit 1; }
read -r -p "Signed pilot-cycle/go-live approval reference: " APPROVAL_REFERENCE
[[ -n $APPROVAL_REFERENCE ]] || { echo "Approval reference is required." >&2; exit 1; }

STATE=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT mode || '|' || kill_switch::int || '|' ||
          (SELECT count(*) FROM finreg_billing_instructions WHERE school_id = '$SCHOOL_ID'::uuid AND status IN ('pending','processing','unknown','rejected'))
   FROM finreg_school_connections WHERE school_id = '$SCHOOL_ID'::uuid")
[[ $STATE == "pilot|0|0" ]] || {
  echo "Live readiness failed (mode|kill-switch|unresolved-commands = $STATE)." >&2; exit 1;
}

AGT_CHANNEL=$(sudo -u postgres psql -At -d finreg -c \
  "SELECT agt_channel FROM companies WHERE tax_id='5000413178'")
[[ $AGT_CHANNEL == sandbox ]] || {
  echo "Live promotion requires a completed sandbox pilot; current channel=$AGT_CHANNEL" >&2
  exit 1
}
set -a
source /etc/finreg.env
set +a
for name in AGT_FE_USERNAME AGT_FE_PASSWORD AGT_SOFTWARE_PRIVATE_KEY_PEM AGT_SOFTWARE_VALIDATION_NUMBER AGT_SOFTWARE_PRODUCER_TAX_ID; do
  [[ -n ${!name:-} ]] || { echo "Required production setting is absent: $name" >&2; exit 1; }
done
ENROLLED=$(sudo -u postgres psql -At -d finreg -c \
  "SELECT (cert_enrolled_at IS NOT NULL)::int FROM companies WHERE tax_id='5000413178'")
[[ $ENROLLED == 1 ]] || { echo "AGT production enrollment is not recorded." >&2; exit 1; }

read -r -p "Type LIVE-$SCHOOL_ID to make Finreg authoritative: " CONFIRM
[[ $CONFIRM == "LIVE-$SCHOOL_ID" ]] || { echo "Cancelled."; exit 1; }

BACKUP_DIR=/home/jorgehel/backups
install -d -o jorgehel -g jorgehel -m 0700 "$BACKUP_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
sudo -u postgres pg_dump -Fc cellen > "$BACKUP_DIR/cellen-before-rainha-live-$STAMP.dump"
sudo -u postgres pg_dump -Fc finreg > "$BACKUP_DIR/finreg-before-rainha-live-$STAMP.dump"
chown jorgehel:jorgehel "$BACKUP_DIR"/*"$STAMP.dump"
chmod 600 "$BACKUP_DIR"/*"$STAMP.dump"

cd /var/www/finreg/backend
set -a
source /etc/finreg.env
set +a
export PYTHONPATH=/var/www/finreg/backend
../.venv/bin/python -m app.cli.set_agt_channel 5000413178 production
CHANNEL_CHANGED=true

sudo -u postgres psql -v ON_ERROR_STOP=1 -d cellen -c \
  "UPDATE finreg_school_connections SET mode = 'live' WHERE school_id = '$SCHOOL_ID'::uuid AND mode = 'pilot' AND kill_switch = false"
MODE_CHANGED=true
systemctl restart finreg-api finreg-worker finreg-beat cellen-api
sleep 5
curl --fail --silent --show-error http://127.0.0.1:8003/ready >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null
CHANNEL_CHANGED=false
MODE_CHANGED=false
printf '%s RainhaNjinga channel=approved approval=%s mode=live\n' \
  "$(date --iso-8601=seconds)" "$APPROVAL_REFERENCE" >> /var/log/cellen-finreg-rollout.log
chmod 600 /var/log/cellen-finreg-rollout.log
echo "Rainha Njinga is LIVE. Finreg is authoritative for new fiscal operations."
