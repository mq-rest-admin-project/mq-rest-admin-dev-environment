#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

# Don't seed until both queue managers serve requests — seeding (and
# the verify/tests that follow) must not race container startup.
scripts/mq_wait_ready.sh

# runmqsc returns the count of failed commands as its exit code.
# START CHANNEL fails harmlessly when the channel is already running,
# so tolerate non-zero exits here.  Output is still printed for
# inspection.
docker compose -f config/docker-compose.yml exec -T qm1 runmqsc QM1 < seed/base-qm1.mqsc || true
docker compose -f config/docker-compose.yml exec -T qm2 runmqsc QM2 < seed/base-qm2.mqsc || true
