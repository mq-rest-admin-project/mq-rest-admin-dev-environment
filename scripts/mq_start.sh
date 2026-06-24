#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml up -d

# Block until both queue managers serve requests reliably.  The
# readiness gate lives in mq_wait_ready.sh so seed/verify (and any
# standalone caller) inherit the same stability window.
scripts/mq_wait_ready.sh
