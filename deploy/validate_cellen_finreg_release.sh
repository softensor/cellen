#!/usr/bin/env bash
# One-command production acceptance for the Cellen–Finreg school vertical.
set -uo pipefail

FINREG_DIR=${FINREG_DIR:-/var/www/finreg}
CELLEN_DIR=${CELLEN_DIR:-/var/www/cellen}
SCHOOL_SLUG=${SCHOOL_SLUG:-rainha-njinga}
TAX_ID=${TAX_ID:-5000413178}
CLIENT_KEY=${CLIENT_KEY:-cellen-rainha-njinga}
EXPECTED_MODE=${EXPECTED_MODE:-shadow}
EXPECTED_AGT_CHANNEL=${EXPECTED_AGT_CHANNEL:-}
REPORT_DIR=${REPORT_DIR:-/home/jorgehel/backups}
RUN_SCHEDULER=1
STARTED_AT=$(date --iso-8601=seconds)
REPORT="$REPORT_DIR/cellen-finreg-acceptance-$(date -u +%Y%m%d-%H%M%S).org"
PASS=0 FAIL=0 WARN=0

usage() { echo "Usage: sudo bash $0 [--mode shadow|pilot|live] [--agt-channel disabled|offline|sandbox|production] [--no-scheduler]"; }
while (($#)); do
  case "$1" in
    --mode) [[ $# -ge 2 ]] || { usage; exit 2; }; EXPECTED_MODE=$2; shift 2 ;;
    --agt-channel) [[ $# -ge 2 ]] || { usage; exit 2; }; EXPECTED_AGT_CHANNEL=$2; shift 2 ;;
    --no-scheduler) RUN_SCHEDULER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
[[ $EXPECTED_MODE =~ ^(shadow|pilot|live)$ ]] || { echo 'Invalid mode.' >&2; exit 2; }
if [[ -z $EXPECTED_AGT_CHANNEL ]]; then
  case "$EXPECTED_MODE" in
    shadow) EXPECTED_AGT_CHANNEL=disabled ;;
    pilot) EXPECTED_AGT_CHANNEL=offline ;;
    live) EXPECTED_AGT_CHANNEL=production ;;
  esac
fi
[[ $EXPECTED_AGT_CHANNEL =~ ^(disabled|offline|sandbox|production)$ ]] || { echo 'Invalid AGT channel.' >&2; exit 2; }
[[ "$EXPECTED_MODE|$EXPECTED_AGT_CHANNEL" =~ ^(shadow\|disabled|pilot\|(offline|sandbox)|live\|production)$ ]] || {
  echo 'Invalid operational-mode/AGT-channel combination.' >&2; exit 2;
}

install -d -m 0700 -o jorgehel -g jorgehel "$REPORT_DIR"
umask 077
printf '#+TITLE: Cellen–Finreg Production Acceptance\n#+DATE: %s\n\n' "$STARTED_AT" >"$REPORT"
record() { printf -- '- [%s] %s%s\n' "$1" "$2" "${3:+ :: $3}" | tee -a "$REPORT"; }
pass() { PASS=$((PASS+1)); record X "$1" "${2:-}"; }
fail() { FAIL=$((FAIL+1)); record ' ' "$1" "${2:-}"; }
warn() { WARN=$((WARN+1)); record '!' "$1" "${2:-}"; }
check() {
  local label=$1 output; shift
  if output=$("$@" 2>&1); then pass "$label" "${output//$'\n'/; }"; return 0; fi
  fail "$label" "${output//$'\n'/; }"; return 1
}
sql() { sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }

printf '* Runtime and repositories\n\n' >>"$REPORT"
for path in "$FINREG_DIR/backend" "$CELLEN_DIR/app" /etc/finreg.env /etc/cellen-finreg-client-secret; do
  [[ -e $path ]] && pass "Required path $path" || fail "Required path $path" missing
