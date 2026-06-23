# mq-rest-admin-dev-environment

Shared dockerized IBM MQ test environment for use across multiple
repositories. Provides container lifecycle scripts, seed data, and
a reusable GitHub Actions composite action for integration testing
against a real MQ queue manager.

## Table of Contents

- [Consuming repositories](#consuming-repositories)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Environment contract](#environment-contract)
- [Seed objects](#seed-objects)
- [Lifecycle scripts](#lifecycle-scripts)
- [CI integration](#ci-integration)
- [Local development](#local-development)
- [Reset workflow](#reset-workflow)
- [Repository structure](#repository-structure)
- [License](#license)

## Consuming repositories

- [pymqrest](https://github.com/mq-rest-admin-project/pymqrest) — Python
  wrapper for the MQ administrative REST API
- [mq-rest-admin](https://github.com/mq-rest-admin-project/mq-rest-admin) —
  Java port of pymqrest
- pymqpcf — Python wrapper for the MQ PCF API (planned)

## Prerequisites

- **Docker**: Docker Desktop or Docker Engine with Compose v2
- **curl**: For REST API health checks (pre-installed on macOS/Linux)

## Quick start

```bash
scripts/mq_start.sh    # Start QM1 + QM2, wait for REST API readiness
scripts/mq_seed.sh     # Run MQSC seed commands on both queue managers
scripts/mq_verify.sh   # Verify seed objects exist via REST API
scripts/mq_stop.sh     # Stop and remove containers
```

## Environment contract

Consuming repositories depend on these stable details:

| Property | Value |
| --- | --- |
| Queue manager 1 | QM1 |
| Queue manager 2 | QM2 |
| QM1 REST API | `https://localhost:9443/ibmmq/rest/v2` |
| QM2 REST API | `https://localhost:9444/ibmmq/rest/v2` |
| QM1 MQ listener | `localhost:1414` |
| QM2 MQ listener | `localhost:1415` |
| Admin user | `mqadmin` / `mqadmin` |
| Reader user | `mqreader` / `mqreader` |
| Docker image | `icr.io/ibm-messaging/mq:9.4.5.1-r1` |
| Docker network | `mq-dev-net` |

## Seed objects

Both queue managers receive a shared set of `DEV.*` objects. QM1 has
the full set; QM2 has a minimal subset plus the cross-QM counterparts.

### QM1 objects (`seed/base-qm1.mqsc`)

| Object | Type | Notes |
| --- | --- | --- |
| DEV.DEAD.LETTER | QLOCAL | Dead-letter queue (set on QMGR) |
| DEV.QLOCAL | QLOCAL | General-purpose local queue |
| DEV.XMITQ | QLOCAL (XMITQ) | Transmission queue |
| DEV.QREMOTE | QREMOTE | Routes to DEV.TARGET on QM1 |
| DEV.QALIAS | QALIAS | Alias for DEV.QLOCAL |
| DEV.QMODEL | QMODEL | Temporary-dynamic model queue |
| DEV.TOPIC | TOPIC | Topic string `dev/topic` |
| DEV.NAMELIST | NAMELIST | Contains DEV.QLOCAL |
| DEV.SVRCONN | SVRCONN | Server-connection channel |
| DEV.SDR | SDR | Sender channel |
| DEV.RCVR | RCVR | Receiver channel |
| DEV.LSTR | LISTENER | TCP listener on port 1415 |
| DEV.PROC | PROCESS | Process definition |

### QM2 objects (`seed/base-qm2.mqsc`)

| Object | Type | Notes |
| --- | --- | --- |
| DEV.DEAD.LETTER | QLOCAL | Dead-letter queue (set on QMGR) |
| DEV.QLOCAL | QLOCAL | General-purpose local queue |
| DEV.SVRCONN | SVRCONN | Server-connection channel |

### Cross-QM routing

Both queue managers define transmission queues, remote queue
definitions, and sender/receiver channel pairs for bidirectional
message routing. QM1 defines a `QM2` QM alias and QM2 defines a `QM1`
QM alias to enable gateway routing — this allows the REST API on one
queue manager to route MQSC commands to the other.

## Lifecycle scripts

| Script | Description |
| --- | --- |
| `scripts/mq_start.sh` | Start containers and wait for REST API readiness |
| `scripts/mq_seed.sh` | Run MQSC seed scripts on QM1 and QM2 |
| `scripts/mq_verify.sh` | Verify seed objects exist via REST API |
| `scripts/mq_reset.sh` | Stop containers, remove volumes, and restart cleanly |
| `scripts/mq_stop.sh` | Stop and remove containers (preserves volumes) |

### MQ version selection

`mq-versions.json` lists the supported MQ versions. Set `MQ_VERSION` to an
alias (e.g. `10.0`, `9.4.5`) for any lifecycle script; omit it to use the
manifest `default`. CI consumers call the reusable `mq-versions.yml`
workflow to build a matrix and pass `mq-version` to the `setup-mq` action;
track the rolling `vX.Y` tag so new versions are picked up automatically.

## CI integration

This repository provides a composite action at
`.github/actions/setup-mq/action.yml` for use in GitHub Actions
workflows.

### Usage

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup MQ
        id: mq
        uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/actions/setup-mq@main
        with:
          verify: 'true'  # default; set 'false' to skip verification

      # Use the outputs in subsequent steps
      # ${{ steps.mq.outputs.qm1-rest-url }}
      # ${{ steps.mq.outputs.qm2-rest-url }}
```

### Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `verify` | No | `'true'` | Run `mq_verify.sh` after seeding |

### Outputs

| Output | Value |
| --- | --- |
| `qm1-rest-url` | `https://localhost:9443/ibmmq/rest/v2` |
| `qm2-rest-url` | `https://localhost:9444/ibmmq/rest/v2` |

## Local development

Consuming repositories reference this repo as a sibling directory:

```text
~/dev/
  mq-rest-admin-dev-environment/     # this repo
  pymqrest/               # consuming repo
  mq-rest-admin/          # consuming repo
```

From a consuming repo, start the environment with:

```bash
../mq-rest-admin-dev-environment/scripts/mq_start.sh
../mq-rest-admin-dev-environment/scripts/mq_seed.sh
```

## Reset workflow

To tear down the environment completely (including Docker volumes)
and start fresh:

```bash
scripts/mq_reset.sh
scripts/mq_start.sh
scripts/mq_seed.sh
```

`mq_reset.sh` runs `docker compose down -v`, which removes all
container data. Use `mq_stop.sh` instead if you want to preserve
queue manager state across restarts.

## Repository structure

```text
.github/
  actions/
    setup-mq/
      action.yml           # Composite action for CI
config/
  docker-compose.yml       # Container definitions (QM1, QM2)
  mqwebuser.xml            # REST API user/role configuration
docs/
  plans/                   # Decision documents
  repository-standards.md
  vergil-tooling.md
scripts/
  git-hooks/               # Git hook scripts
  mq_start.sh              # Start containers + wait for readiness
  mq_wait_ready.sh         # Shared readiness gate (stability window)
  mq_seed.sh               # Run MQSC seed scripts
  mq_verify.sh             # Verify seed objects via REST API
  mq_reset.sh              # Full reset (stop + remove volumes)
  mq_stop.sh               # Stop and remove containers
seed/
  base-qm1.mqsc            # Shared seed objects for QM1
  base-qm2.mqsc            # Shared seed objects for QM2
```

## License

This project is licensed under the
[GNU General Public License v3.0](LICENSE).
