#!/usr/bin/env bash
# Enable the Finreg feature for Rainha Njinga.
#
# Root cause: migration 0031 copied each school's old `finance` switch into the
# new `finreg` selector; Rainha Njinga had finance disabled before that, so its
# features JSONB carries `"finreg": false`. That override makes
# finreg_is_active() false (app/services/payment_control.py), so
# GET /finance/internal-payments/mode answers "internal" and the app renders
# the "Registo interno sem valor fiscal" banner even though the connection is
# pilot with kill_switch=false.
#
# This script:
#   1. writes a timestamped backup of the school's features JSONB,
#   2. flips ONLY the `finreg` key to true (jsonb_set; every other key kept),
#   3. re-evaluates the exact gate the endpoint uses and prints the verdict.
#
# No service restart is needed; features are read from the DB per request.
#
# Run on the VPS:
#   sudo bash /tmp/cellen-enable-finreg-feature.sh
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

CELLEN_DIR=/var/www/cellen
SCHOOL_SLUG=rainha-njinga
DEPLOY_USER=${CELLEN_DEPLOY_USER:-jorgehel}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/home/$DEPLOY_USER/backups
BACKUP=$BACKUP_DIR/cellen-${SCHOOL_SLUG}-features-before-${STAMP}.json
OUT=/home/$DEPLOY_USER/cellen-enable-finreg-${STAMP}.out

install -d -m 0750 -o "$DEPLOY_USER" "$BACKUP_DIR"
exec > >(tee -a "$OUT") 2>&1

before=$(sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 -d cellen -c \
  "SELECT jsonb_pretty(features) FROM schools WHERE slug='$SCHOOL_SLUG'")
[[ -n $before ]] || { echo "School '$SCHOOL_SLUG' not found." >&2; exit 1; }

umask 077
printf '%s\n' "$before" > "$BACKUP"
chown "$DEPLOY_USER": "$BACKUP"
umask 022

echo "== features BEFORE (backup: $BACKUP) ======================================"
printf '%s\n' "$before"

echo
echo "== Flipping features.finreg -> true (all other keys preserved) ============"
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d cellen <<SQL
UPDATE schools
   SET features = jsonb_set(COALESCE(features, '{}'::jsonb), '{finreg}', 'true'::jsonb, true)
 WHERE slug = '$SCHOOL_SLUG';
SQL

echo
echo "== features AFTER ========================================================="
sudo -u postgres psql -X -A -t -v ON_ERROR_STOP=1 -d cellen -c \
  "SELECT jsonb_pretty(features) FROM schools WHERE slug='$SCHOOL_SLUG'"

echo
echo "== Exact gate from app.services.payment_control ==========================="
cd "$CELLEN_DIR"
PYTHONPATH="$CELLEN_DIR" "$CELLEN_DIR/.venv/bin/python" - "$SCHOOL_SLUG" <<'PY'
import asyncio
import sys

import app.main  # noqa: F401  (loads every model)
from sqlalchemy import select

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.finreg_integration import FinregSchoolConnection
from app.models.school import School
from app.services.payment_control import finreg_is_active

slug = sys.argv[1]


async def main():
    async with AsyncSessionLocal() as db:
        school = (await db.execute(
            select(School).where(School.slug == slug)
        )).scalar_one()
        conn = (await db.execute(
            select(FinregSchoolConnection).where(
                FinregSchoolConnection.school_id == school.id
            )
        )).scalar_one_or_none()
        print(f"FINREG_INTEGRATION_ENABLED = {settings.FINREG_INTEGRATION_ENABLED}")
        print(f"resolved_features.finreg   = {school.resolved_features.get('finreg')!r}")
        print(f"connection                 = {None if conn is None else (conn.mode, conn.kill_switch)}")
        active = await finreg_is_active(db, school.id)
        print(f"finreg_is_active           = {active}")
        print("RESULT: /finance/internal-payments/mode will return "
              + ('"finreg"' if active else '"internal" (STILL BLOCKED)'))

asyncio.run(main())
PY

echo
echo "Saved to $OUT"
echo "Next: reload the Cellen web app (hard refresh if needed) and repeat the smoke test:"
echo "  finance user -> Financeiro -> tap 'Abrir no FinReg'; parent -> invoices/statement."