done
for repo in "$FINREG_DIR" "$CELLEN_DIR"; do
  # The suite runs under sudo, but Git metadata belongs to the deployment
  # account. Running status as root can refresh .git/index with root ownership
  # and prevent the next normal deployment pull.
  branch=$(sudo -u jorgehel git -C "$repo" branch --show-current 2>/dev/null || true)
  commit=$(sudo -u jorgehel git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)
  [[ -n $branch && -n $commit ]] && pass "$(basename "$repo") revision" "$branch @ $commit" || fail "$(basename "$repo") revision"
  dirty=$(sudo -u jorgehel git -C "$repo" status --short --untracked-files=no 2>/dev/null || true)
  [[ -z $dirty ]] && pass "$(basename "$repo") tracked worktree is clean" || warn "$(basename "$repo") tracked worktree is dirty" "${dirty//$'\n'/; }"
done
for service in finreg-api finreg-worker finreg-beat cellen-api; do
  check "$service is active" systemctl is-active --quiet "$service"
done
check 'Finreg is ready' curl -fsS http://127.0.0.1:8003/ready
check 'Cellen is healthy' curl -fsS http://127.0.0.1:8001/health
check 'Redis is ready' redis-cli ping
check 'Finreg PostgreSQL is ready' sudo -u postgres psql -X -d finreg -c 'SELECT 1;'
check 'Cellen PostgreSQL is ready' sudo -u postgres psql -X -d cellen -c 'SELECT 1;'

printf '\n* Migration state\n\n' >>"$REPORT"
migration_state() {
  local app=$1 dir=$2 env_file=$3 venv=$4 current head
  current=$(cd "$dir" && set -a && source "$env_file" && set +a && export PYTHONPATH="$dir" && "$venv/alembic" current 2>/dev/null | awk '{print $1}' | tail -1)
  head=$(cd "$dir" && set -a && source "$env_file" && set +a && export PYTHONPATH="$dir" && "$venv/alembic" heads 2>/dev/null | awk '{print $1}' | tail -1)
  [[ -n $current && $current == "$head" ]] && pass "$app migration is at head" "$current" || fail "$app migration is at head" "current=$current head=$head"
}
migration_state Finreg "$FINREG_DIR/backend" /etc/finreg.env "$FINREG_DIR/.venv/bin"
migration_state Cellen "$CELLEN_DIR" "$CELLEN_DIR/.env" "$CELLEN_DIR/.venv/bin"

printf '\n* Tenant and authorization boundary\n\n' >>"$REPORT"
company=$(sql finreg "SELECT id||'|'||vertical_profile||'|'||COALESCE(module_manifest_fingerprint,'')||'|'||agt_channel FROM companies WHERE tax_id='$TAX_ID';" 2>/dev/null || true)
IFS='|' read -r company_id profile stored_fingerprint agt_channel <<<"$company"
[[ -n ${company_id:-} ]] && pass 'Finreg company exists' "$company_id" || fail 'Finreg company exists' "tax_id=$TAX_ID"
[[ ${profile:-} == school ]] && pass 'School vertical is enabled' || fail 'School vertical is enabled' "${profile:-missing}"
[[ ${agt_channel:-} == "$EXPECTED_AGT_CHANNEL" ]] && pass 'AGT channel' "$agt_channel" || fail 'AGT channel' "expected=$EXPECTED_AGT_CHANNEL actual=${agt_channel:-missing}"
if [[ $EXPECTED_AGT_CHANNEL == offline || $EXPECTED_AGT_CHANNEL == disabled ]]; then
  pass 'AGT network policy' 'transport is structurally disabled'
