#!/usr/bin/env bash
set -Eeuo pipefail

SINCE=${1:-5 minutes ago}

cd /var/www/cellen

printf 'Cellen revision: '
git rev-parse HEAD

printf 'Pinned Finreg revision: '
tr -d '\n' < .github/finreg-packages-ref
printf '\n'

printf 'Cellen API state: '
systemctl is-active cellen-api

curl --fail --silent --show-error http://127.0.0.1:8001/health
printf '\n'

sudo journalctl \
  -u cellen-api \
  --since "$SINCE" \
  --no-pager \
  -o cat |
  grep -E \
    'embedded-session|workspace-launch|delegated|Finreg|401|403|409|500' || true

curl --fail --silent --show-error --head \
  https://softensor.github.io/cellen/ |
  grep -Ei 'HTTP/|last-modified|etag|date' || true

cd /var/www/finreg

printf 'Finreg revision: '
git rev-parse HEAD

printf 'Finreg API state: '
systemctl is-active finreg-api

curl --fail --silent --show-error http://127.0.0.1:8003/ready
printf '\n'

curl --fail --silent --show-error \
  https://finreg.167.235.158.77.nip.io/finreg-release.json
printf '\n'

sudo journalctl \
  -u finreg-api \
  --since "$SINCE" \
  --no-pager \
  -o cat |
  grep -E \
    'workspace-launch|delegated/exchange|auth/me|auth/refresh|401|403|409|500' || true
