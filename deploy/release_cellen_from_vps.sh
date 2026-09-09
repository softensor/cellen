#!/usr/bin/env bash
# Deploy a merged Cellen master revision on the production VPS.
#
# Usage:
#   sudo bash deploy/release_cellen_from_vps.sh [expected-master-sha]
#
# Run this from /var/www/cellen after the pull request has merged and CI has
# passed. The optional SHA makes the release fail closed if origin/master does
# not resolve to the reviewed revision.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 2; }

CELLEN_DIR=${CELLEN_DIR:-/var/www/cellen}
DEPLOY_USER=${CELLEN_DEPLOY_USER:-jorgehel}
DB_NAME=${CELLEN_DB_NAME:-cellen}
BACKUP_DIR=${CELLEN_BACKUP_DIR:-/home/$DEPLOY_USER/backups}
SERVICE_NAME=${CELLEN_SERVICE_NAME:-cellen-api}
LOCAL_HEALTH_URL=${CELLEN_LOCAL_HEALTH_URL:-http://127.0.0.1:8001/health}
PUBLIC_HEALTH_URL=${CELLEN_PUBLIC_HEALTH_URL:-https://167.235.158.77.nip.io/health}
EXPECTED_SHA=${1:-}
STARTED_AT=$(date --iso-8601=seconds)
BACKUP_FILE=

release_failed() {
  local status=$?
  trap - ERR
  echo "Cellen deployment failed with status $status." >&2
  if [[ -n $BACKUP_FILE ]]; then
    echo "Pre-migration database backup: $BACKUP_FILE" >&2
  fi
  systemctl --no-pager --full status "$SERVICE_NAME" >&2 || true
  journalctl -u "$SERVICE_NAME" --since "$STARTED_AT" --no-pager >&2 || true
  exit "$status"
}
trap release_failed ERR

for command in git pg_dump curl systemctl runuser; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 2
  }
done

id "$DEPLOY_USER" >/dev/null 2>&1 || {
  echo "Deployment user does not exist: $DEPLOY_USER" >&2
  exit 2
}

for required in \
  "$CELLEN_DIR/.git" \
  "$CELLEN_DIR/.env" \
  "$CELLEN_DIR/requirements.txt" \
  "$CELLEN_DIR/alembic.ini" \
  "$CELLEN_DIR/.venv/bin/python" \
  "$CELLEN_DIR/.venv/bin/pip" \
  "$CELLEN_DIR/.venv/bin/alembic"; do
  [[ -e $required ]] || {
    echo "Missing required path: $required" >&2
    exit 2
  }
done

if [[ -n $EXPECTED_SHA && ! $EXPECTED_SHA =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  echo "Expected revision must be a 7-40 character Git SHA." >&2
  exit 2
fi

if [[ -n $(runuser -u "$DEPLOY_USER" -- \
    git -C "$CELLEN_DIR" status --porcelain --untracked-files=no) ]]; then
  echo "Tracked changes exist in $CELLEN_DIR; refusing to overwrite them." >&2
  runuser -u "$DEPLOY_USER" -- \
    git -C "$CELLEN_DIR" status --short --untracked-files=no >&2
  exit 2
fi

echo "==> Updating Cellen from origin/master"
runuser -u "$DEPLOY_USER" -- git -C "$CELLEN_DIR" fetch origin master
runuser -u "$DEPLOY_USER" -- git -C "$CELLEN_DIR" switch master
runuser -u "$DEPLOY_USER" -- \
  git -C "$CELLEN_DIR" merge --ff-only origin/master

DEPLOYED_SHA=$(runuser -u "$DEPLOY_USER" -- git -C "$CELLEN_DIR" rev-parse HEAD)
REMOTE_SHA=$(runuser -u "$DEPLOY_USER" -- git -C "$CELLEN_DIR" rev-parse origin/master)
[[ $DEPLOYED_SHA == "$REMOTE_SHA" ]] || {
  echo "Local master does not match origin/master." >&2
  exit 2
}

if [[ -n $EXPECTED_SHA ]]; then
  RESOLVED_EXPECTED_SHA=$(runuser -u "$DEPLOY_USER" -- \
    git -C "$CELLEN_DIR" rev-parse --verify "$EXPECTED_SHA^{commit}")
  [[ $DEPLOYED_SHA == "$RESOLVED_EXPECTED_SHA" ]] || {
    echo "Refusing to deploy unexpected revision." >&2
    echo "Expected: $RESOLVED_EXPECTED_SHA" >&2
    echo "Resolved origin/master: $DEPLOYED_SHA" >&2
    exit 2
  }
fi

echo "==> Backing up PostgreSQL database $DB_NAME"
install -d -m 0750 "$BACKUP_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_FILE="$BACKUP_DIR/cellen-before-$DEPLOYED_SHA-$STAMP.dump"
runuser -u postgres -- pg_dump -Fc -d "$DB_NAME" > "$BACKUP_FILE"
chmod 0600 "$BACKUP_FILE"
[[ -s $BACKUP_FILE ]] || {
  echo "Database backup is empty: $BACKUP_FILE" >&2
  exit 2
}

echo "==> Installing pinned Python dependencies"
"$CELLEN_DIR/.venv/bin/pip" install \
  --disable-pip-version-check \
  --prefer-binary \
  --requirement "$CELLEN_DIR/requirements.txt"

echo "==> Applying database migrations"
set -a
# shellcheck disable=SC1091
source "$CELLEN_DIR/.env"
set +a
export PYTHONPATH="$CELLEN_DIR"
(
  cd "$CELLEN_DIR"
  "$CELLEN_DIR/.venv/bin/alembic" upgrade head
  "$CELLEN_DIR/.venv/bin/alembic" current | grep -F '(head)' >/dev/null
)

echo "==> Restarting $SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "==> Waiting for Cellen health"
healthy=0
for ((attempt = 1; attempt <= 30; attempt++)); do
  if systemctl is-active --quiet "$SERVICE_NAME" \
      && curl --fail --silent --show-error "$LOCAL_HEALTH_URL" >/dev/null; then
    healthy=1
    break
  fi
  sleep 2
done
[[ $healthy -eq 1 ]] || {
  echo "Cellen did not become healthy within 60 seconds." >&2
  exit 1
}

curl --fail --silent --show-error "$PUBLIC_HEALTH_URL" >/dev/null

echo "Cellen deployment completed successfully."
echo "Revision: $DEPLOYED_SHA"
echo "Database backup: $BACKUP_FILE"
echo "Local health: $LOCAL_HEALTH_URL"
echo "Public health: $PUBLIC_HEALTH_URL"
