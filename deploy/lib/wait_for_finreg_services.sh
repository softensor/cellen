#!/usr/bin/env bash

# Wait until systemd and both HTTP applications agree that the integrated
# finance stack is ready. Callers retain their ERR trap and rollback policy.
wait_for_finreg_services() {
  local attempts=${1:-30}
  local delay=${2:-2}
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if systemctl is-active --quiet finreg-api finreg-worker finreg-beat cellen-api \
      && curl --fail --silent --show-error http://127.0.0.1:8003/ready >/dev/null 2>&1 \
      && curl --fail --silent --show-error http://127.0.0.1:8001/health >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done

  echo "Integrated finance services did not become ready within $((attempts * delay)) seconds." >&2
  systemctl --no-pager --full status finreg-api finreg-worker finreg-beat cellen-api >&2 || true
  return 1
}
