# Environment Contract

The language-specific libraries depend on these stable details.
Changes to any of these values are breaking changes and require
coordination with all language libraries.

## Connection details

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
the full set covering all major MQ object types; QM2 has a minimal
subset plus cross-QM routing counterparts.

See [Seed Data](../configuration/seed-data.md) for the complete
object listing.

## CI outputs

The composite action exposes REST API base URLs as step outputs:

| Output | Value |
| --- | --- |
| `qm1-rest-url` | `https://localhost:9443/ibmmq/rest/v2` |
| `qm2-rest-url` | `https://localhost:9444/ibmmq/rest/v2` |

See [CI Integration](../ci-integration.md) for usage details.

## Language libraries

This environment is used by the language-specific libraries in the
mq-rest-admin project:

- [mq-rest-admin-python](https://github.com/mq-rest-admin-project/mq-rest-admin-python)
- [mq-rest-admin-java](https://github.com/mq-rest-admin-project/mq-rest-admin-java)
- [mq-rest-admin-go](https://github.com/mq-rest-admin-project/mq-rest-admin-go)
- [mq-rest-admin-ruby](https://github.com/mq-rest-admin-project/mq-rest-admin-ruby)
- [mq-rest-admin-rust](https://github.com/mq-rest-admin-project/mq-rest-admin-rust)
