# Docker Compose

The Docker Compose configuration is located at `config/docker-compose.yml`
and defines two IBM MQ container services with REST API access.

## Services

### QM1

| Property | Value |
| --- | --- |
| Image | `icr.io/ibm-messaging/mq:9.4.5.1-r1` |
| Hostname | `qm1` |
| MQ listener port | `1414` (host: `1414`) |
| REST API port | `9443` (host: `9443`) |
| Queue manager name | `QM1` |

### QM2

| Property | Value |
| --- | --- |
| Image | `icr.io/ibm-messaging/mq:9.4.5.1-r1` |
| Hostname | `qm2` |
| MQ listener port | `1414` (host: `1415`) |
| REST API port | `9443` (host: `9444`) |
| Queue manager name | `QM2` |

## Environment variables

Both services accept the same environment variables for port
overrides:

| Variable | Default | Description |
| --- | --- | --- |
| `MQ_IMAGE` | `icr.io/ibm-messaging/mq:9.4.5.1-r1` | Container image |
| `QM1_MQ_PORT` | `1414` | Host port for QM1 MQ listener |
| `QM1_REST_PORT` | `9443` | Host port for QM1 REST API |
| `QM2_MQ_PORT` | `1415` | Host port for QM2 MQ listener |
| `QM2_REST_PORT` | `9444` | Host port for QM2 REST API |

## Volumes

Each queue manager has a dedicated named volume for persistent data:

- `qm1data` — mounted at `/var/mqm` in the QM1 container
- `qm2data` — mounted at `/var/mqm` in the QM2 container

The `mqwebuser.xml` configuration file is bind-mounted read-only
into both containers at the Liberty web server configuration path.

## Health checks

Both containers use the `dspmq` command as a health check:

```yaml
healthcheck:
  test: ["CMD", "dspmq", "-m", "QM1"]  # or QM2
  interval: 10s
  timeout: 5s
  retries: 12
```

The `mq_start.sh` script waits for both containers to report
healthy before returning.

## Network

Both services share the `mq-dev-net` Docker network, which allows
the containers to communicate using their hostnames (`qm1`, `qm2`).
This is required for the cross-QM sender/receiver channels.
