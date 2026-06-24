#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml down -v