else
  set -a
  source /etc/finreg.env
  set +a
  missing_agt=()
  for name in AGT_FE_USERNAME AGT_FE_PASSWORD AGT_SOFTWARE_PRIVATE_KEY_PEM AGT_SOFTWARE_VALIDATION_NUMBER AGT_SOFTWARE_PRODUCER_TAX_ID; do
    [[ -n ${!name:-} ]] || missing_agt+=("$name")
  done
  tenant_key=$(sql finreg "SELECT (private_key_pem IS NOT NULL)::int FROM companies WHERE id='$company_id';" 2>/dev/null || true)
  [[ $tenant_key == 1 ]] || missing_agt+=(tenant_private_key)
  if ((${#missing_agt[@]} == 0)); then
    pass 'AGT network configuration is complete' "$EXPECTED_AGT_CHANNEL"
  else
    fail 'AGT network configuration is complete' "missing=${missing_agt[*]}"
  fi
fi
if [[ $EXPECTED_AGT_CHANNEL == offline ]]; then
  local_series=$(sql finreg "SELECT count(*) FROM document_series WHERE company_id='$company_id' AND is_active=true AND document_type='invoice' AND series_code LIKE 'OFF%';" 2>/dev/null || echo -1)
  [[ $local_series -ge 1 ]] && pass 'Offline invoice series is active' "$local_series" || fail 'Offline invoice series is active' "$local_series"
elif [[ $EXPECTED_AGT_CHANNEL == sandbox || $EXPECTED_AGT_CHANNEL == production ]]; then
  confirmed_series=$(sql finreg "SELECT count(*) FROM document_series ds JOIN agt_series_notifications n ON n.series_id=ds.id AND n.confirmed_at IS NOT NULL WHERE ds.company_id='$company_id' AND ds.is_active=true AND ds.document_type='invoice' AND ds.series_code NOT LIKE 'OFF%';" 2>/dev/null || echo -1)
  [[ $confirmed_series -ge 1 ]] && pass 'AGT-confirmed invoice series is active' "$confirmed_series" || fail 'AGT-confirmed invoice series is active' "$confirmed_series"
fi
fingerprint=$(cd "$FINREG_DIR/backend" && set -a && source /etc/finreg.env && set +a && export PYTHONPATH="$FINREG_DIR/backend" && "$FINREG_DIR/.venv/bin/python" -c 'from app.core.module_registry import module_registry; print(module_registry.resolve("school", [], "angola").fingerprint)' 2>/dev/null || true)
[[ -n $fingerprint && $fingerprint == "$stored_fingerprint" ]] && pass 'Module manifest fingerprint matches deployed code' "$fingerprint" || fail 'Module manifest fingerprint matches deployed code' "stored=$stored_fingerprint resolved=$fingerprint"
client=$(sql finreg "SELECT status||'|'||non_fiscal||'|'||allowed_scopes::text FROM integration_clients WHERE client_key='$CLIENT_KEY';" 2>/dev/null || true)
[[ $client == active\|* ]] && pass 'Integration client is active' "$client" || fail 'Integration client is active' "${client:-missing}"
client_non_fiscal=${client#*|}; client_non_fiscal=${client_non_fiscal%%|*}
if [[ $EXPECTED_MODE == shadow ]]; then
  [[ $client_non_fiscal == true ]] && pass 'Shadow client is non-fiscal' || fail 'Shadow client is non-fiscal' "$client_non_fiscal"
else
  [[ $client_non_fiscal == false ]] && pass 'Pilot/live client permits fiscal operations' || fail 'Pilot/live client permits fiscal operations' "$client_non_fiscal"
fi
for scope in documents:read documents:write payments:write receipts:read receipts:write reports:read billing_plans:read billing_plans:write; do
  [[ $client == *\"$scope\"* ]] && pass "Scope $scope" || fail "Scope $scope"
done
permissions=$(stat -c '%U|%G|%a' /etc/cellen-finreg-client-secret 2>/dev/null || true)
[[ $permissions == root\|jorgehel\|640 ]] && pass 'Secret file permissions' "$permissions" || fail 'Secret file permissions' "$permissions"
connection=$(sql cellen "SELECT fc.mode||'|'||fc.kill_switch||'|'||fc.finreg_company_id FROM schools s JOIN finreg_school_connections fc ON fc.school_id=s.id WHERE s.slug='$SCHOOL_SLUG';" 2>/dev/null || true)
IFS='|' read -r mode kill_switch linked_company <<<"$connection"
[[ ${mode:-} == "$EXPECTED_MODE" ]] && pass 'Integration mode' "$mode" || fail 'Integration mode' "expected=$EXPECTED_MODE actual=${mode:-missing}"
[[ ${kill_switch:-} == false ]] && pass 'Kill switch is open' || fail 'Kill switch is open' "${kill_switch:-missing}"
[[ -n ${company_id:-} && ${linked_company:-} == "$company_id" ]] && pass 'Cellen links to the correct Finreg tenant' "$company_id" || fail 'Cellen links to the correct Finreg tenant'
mapping_errors=$(sql cellen "SELECT count(*) FROM finreg_entity_mappings m JOIN schools s ON s.id=m.school_id WHERE s.slug='$SCHOOL_SLUG' AND (m.status<>'confirmed' OR m.last_error_code IS NOT NULL);" 2>/dev/null || echo query_failed)
[[ $mapping_errors == 0 ]] && pass 'No unresolved mapping errors' || fail 'No unresolved mapping errors' "$mapping_errors"
outbox_errors=$(sql cellen "SELECT count(*) FROM finreg_billing_instructions i JOIN schools s ON s.id=i.school_id WHERE s.slug='$SCHOOL_SLUG' AND i.status IN ('failed','unknown');" 2>/dev/null || echo query_failed)
[[ $outbox_errors == 0 ]] && pass 'No failed or unknown billing instructions' || fail 'No failed or unknown billing instructions' "$outbox_errors"

printf '\n* Billing plan and scheduler\n\n' >>"$REPORT"
plan=$(sql finreg "SELECT id||'|'||frequency||'|'||interval_count||'|'||due_days||'|'||next_run_date||'|'||generation_mode||'|'||is_active FROM recurring_invoice_templates WHERE company_id='$company_id' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null || true)
IFS='|' read -r plan_id frequency interval due_days next_run generation_mode active <<<"$plan"
[[ -n ${plan_id:-} ]] && pass 'Billing plan exists' "$plan_id" || fail 'Billing plan exists'
[[ ${frequency:-} =~ ^(weekly|monthly|quarterly|annual)$ && ${interval:-0} -ge 1 && ${due_days:-x} =~ ^[0-9]+$ && -n ${next_run:-} ]] && pass 'Billing plan schedule is complete' "$frequency/$interval due=$due_days next=$next_run" || fail 'Billing plan schedule is complete'
expected_generation=draft
[[ $EXPECTED_MODE == shadow ]] || expected_generation=finalize
[[ ${generation_mode:-} == "$expected_generation" && ${active:-} == true ]] && pass 'Billing plan generation mode' "$generation_mode" || fail 'Billing plan generation mode' "expected=$expected_generation actual=${generation_mode:-missing} active=${active:-missing}"
if [[ $RUN_SCHEDULER -eq 1 && -n ${plan_id:-} ]]; then
  before=$(sql finreg "SELECT count(*) FROM documents WHERE recurring_template_id='$plan_id';" 2>/dev/null || echo -1)
  task=$(cd "$FINREG_DIR/backend" && set -a && source /etc/finreg.env && set +a && export PYTHONPATH="$FINREG_DIR/backend" && "$FINREG_DIR/.venv/bin/celery" -A app.tasks.celery_app call app.tasks.invoice_batch.generate_recurring_invoices 2>/dev/null || true)
  [[ -n $task ]] && pass 'Scheduler task accepted' "$task" || fail 'Scheduler task accepted'
  sleep 8
  task_error=$(journalctl -u finreg-worker --since "$STARTED_AT" --no-pager 2>/dev/null | grep -F "$task" | grep -E 'raised unexpected|FAILURE' || true)
  [[ -z $task_error ]] && pass 'Scheduler task has no failure' || fail 'Scheduler task has no failure' "${task_error//$'\n'/; }"
  after=$(sql finreg "SELECT count(*) FROM documents WHERE recurring_template_id='$plan_id';" 2>/dev/null || echo -1)
  [[ $after -ge $before && $after -ge 1 ]] && pass 'Plan has generated a document' "before=$before after=$after" || fail 'Plan has generated a document' "before=$before after=$after"
  duplicates=$(sql finreg "SELECT count(*) FROM (SELECT recurring_run_date FROM documents WHERE recurring_template_id='$plan_id' GROUP BY recurring_run_date HAVING count(*)>1) x;" 2>/dev/null || echo query_failed)
  [[ $duplicates == 0 ]] && pass 'Recurring generation is idempotent' || fail 'Recurring generation is idempotent' "$duplicates"
  if [[ $EXPECTED_MODE == shadow ]]; then
    unsafe=$(sql finreg "SELECT count(*) FROM documents WHERE recurring_template_id='$plan_id' AND (document_status<>'draft' OR full_document_number IS NOT NULL);" 2>/dev/null || echo query_failed)
    [[ $unsafe == 0 ]] && pass 'Shadow documents remain unnumbered drafts' || fail 'Shadow documents remain unnumbered drafts' "$unsafe"
  fi
  if [[ $EXPECTED_MODE == pilot && $EXPECTED_AGT_CHANNEL == offline ]]; then
    offline_docs=$(sql finreg "SELECT count(*) FROM documents WHERE company_id='$company_id' AND document_status='finalized' AND agt_status='transmission_disabled';" 2>/dev/null || echo -1)
    [[ $offline_docs -ge 1 ]] && pass 'Offline fiscal document finalized without AGT transport' "count=$offline_docs" || fail 'Offline fiscal document finalized without AGT transport' "$offline_docs"
  fi
else
  warn 'Scheduler exercise skipped'
fi

printf '\n* Authoritative SAF-T boundary\n\n' >>"$REPORT"
saft=$(cd "$CELLEN_DIR" && set -a && source .env && set +a && export PYTHONPATH="$CELLEN_DIR" && "$CELLEN_DIR/.venv/bin/python" - <<'PY'
import asyncio
from datetime import date
from xml.etree import ElementTree
from app.services.finreg import HttpFinregAdapter
async def main():
    today = date.today()
    data = await HttpFinregAdapter().download(
        f"reports/saft-sales?date_from={today.year}-01-01&date_to={today.isoformat()}",
        actor_reference="release-acceptance",
    )
    print(f"{len(data)}|{ElementTree.fromstring(data).tag}")
asyncio.run(main())
PY
 2>/dev/null || true)
size=${saft%%|*}; root=${saft#*|}
[[ $size =~ ^[0-9]+$ && $size -gt 100 && -n $root ]] && pass 'SAF-T exports through Cellen into authoritative Finreg' "bytes=$size root=$root" || fail 'SAF-T exports through Cellen into authoritative Finreg' "${saft:-no XML}"

printf '\n* New service errors\n\n' >>"$REPORT"
for service in finreg-api finreg-worker finreg-beat cellen-api; do
  errors=$(journalctl -u "$service" --since "$STARTED_AT" --no-pager 2>/dev/null | grep -Ei 'ERROR|Traceback|raised unexpected' || true)
  [[ -z $errors ]] && pass "$service has no new errors" || fail "$service has no new errors" "${errors//$'\n'/; }"
done

printf '\n* Summary\n\n- Passed: %d\n- Failed: %d\n- Warnings: %d\n- Finished: %s\n' "$PASS" "$FAIL" "$WARN" "$(date --iso-8601=seconds)" | tee -a "$REPORT"
chown jorgehel:jorgehel "$REPORT"; chmod 0600 "$REPORT"
echo "Evidence report: $REPORT"
((FAIL == 0))
