# CI Integration

This repository provides a composite action at
`.github/actions/setup-mq/action.yml` for use in GitHub Actions
workflows. The action starts the MQ containers, seeds them with
test objects, and optionally verifies the environment.

## Usage

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
          verify: 'true'

      # Use the outputs in subsequent steps
      # ${{ steps.mq.outputs.qm1-rest-url }}
      # ${{ steps.mq.outputs.qm2-rest-url }}
```

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `project-name` | No | `mq-dev` | COMPOSE_PROJECT_NAME for container isolation |
| `qm1-rest-port` | No | `9443` | Host port for QM1 REST API |
| `qm2-rest-port` | No | `9444` | Host port for QM2 REST API |
| `qm1-mq-port` | No | `1414` | Host port for QM1 MQ listener |
| `qm2-mq-port` | No | `1415` | Host port for QM2 MQ listener |
| `verify` | No | `true` | Run `mq_verify.sh` after seeding |

## Outputs

| Output | Value |
| --- | --- |
| `qm1-rest-url` | `https://localhost:<qm1-rest-port>/ibmmq/rest/v2` |
| `qm2-rest-url` | `https://localhost:<qm2-rest-port>/ibmmq/rest/v2` |

## What the action does

1. **Start containers** — runs `scripts/mq_start.sh` with the
   configured ports and project name
2. **Seed objects** — runs `scripts/mq_seed.sh` to create all
   `DEV.*` objects on both queue managers
3. **Verify** (optional) — runs `scripts/mq_verify.sh` to confirm
   all expected objects exist via the REST API

## Port customization

Use the port inputs to avoid conflicts when running multiple MQ
environments in the same workflow:

```yaml
- name: Setup MQ
  id: mq
  uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/actions/setup-mq@main
  with:
    project-name: 'my-tests'
    qm1-mq-port: '11414'
    qm2-mq-port: '11415'
    qm1-rest-port: '19443'
    qm2-rest-port: '19444'
```

## CI matrix example

When using a build matrix (e.g., multiple Python versions), each matrix
entry needs unique ports. Apply an offset based on the matrix index:

```yaml
strategy:
  matrix:
    python-version: ['3.12', '3.13']

steps:
  - name: Calculate port offset
    id: ports
    run: |
      # Find this version's index in the matrix
      versions=("3.12" "3.13")
      for i in "${!versions[@]}"; do
        if [[ "${versions[$i]}" == "${{ matrix.python-version }}" ]]; then
          idx=$i; break
        fi
      done
      echo "qm1-mq-port=$((11414 + idx * 2))" >> "$GITHUB_OUTPUT"
      echo "qm2-mq-port=$((11415 + idx * 2))" >> "$GITHUB_OUTPUT"
      echo "qm1-rest-port=$((19443 + idx * 2))" >> "$GITHUB_OUTPUT"
      echo "qm2-rest-port=$((19444 + idx * 2))" >> "$GITHUB_OUTPUT"

  - name: Setup MQ
    id: mq
    uses: ./.mq-dev-env/.github/actions/setup-mq
    with:
      project-name: 'mqrest-python-${{ matrix.python-version }}'
      qm1-mq-port: ${{ steps.ports.outputs.qm1-mq-port }}
      qm2-mq-port: ${{ steps.ports.outputs.qm2-mq-port }}
      qm1-rest-port: ${{ steps.ports.outputs.qm1-rest-port }}
      qm2-rest-port: ${{ steps.ports.outputs.qm2-rest-port }}
```

See [Port Allocation](reference/port-allocation.md) for the full
per-language port scheme and offset formula.
