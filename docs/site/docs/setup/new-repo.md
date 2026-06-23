# New Repository Onboarding

How to add a new language library to the mq-rest-admin project family
with full MQ dev environment integration.

## 1. Create wrapper scripts

Each consuming repo delegates MQ lifecycle operations to this repository
through thin wrapper scripts in `scripts/dev/`. Create one for each
lifecycle operation: `mq_start.sh`, `mq_stop.sh`, `mq_seed.sh`,
`mq_verify.sh`, `mq_reset.sh`.

Every wrapper follows the same pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
mq_dev_env="${MQ_DEV_ENV_PATH:-${repo_root}/../mq-rest-admin-dev-environment}"

if [ ! -d "$mq_dev_env" ]; then
  echo "mq-rest-admin-dev-environment not found at: $mq_dev_env" >&2
  echo "Clone it as a sibling directory or set MQ_DEV_ENV_PATH." >&2
  exit 1
fi

export COMPOSE_PROJECT_NAME=mqrest-<language>

cd "$mq_dev_env"
exec scripts/mq_start.sh
```

Replace `mq_start.sh` on the last line with the appropriate script name
for each wrapper (`mq_stop.sh`, `mq_seed.sh`, etc.).

## 2. Choose a `COMPOSE_PROJECT_NAME`

Each language library uses a unique `COMPOSE_PROJECT_NAME` to isolate
its Docker Compose resources. The naming convention is:

```text
mqrest-<language>
```

Existing names:

| Language | COMPOSE_PROJECT_NAME |
| --- | --- |
| Python | `mqrest-python` |
| Java | `mqrest-java` |
| Go | `mqrest-go` |
| Ruby | `mqrest-ruby` |
| Rust | `mqrest-rust` |

## 3. Allocate ports

Each language is assigned a dedicated block of ports to avoid conflicts
when environments run concurrently. See the
[Port Allocation](../reference/port-allocation.md) reference for the
full scheme and instructions on claiming the next available block.

## 4. Set up CI

Add the composite action to your GitHub Actions workflow. The action
handles starting, seeding, and verifying the MQ environment:

```yaml
- name: Checkout MQ dev environment
  uses: actions/checkout@v4
  with:
    repository: mq-rest-admin-project/mq-rest-admin-dev-environment
    ref: main
    path: .mq-dev-env

- name: Setup MQ
  id: mq
  uses: ./.mq-dev-env/.github/actions/setup-mq
  with:
    project-name: 'mqrest-<language>'
    qm1-rest-port: '<allocated-rest-port>'
    qm2-rest-port: '<allocated-rest-port + 1>'
    qm1-mq-port: '<allocated-mq-port>'
    qm2-mq-port: '<allocated-mq-port + 1>'
```

Use the ports from your allocated block. For matrix builds, apply the
CI offset formula described in
[Port Allocation — CI port isolation](../reference/port-allocation.md#ci-port-isolation).

See [CI Integration](../ci-integration.md) for complete input/output
reference.

## 5. Implement the integration test gate

Integration tests should only run when the MQ environment is available.
Use an environment variable to gate execution:

```text
MQ_REST_ADMIN_RUN_INTEGRATION=true
```

In your test suite, skip integration tests unless this variable is set.
Your CI workflow should set it:

```yaml
env:
  MQ_REST_ADMIN_RUN_INTEGRATION: 'true'
```

Locally, developers opt in by exporting it before running tests.

## 6. Add lifecycle fixture for CI

In CI, the composite action handles startup and teardown. Your test
suite should skip its own lifecycle management when running under CI.
Use the `MQ_SKIP_LIFECYCLE` variable:

```text
MQ_SKIP_LIFECYCLE=true
```

When set, test fixtures should not call `mq_start.sh` or `mq_stop.sh`
— the action has already done this. Locally (when the variable is
unset), fixtures manage the full lifecycle.

## Checklist

- [ ] Created `scripts/dev/mq_*.sh` wrapper scripts
- [ ] Chose a unique `COMPOSE_PROJECT_NAME` (`mqrest-<language>`)
- [ ] Allocated ports from the port scheme
- [ ] Added the `setup-mq` composite action to CI workflow
- [ ] Set `MQ_REST_ADMIN_RUN_INTEGRATION` in CI
- [ ] Implemented `MQ_SKIP_LIFECYCLE` in test fixtures
- [ ] Tested locally: `scripts/dev/mq_start.sh && scripts/dev/mq_seed.sh`
- [ ] Tested in CI: pushed a branch and verified the workflow
