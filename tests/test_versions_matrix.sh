#!/usr/bin/env bash
# Covers scripts/mq_versions_matrix.sh against the fixture manifest.
set -uo pipefail

export MQ_VERSIONS_FILE="tests/fixtures/mq-versions.json"
out="$(bash scripts/mq_versions_matrix.sh)"
if [ "$out" = '["10.0","9.4.5"]' ]; then
  echo "ok   - emits sorted JSON array of aliases"; echo "PASS"
else
  echo "FAIL - expected [\"10.0\",\"9.4.5\"] got [$out]"; exit 1
fi
