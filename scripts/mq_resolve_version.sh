#!/usr/bin/env bash
# Resolve an MQ version alias to its image, caps, and Compose project name.
#
# Source it and call mq_resolve to export the environment for the
# lifecycle scripts, or run it directly to print the resolved image:
#   source scripts/mq_resolve_version.sh && mq_resolve "${MQ_VERSION:-}"
#   scripts/mq_resolve_version.sh 10.0   # prints the image tag
set -euo pipefail

MQ_VERSIONS_FILE="${MQ_VERSIONS_FILE:-mq-versions.json}"

mq_resolve() {
  command -v jq >/dev/null 2>&1 || {
    echo "mq_resolve_version: jq is required but not installed." \
         "Install jq: https://jqlang.github.io/jq/" >&2
    return 1
  }

  local alias="${1:-}"
  if [ -z "$alias" ]; then
    alias="$(jq -r '.default' "$MQ_VERSIONS_FILE")"
  fi

  local image
  if ! image="$(jq -er --arg v "$alias" '.versions[$v].image' "$MQ_VERSIONS_FILE" 2>/dev/null)"; then
    local known
    known="$(jq -r '.versions | keys_unsorted | join(", ")' "$MQ_VERSIONS_FILE")"
    echo "mq_resolve_version: unknown MQ version '$alias'. Valid versions: $known." >&2
    return 1
  fi

  MQ_VERSION="$alias"
  MQ_IMAGE="$image"
  MQ_CAPS="$(jq -c --arg v "$alias" '.versions[$v].caps // []' "$MQ_VERSIONS_FILE")"
  COMPOSE_PROJECT_NAME="${MQ_PROJECT_NAME_PREFIX:-mq-dev}-${alias//./_}"
  export MQ_VERSION MQ_IMAGE MQ_CAPS COMPOSE_PROJECT_NAME
}

# Executed directly (not sourced): print the resolved image and exit.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  mq_resolve "${1:-}"
  echo "$MQ_IMAGE"
fi
