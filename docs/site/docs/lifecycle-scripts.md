# Lifecycle Scripts

All lifecycle scripts are located in the `scripts/` directory. They
manage the Docker container lifecycle for the MQ development
environment.

## Script reference

### mq_start.sh

Starts the QM1 and QM2 containers and waits for both REST APIs to
become ready.

```bash
scripts/mq_start.sh
```

The script:

1. Runs `docker compose up -d` using `config/docker-compose.yml`
2. Delegates to `mq_wait_ready.sh` to block until both REST APIs serve
   requests reliably

### mq_wait_ready.sh

Readiness gate shared by `mq_start.sh`, `mq_seed.sh`, and `mq_verify.sh`.
Polls both queue managers' administrative REST endpoints and only
returns once **every** queue manager has answered healthily for several
consecutive rounds (a stability window).

```bash
scripts/mq_wait_ready.sh
```

A single successful probe is not enough: during startup the MQ web
server answers one request while the queue manager is still
stabilising, then resets connections moments later (seen downstream as
`SSL_ERROR_SYSCALL` / `Connection reset by peer`). Requiring a stability
window keeps seed/verify and the consuming repos' tests from racing
startup. On timeout the script exits non-zero with an explicit
"queue manager not ready after N seconds" message so a genuine startup
failure is distinguishable from a slow start.

Tunable via [environment variables](reference/environment-variables.md#readiness-gate-variables)
(`MQ_READY_TIMEOUT_SECONDS`, `MQ_READY_INTERVAL_SECONDS`,
`MQ_READY_CONSECUTIVE`).

### mq_seed.sh

Runs the MQSC seed scripts against both queue managers to create
all development objects.

```bash
scripts/mq_seed.sh
```

The script:

1. Blocks on `mq_wait_ready.sh` so seeding never races startup
2. Copies `seed/base-qm1.mqsc` into the QM1 container
3. Runs `runmqsc QM1` with the seed file
4. Copies `seed/base-qm2.mqsc` into the QM2 container
5. Runs `runmqsc QM2` with the seed file

### mq_verify.sh

Verifies that all expected seed objects exist by querying the REST
API on both queue managers.

```bash
scripts/mq_verify.sh
```

The script first blocks on `mq_wait_ready.sh`, then checks each object
type (queues, channels, topics, etc.) and reports success or failure
for each.

### mq_reset.sh

Stops containers, removes Docker volumes, and restarts the
environment cleanly.

```bash
scripts/mq_reset.sh
```

The script runs `docker compose down -v` to remove all container
data, then calls `mq_start.sh` and `mq_seed.sh` to rebuild the
environment from scratch.

!!! warning
    This removes all queue manager state including any messages
    in queues. Use `mq_stop.sh` if you want to preserve state.

### mq_stop.sh

Stops and removes the containers but preserves the named Docker
volumes.

```bash
scripts/mq_stop.sh
```

Queue manager state is retained in the `qm1data` and `qm2data`
volumes and will be available on the next `mq_start.sh`.

## Typical workflows

### First-time setup

```bash
scripts/mq_start.sh
scripts/mq_seed.sh
scripts/mq_verify.sh
```

### Daily restart

```bash
scripts/mq_start.sh    # Volumes preserved, no re-seed needed
```

### Clean reset

```bash
scripts/mq_reset.sh    # Removes volumes and re-seeds
```
