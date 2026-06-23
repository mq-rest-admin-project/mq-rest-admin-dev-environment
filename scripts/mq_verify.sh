#!/usr/bin/env bash
set -euo pipefail

mq_admin_user="${MQ_ADMIN_USER:-mqadmin}"
mq_admin_password="${MQ_ADMIN_PASSWORD:-mqadmin}"

qm1_rest_port="${QM1_REST_PORT:-9443}"
qm2_rest_port="${QM2_REST_PORT:-9444}"
qm1_rest_base_url="https://localhost:${qm1_rest_port}/ibmmq/rest/v2"
qm2_rest_base_url="https://localhost:${qm2_rest_port}/ibmmq/rest/v2"

# Don't probe seed objects until both queue managers serve requests.
scripts/mq_wait_ready.sh

echo "=== QM1: DEV.QLOCAL ==="
curl -sS -k -u "${mq_admin_user}:${mq_admin_password}" \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: local" \
  -d '{"type": "runCommandJSON", "command": "DISPLAY", "qualifier": "QLOCAL", "name": "DEV.QLOCAL"}' \
  "${qm1_rest_base_url}/admin/action/qmgr/QM1/mqsc"

echo ""
echo "---"
echo ""

echo "=== QM1: DEV.SVRCONN ==="
curl -sS -k -u "${mq_admin_user}:${mq_admin_password}" \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: local" \
  -d '{"type": "runCommandJSON", "command": "DISPLAY", "qualifier": "CHANNEL", "name": "DEV.SVRCONN"}' \
  "${qm1_rest_base_url}/admin/action/qmgr/QM1/mqsc"

echo ""
echo "---"
echo ""

echo "=== QM2: DEV.QLOCAL ==="
curl -sS -k -u "${mq_admin_user}:${mq_admin_password}" \
  -H "Content-Type: application/json" \
  -H "ibm-mq-rest-csrf-token: local" \
  -d '{"type": "runCommandJSON", "command": "DISPLAY", "qualifier": "QLOCAL", "name": "DEV.QLOCAL"}' \
  "${qm2_rest_base_url}/admin/action/qmgr/QM2/mqsc"
