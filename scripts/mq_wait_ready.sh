#!/usr/bin/env bash
set -euo pipefail

# Readiness gate for the MQ dev environment.
#
# Polls each queue manager's administrative REST endpoint and only
# returns success once EVERY queue manager has answered healthily for
# MQ_READY_CONSECUTIVE consecutive rounds.
#
# A single successful probe is not enough: during startup the MQ web
# server accepts a connection and answers one request while the queue
# manager is still stabilising, then resets connections moments later
# (observed downstream as `SSL_ERROR_SYSCALL` / `Connection reset by
# peer`).  Requiring a stability window keeps seed/verify and the
# consuming repos' tests from firing into that window.
#
# On timeout the script exits non-zero with an explicit message so a
# genuine startup failure is distinguishable from a slow start.

mq_admin_user="${MQ_ADMIN_USER:-mqadmin}"
mq_admin_password="${MQ_ADMIN_PASSWORD:-mqadmin}"

qm1_rest_port="${QM1_REST_PORT:-9443}"
qm2_rest_port="${QM2_REST_PORT:-9444}"

wait_timeout_seconds="${MQ_READY_TIMEOUT_SECONDS:-120}"
wait_interval_seconds="${MQ_READY_INTERVAL_SECONDS:-3}"
required_consecutive="${MQ_READY_CONSECUTIVE:-3}"

# Parallel arrays: queue manager name -> REST base URL.
qmgr_names=("QM1" "QM2")
rest_base_urls=(
  "https://localhost:${qm1_rest_port}/ibmmq/rest/v2"
  "https://localhost:${qm2_rest_port}/ibmmq/rest/v2"
)

probe_qm() {
  local rest_base_url="$1"
  local qmgr_name="$2"
  curl -sS -k -u "${mq_admin_user}:${mq_admin_password}" \
    -H "Content-Type: application/json" \
    -H "ibm-mq-rest-csrf-token: local" \
    -d '{"type": "runCommandJSON", "command": "DISPLAY", "qualifier": "QMGR"}' \
    -o /dev/null \
    --fail \
    --retry 2 \
    --retry-connrefused \
    --max-time 5 \
    "${rest_base_url}/admin/action/qmgr/${qmgr_name}/mqsc"
}

all_qms_ready() {
  local i
  for i in "${!qmgr_names[@]}"; do
    if ! probe_qm "${rest_base_urls[$i]}" "${qmgr_names[$i]}"; then
      return 1
    fi
  done
  return 0
}

start_epoch="$(date +%s)"
consecutive=0

while true; do
  if all_qms_ready; then
    consecutive=$((consecutive + 1))
    if ((consecutive >= required_consecutive)); then
      echo "All queue managers ready (${required_consecutive} consecutive healthy probes)."
      exit 0
    fi
    echo "Queue managers healthy (${consecutive}/${required_consecutive} consecutive)..."
  else
    if ((consecutive > 0)); then
      echo "Readiness probe regressed before reaching ${required_consecutive} consecutive; resetting stability counter."
    fi
    consecutive=0
  fi

  now_epoch="$(date +%s)"
  elapsed_seconds="$((now_epoch - start_epoch))"
  if ((elapsed_seconds >= wait_timeout_seconds)); then
    echo "Queue manager not ready after ${wait_timeout_seconds}s" \
      "(needed ${required_consecutive} consecutive healthy probes, reached ${consecutive})." >&2
    exit 1
  fi

  sleep "${wait_interval_seconds}"
done
