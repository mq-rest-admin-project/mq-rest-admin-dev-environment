#!/usr/bin/env bash
# Covers scripts/mq_resolve_version.sh in both CLI and sourced modes.
set -uo pipefail

export MQ_VERSIONS_FILE="tests/fixtures/mq-versions.json"
HELPER="scripts/mq_resolve_version.sh"
fails=0
eq() { # description, actual, expected
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected [$3] got [$2]"; fails=$((fails + 1)); fi
}
ok_nonzero() { # description, exit-code
  if [ "$2" -ne 0 ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected non-zero exit"; fails=$((fails + 1)); fi
}

# CLI mode: explicit alias prints its image.
eq "cli resolves 10.0 image" "$(bash "$HELPER" 10.0)" "test/mq:10.0"

# CLI mode: no alias uses the manifest default (9.4.5).
eq "cli no-arg uses default image" "$(bash "$HELPER")" "test/mq:9.4.5"

# CLI mode: unknown alias fails and names valid versions.
err="$(bash "$HELPER" bogus 2>&1)"; rc=$?
ok_nonzero "cli unknown alias exits non-zero" "$rc"
case "$err" in
  *"unknown MQ version"*"9.4.5"*"10.0"*) echo "ok   - error lists valid versions" ;;
  *) echo "FAIL - error message missing valid versions: $err"; fails=$((fails + 1)) ;;
esac

# Sourced mode: exports the full signal set for 10.0.
( set -e
  # shellcheck disable=SC1090
  source "$HELPER"
  mq_resolve 10.0
  [ "$MQ_VERSION" = "10.0" ] || { echo "FAIL - sourced MQ_VERSION"; exit 1; }
  [ "$MQ_IMAGE" = "test/mq:10.0" ] || { echo "FAIL - sourced MQ_IMAGE"; exit 1; }
  [ "$MQ_CAPS" = '["chstatus-quantum-safe"]' ] || { echo "FAIL - sourced MQ_CAPS [$MQ_CAPS]"; exit 1; }
  [ "$COMPOSE_PROJECT_NAME" = "mq-dev-10_0" ] || { echo "FAIL - sourced project name [$COMPOSE_PROJECT_NAME]"; exit 1; }
  echo "ok   - sourced mode exports version/image/caps/project"
) || fails=$((fails + 1))

# Sourced mode: 9.4.5 caps default to [].
( set -e
  # shellcheck disable=SC1090
  source "$HELPER"
  mq_resolve 9.4.5
  [ "$MQ_CAPS" = "[]" ] || { echo "FAIL - 9.4.5 caps [$MQ_CAPS]"; exit 1; }
  echo "ok   - 9.4.5 caps default to []"
) || fails=$((fails + 1))

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails check(s) failed"; exit 1; }
