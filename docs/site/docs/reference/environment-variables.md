# Environment Variables

Complete reference for all environment variables used by the MQ dev
environment and consuming repositories.

## Docker Compose variables

These variables control the Docker Compose configuration. Set them
before running `mq_start.sh` to override defaults.

| Variable | Default | Description |
| --- | --- | --- |
| `MQ_IMAGE` | `icr.io/ibm-messaging/mq:9.4.5.1-r1` | IBM MQ container image |
| `QM1_MQ_PORT` | `1414` | Host port for QM1 MQ listener |
| `QM1_REST_PORT` | `9443` | Host port for QM1 REST API |
| `QM2_MQ_PORT` | `1415` | Host port for QM2 MQ listener |
| `QM2_REST_PORT` | `9444` | Host port for QM2 REST API |

```bash
QM1_REST_PORT=19443 QM2_REST_PORT=19444 scripts/mq_start.sh
```

## Consumer variables

Set these in consuming repositories (language libraries) to configure
how they reference the dev environment.

| Variable | Default | Description |
| --- | --- | --- |
| `COMPOSE_PROJECT_NAME` | `mq-dev` | Docker Compose project name for resource isolation. Each language library sets this in its wrapper scripts (e.g., `mqrest-python`). |
| `MQ_DEV_ENV_PATH` | `../mq-rest-admin-dev-environment` | Path to this repository. Override when it is not a sibling directory. |

## Script variables

Used by the lifecycle scripts and seed/verify operations.

| Variable | Default | Description |
| --- | --- | --- |
| `MQ_ADMIN_USER` | `mqadmin` | Admin username for REST API authentication |
| `MQ_ADMIN_PASSWORD` | `mqadmin` | Admin password for REST API authentication |

## Test gate variables

Control integration test execution in consuming repositories.

| Variable | Default | Description |
| --- | --- | --- |
| `MQ_REST_ADMIN_RUN_INTEGRATION` | *(unset)* | Set to `true` to enable integration tests. When unset, integration tests are skipped. |
| `MQ_SKIP_LIFECYCLE` | *(unset)* | Set to `true` to skip MQ lifecycle management in test fixtures. Used in CI where the composite action handles startup/teardown. |
