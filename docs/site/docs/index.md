# mq-rest-admin-dev-environment

Shared dockerized IBM MQ test environment for use across multiple
repositories. Provides container lifecycle scripts, seed data, and
a reusable GitHub Actions composite action for integration testing
against a real MQ queue manager.

## Language libraries

This environment is used by the language-specific libraries in the
mq-rest-admin project:

- [mq-rest-admin-python](https://github.com/mq-rest-admin-project/mq-rest-admin-python)
- [mq-rest-admin-java](https://github.com/mq-rest-admin-project/mq-rest-admin-java)
- [mq-rest-admin-go](https://github.com/mq-rest-admin-project/mq-rest-admin-go)
- [mq-rest-admin-ruby](https://github.com/mq-rest-admin-project/mq-rest-admin-ruby)
- [mq-rest-admin-rust](https://github.com/mq-rest-admin-project/mq-rest-admin-rust)

## What this repo provides

- **Two queue managers** (QM1 and QM2) running in Docker containers
  with REST API access enabled
- **Seed data** covering all major MQ object types (queues, channels,
  topics, namelists, processes, listeners)
- **Cross-QM routing** with bidirectional sender/receiver channel
  pairs and gateway QM aliases for REST API command routing
- **Lifecycle scripts** for starting, seeding, verifying, resetting,
  and stopping the environment
- **CI composite action** for use in GitHub Actions workflows

## Quick links

- [Getting Started](getting-started.md) — prerequisites and quick
  start
- [New Repository Onboarding](setup/new-repo.md) — add a new
  language library to the project
- [Environment Contract](architecture/environment-contract.md) —
  stable ports, credentials, and URLs
- [CI Integration](ci-integration.md) — composite action usage
- [Lifecycle Scripts](lifecycle-scripts.md) — script reference
