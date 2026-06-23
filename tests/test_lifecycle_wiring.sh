#!/usr/bin/env bash
# Verifies a lifecycle script resolves the per-version Compose project
# name and passes it to docker. Stubs `docker` on PATH to capture env.
set -uo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake docker: record COMPOSE_PROJECT_NAME, then succeed.
mkdir -p "$tmp/bin"
{
  echo '#!/usr/bin/env bash'
  echo 'printf "%s" "${COMPOSE_PROJECT_NAME:-UNSET}" > "$CAPTURE_FILE"'
  echo 'exit 0'
} > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"

export CAPTURE_FILE="$tmp/project"
PATH="$tmp/bin:$PATH" MQ_VERSION=10.0 bash scripts/mq_stop.sh >/dev/null 2>&1

got="$(cat "$tmp/project" 2>/dev/null || echo MISSING)"
if [ "$got" = "mq-dev-10_0" ]; then
  echo "ok   - mq_stop.sh resolves per-version project name"; echo "PASS"
else
  echo "FAIL - expected mq-dev-10_0 got [$got]"; exit 1
fi
