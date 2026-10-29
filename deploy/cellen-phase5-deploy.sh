#!/usr/bin/env bash
# Phase 5 — Cellen/FinReg big-bang cutover window (Cellen-only).
#
# Releases merged PR #40 on the VPS, stages the pinned finreg-kit, applies the
# additive FinReg scope grant + manifest fingerprint refresh, restarts ONLY
# cellen-api, and runs the acceptance suite.
#
# FinReg code, migrations and services are never touched: the script fails
# closed if FinReg's certified revision is not on disk, if the revision changes
# during the window, or if any FinReg service uptime changes.
#
# Usage (on the VPS):
#   sudo bash ~/cellen-phase5-deploy.sh
#
# One-off window script on purpose: it is not committed, so it cannot change
# the released tree or trigger another CI cycle. Delete it after the window.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo: sudo bash $0" >&2; exit 2; }

CELLEN_SHA=0eb8b976aa1230b01846731ebad0bf706ba46eb6
FINREG_SHA_EXPECTED=${EXPECTED_FINREG_SHA:-4977a0b}

DEPLOY_USER=${CELLEN_DEPLOY_USER:-jorgehel}
CELLEN_DIR=${CELLEN_DIR:-/var/www/cellen}
FINREG_DIR=${FINREG_DIR:-/var/www/finreg}
BACKUP_DIR=/home/$DEPLOY_USER/backups
FINREG_HEALTH_URL=${FINREG_HEALTH_URL:-http://127.0.0.1:8003/health}
CELLEN_HEALTH_URL=${CELLEN_HEALTH_URL:-http://127.0.0.1:8001/health}

STARTED_AT=$(date --iso-8601=seconds)
LOG=$BACKUP_DIR/cellen-phase5-$(date -u +%Y%m%dT%H%M%SZ).log

install -d -m 0750 -o "$DEPLOY_USER" "$BACKUP_DIR"
exec > >(tee -a "$LOG") 2>&1

fail() { echo "PHASE 5 FAILED: $*" >&2; exit 1; }

on_exit() {
  local status=$?
  chmod 0644 "$LOG" 2>/dev/null || true
  if ((status != 0)); then
    echo "PHASE 5 FAILED (status $status). Full log: $LOG" >&2
    systemctl --no-pager --full status cellen-api >&2 || true
    journalctl -u cellen-api --since "$STARTED_AT" --no-pager | tail -n 80 >&2 || true
  fi
}
trap on_exit EXIT

# git on checkouts owned by another user needs the safe.directory override
# when this script runs as root.
git_sha() {
  git -c "safe.directory=$1" -C "$1" rev-parse HEAD
}

echo "== Preflight ============================================================="
for required in "$CELLEN_DIR/.git" "$CELLEN_DIR/.env" "$FINREG_DIR/.git"; do
  [[ -e $required ]] || fail "missing required path: $required"
done

FINREG_SHA_BEFORE=$(git_sha "$FINREG_DIR")
FINREG_UPTIME_BEFORE=$(systemctl show -p ActiveEnterTimestamp finreg-api finreg-worker finreg-beat)
echo "FinReg revision: $FINREG_SHA_BEFORE (expect ${FINREG_SHA_EXPECTED}...)"
echo "$FINREG_UPTIME_BEFORE"
[[ $FINREG_SHA_BEFORE == "$FINREG_SHA_EXPECTED"* ]] \
  || fail "FinReg is not at the certified revision ${FINREG_SHA_EXPECTED}... (override with EXPECTED_FINREG_SHA=<sha> only after investigating)"
systemctl is-active --quiet finreg-api finreg-worker finreg-beat \
  || fail "a FinReg service is not active"
curl -fsS -o /dev/null -w 'FinReg health: %{http_code}\n' "$FINREG_HEALTH_URL" \
  || fail "FinReg health check failed"

echo
echo "== FinReg database backup ================================================"
FINREG_BACKUP=$BACKUP_DIR/finreg-before-$CELLEN_SHA-$(date -u +%Y%m%dT%H%M%SZ).dump
runuser -u postgres -- pg_dump -Fc -d finreg > "$FINREG_BACKUP" \
  || fail "FinReg database backup failed"
chmod 0600 "$FINREG_BACKUP"
chown "$DEPLOY_USER": "$FINREG_BACKUP"
[[ -s $FINREG_BACKUP ]] || fail "FinReg backup is empty: $FINREG_BACKUP"
echo "FinReg backup: $FINREG_BACKUP"

echo
echo "== Cellen release: $CELLEN_SHA ==========================================="
cd "$CELLEN_DIR"
bash "$CELLEN_DIR/deploy/release_cellen_from_vps.sh" "$CELLEN_SHA"

echo
echo "== Cellen-only FinReg cutover (scope grant, fingerprints, acceptance) ===="
"$CELLEN_DIR/deploy/deploy_finreg_school_finance.sh" --cellen-only

echo
echo "== Postflight ============================================================"
[[ $(git_sha "$FINREG_DIR") == "$FINREG_SHA_BEFORE" ]] \
  || fail "FinReg checkout changed during the window"
[[ $(systemctl show -p ActiveEnterTimestamp finreg-api finreg-worker finreg-beat) == "$FINREG_UPTIME_BEFORE" ]] \
  || fail "a FinReg service was restarted during the window"
[[ $(git_sha "$CELLEN_DIR") == "$CELLEN_SHA" ]] \
  || fail "unexpected Cellen revision on disk"
systemctl is-active --quiet finreg-api finreg-worker finreg-beat cellen-api \
  || fail "a service is not active after the window"
curl -fsS -o /dev/null -w 'FinReg health: %{http_code}\n' "$FINREG_HEALTH_URL"
curl -fsS -o /dev/null -w 'Cellen health: %{http_code}\n' "$CELLEN_HEALTH_URL"

LATEST_CELLEN_BACKUP=$(ls -t "$BACKUP_DIR"/cellen-before-*.dump 2>/dev/null | head -1 || true)
echo "Cellen backup: ${LATEST_CELLEN_BACKUP:-see release output above}"
echo "FinReg backup: $FINREG_BACKUP"
echo "Log: $LOG"
echo "PHASE 5 COMPLETE — Cellen $CELLEN_SHA deployed; FinReg untouched."
