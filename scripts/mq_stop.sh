#!/usr/bin/env bash
set -euo pipefail

# Resolve the selected MQ version so COMPOSE_PROJECT_NAME targets the
# right per-version environment.
# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml down
