#!/usr/bin/env bash
# Print the manifest's version aliases as a compact JSON array, for use
# as a GitHub Actions matrix (consumed via fromJSON).
set -euo pipefail

MQ_VERSIONS_FILE="${MQ_VERSIONS_FILE:-mq-versions.json}"
jq -c '.versions | keys' "$MQ_VERSIONS_FILE"
