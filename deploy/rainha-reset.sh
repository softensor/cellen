#!/usr/bin/env bash
# Wipe Rainha Njinga's people and money in Cellen and FinReg, then leave both
# services healthy. Destructive: run with sudo after taking the backups it
# makes itself. The resets are transactional; a failure rolls back.
#
# Prerequisites (copied to /tmp by the hand-off commands):
#   /tmp/reset_rainha_cellen.py
#   /tmp/reset_rainha_finreg.py
set -euo pipefail

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/home/jorgehel/backups
CELLEN_VENV=/var/www/cellen/.venv/bin/python
FINREG_VENV=/var/www/finreg/.venv/bin/python
FINREG_COMPANY=e76b47c8-9221-4974-9eb5-cdf5044faa54
FINREG_NIF=5000413178
UNITS="finreg-api finreg-worker finreg-beat cellen-api"
STOPPED=0

start_services() {
  if [ "$STOPPED" -eq 1 ]; then
    echo
    echo "==> Starting services"
    for unit in $UNITS; do
      if systemctl list-unit-files "$unit.service" --no-legend | grep -q .; then
        systemctl start "$unit" || true
        echo "start requested: $unit"
      fi
    done
    STOPPED=0
  fi
}
trap start_services EXIT

echo "==> Preflight"
for path in \
  /var/www/cellen/app/models/__init__.py \
  /var/www/finreg/backend/app/models/__init__.py \
  "$CELLEN_VENV" \
  "$FINREG_VENV" \
  /tmp/reset_rainha_cellen.py \
  /tmp/reset_rainha_finreg.py; do
  if [ ! -r "$path" ]; then
    echo "cannot read: $path" >&2
    exit 2
  fi
done
chmod 644 /tmp/reset_rainha_cellen.py /tmp/reset_rainha_finreg.py
echo "preflight ok"

echo
echo "==> Deployed source readable by the reset user (postgres)"
restricted=$(runuser -u postgres -- \
  find /var/www/cellen/app /var/www/finreg/backend/app \
  -type f ! -readable -print 2>/dev/null | head -n 20 || true)
if [ -n "$restricted" ]; then
  echo "postgres could not read these files; granting o+rX:"
  printf '%s\n' "$restricted"
fi
chmod -R o+rX /var/www/cellen/app /var/www/finreg/backend/app
left=$(runuser -u postgres -- \
  find /var/www/cellen/app /var/www/finreg/backend/app \
  -type f ! -readable -print 2>/dev/null | wc -l || true)
if [ "$left" -ne 0 ]; then
  echo "$left source file(s) are still unreadable by postgres" >&2
  exit 2
fi
runuser -u postgres -- env PYTHONPATH=/var/www/cellen "$CELLEN_VENV" -c '
import importlib, pkgutil
import app.models
for module in pkgutil.iter_modules(app.models.__path__):
    importlib.import_module("app.models." + module.name)
print("cellen model imports ok")
'
runuser -u postgres -- env PYTHONPATH=/var/www/finreg/backend "$FINREG_VENV" -c '
import app.services.go_live_archive
print("finreg imports ok")
'

echo
echo "==> Backups ($STAMP)"
mkdir -p "$BACKUP_DIR"
runuser -u postgres -- pg_dump -Fc cellen > "$BACKUP_DIR/cellen-before-rainha-reset-$STAMP.dump"
runuser -u postgres -- pg_dump -Fc finreg > "$BACKUP_DIR/finreg-before-rainha-reset-$STAMP.dump"
ls -lh "$BACKUP_DIR/cellen-before-rainha-reset-$STAMP.dump" \
       "$BACKUP_DIR/finreg-before-rainha-reset-$STAMP.dump"
for dump in cellen finreg; do
  size=$(stat -c %s "$BACKUP_DIR/$dump-before-rainha-reset-$STAMP.dump")
  if [ "$size" -lt 100000 ]; then
    echo "backup too small ($dump: $size bytes); stopping" >&2
    exit 2
  fi
done

echo
echo "==> Cellen reset (dry run)"
runuser -u postgres -- env PYTHONPATH=/var/www/cellen \
  "$CELLEN_VENV" /tmp/reset_rainha_cellen.py \
  --dsn postgresql+asyncpg:///cellen

echo
echo "==> FinReg reset (dry run)"
runuser -u postgres -- env PYTHONPATH=/var/www/finreg/backend \
  "$FINREG_VENV" /tmp/reset_rainha_finreg.py \
  --company-id "$FINREG_COMPANY" \
  --dsn postgresql+asyncpg:///finreg

echo
echo "Review the two dry runs above. This deletes every non-zero row listed."
read -r -p "Type RESET to continue: " CONFIRM
if [ "$CONFIRM" != "RESET" ]; then
  echo "Aborted; nothing was changed."
  exit 2
fi

echo
echo "==> Stopping services"
STOPPED=1
for unit in $UNITS; do
  if systemctl list-unit-files "$unit.service" --no-legend | grep -q .; then
    systemctl stop "$unit"
    echo "stopped $unit"
  fi
done

echo
echo "==> Cellen reset (apply)"
runuser -u postgres -- env PYTHONPATH=/var/www/cellen \
  "$CELLEN_VENV" /tmp/reset_rainha_cellen.py \
  --dsn postgresql+asyncpg:///cellen \
  --apply --confirm rainha-njinga

echo
echo "==> FinReg reset (apply)"
runuser -u postgres -- env PYTHONPATH=/var/www/finreg/backend \
  "$FINREG_VENV" /tmp/reset_rainha_finreg.py \
  --company-id "$FINREG_COMPANY" \
  --dsn postgresql+asyncpg:///finreg \
  --apply --confirm "$FINREG_NIF"

start_services

echo
echo "==> Waiting for health"
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8001/health >/dev/null 2>&1 &&
     curl -fsS http://127.0.0.1:8003/health >/dev/null 2>&1; then
    curl -fsS http://127.0.0.1:8001/health; echo
    curl -fsS http://127.0.0.1:8003/health; echo
    echo "Both APIs are healthy after the reset."
    echo "Backups: $BACKUP_DIR/*-before-rainha-reset-$STAMP.dump"
    echo "Next: run the family seed from the Mac."
    exit 0
  fi
  sleep 1
done
echo "APIs did not both answer within 30s; check systemctl status." >&2
exit 1
