#!/usr/bin/env bash
# Read-only diagnosis: why does Cellen answer /finance/internal-payments/mode
# with "internal" (i.e. the "Registo interno sem valor fiscal" banner) when
# Rainha Njinga is active in FinReg?
#
# Prints, without exposing any secret:
#   - the FINREG_* lines of /var/www/cellen/.env (secrets/ids masked)
#   - what the running cellen-api workers actually see in their process env
#   - the cellen services' state and deployed revision
#   - for every school: features, resolved_features.finreg, connection
#     (mode/kill_switch) and the exact finreg_is_active() verdict
#
# Run on the VPS (read-only; no writes, no restarts):
#   sudo bash /tmp/cellen-diagnose-mode.sh
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

CELLEN_DIR=/var/www/cellen
CELLEN_ENV=$CELLEN_DIR/.env
DEPLOY_USER=${CELLEN_DEPLOY_USER:-jorgehel}
OUT=/home/$DEPLOY_USER/cellen-mode-$(date -u +%Y%m%dT%H%M%SZ).out

install -d -m 0750 -o "$DEPLOY_USER" "/home/$DEPLOY_USER"
exec > >(tee -a "$OUT") 2>&1

echo "== Cellen service ========================================================"
systemctl show -p ActiveState -p SubState -p ActiveEnterTimestamp cellen-api
git -c "safe.directory=$CELLEN_DIR" -C "$CELLEN_DIR" rev-parse HEAD
"$CELLEN_DIR/.venv/bin/pip" show finreg-kit 2>/dev/null | sed -n '1,2p' || echo "finreg-kit: not installed"

echo
echo "== /var/www/cellen/.env — FINREG_* (ids/secret values masked) ============"
while IFS= read -r line; do
  key=${line%%=*}
  case $key in
    FINREG_CLIENT_SECRET|FINREG_CLIENT_SECRET_FILE|FINREG_PASSWORD)
      echo "$key=<present, redacted>" ;;
    *)
      echo "$line" ;;
  esac
done < <(grep -E '^FINREG_[A-Z0-9_]+=' "$CELLEN_ENV" || true)

echo
echo "== What the running cellen-api processes actually see ===================="
mapfile -t PIDS < <(pgrep -f 'uvicorn app.main:app' || true)
[[ ${#PIDS[@]} -gt 0 ]] || echo "no uvicorn process found"
for pid in "${PIDS[@]}"; do
  val=$(tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^FINREG_INTEGRATION_ENABLED=' || true)
  echo "pid $pid: ${val:-FINREG_INTEGRATION_ENABLED not in process environment}"
done

echo
echo "== Schools (DB) =========================================================="
sudo -u postgres psql -X -A -F ' | ' -d cellen -c \
  "SELECT s.slug, s.segment, s.is_active, s.features::text
     FROM schools s ORDER BY s.slug"
echo
sudo -u postgres psql -X -A -F ' | ' -d cellen -c \
  "SELECT s.slug, fc.mode, fc.kill_switch
     FROM schools s LEFT JOIN finreg_school_connections fc ON fc.school_id = s.id
    ORDER BY s.slug"

echo
echo "== Staff logins per school (who signs in where) =========================="
sudo -u postgres psql -X -A -F ' | ' -d cellen -c \
  "SELECT s.slug, u.username, array_to_string(u.roles, ','), u.is_active
     FROM users u JOIN schools s ON s.id = u.school_id
    WHERE NOT ('parent' = ANY(u.roles)) AND NOT ('student' = ANY(u.roles))
    ORDER BY s.slug, u.username"

echo
echo "== The exact gate the endpoint uses (app.services.payment_control) ======="
cd "$CELLEN_DIR"
PYTHONPATH="$CELLEN_DIR" "$CELLEN_DIR/.venv/bin/python" - <<'PY'
import asyncio

# Importing the app loads every model (app/models/__init__.py is empty), so
# relationships used by School / FinregSchoolConnection resolve.
import app.main  # noqa: F401
from sqlalchemy import select

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.finreg_integration import FinregSchoolConnection
from app.models.school import School
from app.services.payment_control import finreg_is_active

print("settings.FINREG_INTEGRATION_ENABLED =", settings.FINREG_INTEGRATION_ENABLED)
print("settings.FINREG_BASE_URL            =", settings.FINREG_BASE_URL)
print("settings.FINREG_WEB_URL             =", settings.FINREG_WEB_URL)


async def main():
    async with AsyncSessionLocal() as db:
        schools = (await db.execute(select(School).order_by(School.slug))).scalars().all()
        for school in schools:
            print(f"- {school.slug} ({school.name}) segment={school.segment}")
            print(f"    features                 = {school.features}")
            print(f"    resolved_features.finreg = {school.resolved_features.get('finreg')!r}")
            conn = (await db.execute(
                select(FinregSchoolConnection).where(
                    FinregSchoolConnection.school_id == school.id
                )
            )).scalar_one_or_none()
            if conn is None:
                print("    connection               = NONE")
            else:
                print(f"    connection               = mode={conn.mode!r} kill_switch={conn.kill_switch!r}")
            print(f"    finreg_is_active         = {await finreg_is_active(db, school.id)}")

asyncio.run(main())
PY

echo
echo "== Done =================================================================="
echo "Saved to $OUT"
