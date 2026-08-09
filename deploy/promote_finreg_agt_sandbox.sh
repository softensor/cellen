#!/usr/bin/env bash
# Connect an existing offline pilot to AGT homologation without replaying data.
set -Eeuo pipefail

FINREG_DIR=/var/www/finreg
CELLEN_DIR=/var/www/cellen
source "$CELLEN_DIR/deploy/lib/wait_for_finreg_services.sh"
TAX_ID=5000413178
CHANNEL_CHANGED=false
SERIES_CHANGED=false

rollback_channel() {
  if [[ $CHANNEL_CHANGED == true ]]; then
    cd "$FINREG_DIR/backend" || return
    "$FINREG_DIR/.venv/bin/python" -m app.cli.set_agt_channel "$TAX_ID" offline || true
    systemctl restart finreg-api finreg-worker finreg-beat cellen-api || true
  fi
  if [[ $SERIES_CHANGED == true ]]; then
    sudo -u postgres psql -d finreg -c \
      "UPDATE document_series SET is_active=true WHERE company_id=(SELECT id FROM companies WHERE tax_id='$TAX_ID') AND series_code LIKE 'OFF%'" || true
  fi
}
trap rollback_channel ERR
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

MODE=$(sudo -u postgres psql -At -d cellen -c \
  "SELECT fc.mode FROM schools s JOIN finreg_school_connections fc ON fc.school_id=s.id WHERE s.slug='rainha-njinga'")
CHANNEL=$(sudo -u postgres psql -At -d finreg -c \
  "SELECT agt_channel FROM companies WHERE tax_id='$TAX_ID'")
[[ $MODE == pilot && $CHANNEL == offline ]] || {
  echo "Expected pilot+offline; current=$MODE+$CHANNEL" >&2; exit 1;
}

set -a
source /etc/finreg.env
set +a
for name in AGT_FE_USERNAME AGT_FE_PASSWORD AGT_SOFTWARE_PRIVATE_KEY_PEM AGT_SOFTWARE_VALIDATION_NUMBER AGT_SOFTWARE_PRODUCER_TAX_ID; do
  [[ -n ${!name:-} ]] || { echo "Required sandbox setting is absent: $name" >&2; exit 1; }
done
TENANT_KEY=$(sudo -u postgres psql -At -d finreg -c \
  "SELECT (private_key_pem IS NOT NULL)::int FROM companies WHERE tax_id='$TAX_ID'")
[[ $TENANT_KEY == 1 ]] || { echo "Tenant signing key is missing." >&2; exit 1; }

read -r -p "AGT homologation approval/reference: " APPROVAL_REFERENCE
[[ -n $APPROVAL_REFERENCE ]] || { echo "Approval reference is required." >&2; exit 1; }
read -r -p "Type SANDBOX-$TAX_ID to enable AGT homologation transport: " CONFIRM
[[ $CONFIRM == "SANDBOX-$TAX_ID" ]] || { echo "Cancelled."; exit 1; }

cd "$FINREG_DIR/backend"
export PYTHONPATH="$FINREG_DIR/backend"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d finreg -c \
  "UPDATE document_series SET is_active=false WHERE company_id=(SELECT id FROM companies WHERE tax_id='$TAX_ID') AND series_code LIKE 'OFF%'"
SERIES_CHANGED=true
"$FINREG_DIR/.venv/bin/python" -m app.cli.set_agt_channel "$TAX_ID" sandbox
CHANNEL_CHANGED=true
systemctl restart finreg-api finreg-worker finreg-beat cellen-api
wait_for_finreg_services
CHANNEL_CHANGED=false
SERIES_CHANGED=false
printf '%s RainhaNjinga channel=sandbox approval=%s no_automatic_replay=true\n' \
  "$(date --iso-8601=seconds)" "$APPROVAL_REFERENCE" >> /var/log/cellen-finreg-rollout.log
chmod 600 /var/log/cellen-finreg-rollout.log
echo "Rainha Njinga is pilot+sandbox. Offline documents were not submitted."
echo "Create sandbox series in Finreg and wait for AGT confirmation before issuing."
