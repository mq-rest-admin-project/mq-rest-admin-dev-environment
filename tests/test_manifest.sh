#!/usr/bin/env bash
# Validates the real mq-versions.json manifest structure.
set -uo pipefail

MANIFEST="mq-versions.json"
fails=0
check() { # description, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi
}

jq -e . "$MANIFEST" >/dev/null 2>&1; check "manifest is valid JSON" $?

jq -e '.default as $d | .versions | has($d)' "$MANIFEST" >/dev/null 2>&1
check "default names an existing version" $?

jq -e '.versions | to_entries | all(.value.image | type == "string" and length > 0)' \
  "$MANIFEST" >/dev/null 2>&1
check "every version has a non-empty image" $?

jq -e '.versions | to_entries | all(.value.caps | type == "array")' \
  "$MANIFEST" >/dev/null 2>&1
check "every version has a caps array" $?

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails check(s) failed"; exit 1; }
