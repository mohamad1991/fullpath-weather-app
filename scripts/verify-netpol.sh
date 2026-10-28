#!/usr/bin/env bash
# Proves NetworkPolicies are enforced (not just present): every flow the
# architecture needs is ALLOWED, everything else is BLOCKED.
# Usage: scripts/verify-netpol.sh [namespace] [release]
set -uo pipefail
NS=${1:-weather}
REL=${2:-weather}

FE=$(kubectl -n "$NS" get pod -l app.kubernetes.io/instance="$REL",app.kubernetes.io/component=frontend -o name | head -1)
API=$(kubectl -n "$NS" get pod -l app.kubernetes.io/instance="$REL",app.kubernetes.io/component=api -o name | head -1)
DB_HOST=$(kubectl -n "$NS" exec "$API" -- printenv DB_HOST)
PYCONN='import socket,sys; socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=3)'
failures=0

check() {
  local desc=$1 expect=$2 got result
  shift 2
  if "$@" >/dev/null 2>&1; then got=ALLOWED; else got=BLOCKED; fi
  if [[ $got == "$expect" ]]; then result=PASS; else result=FAIL; failures=$((failures + 1)); fi
  printf "%-4s %-36s expected %-8s got %s\n" "$result" "$desc" "$expect" "$got"
}

check "frontend -> api"               ALLOWED kubectl -n "$NS" exec "$FE" -- nc -z -w3 "$REL-api" 80
check "frontend -> postgres"          BLOCKED kubectl -n "$NS" exec "$FE" -- nc -z -w3 "$DB_HOST" 5432
check "frontend -> internet"          BLOCKED kubectl -n "$NS" exec "$FE" -- nc -z -w3 1.1.1.1 443
check "api -> postgres"               ALLOWED kubectl -n "$NS" exec "$API" -- python -c "$PYCONN" "$DB_HOST" 5432
check "api -> internet"               BLOCKED kubectl -n "$NS" exec "$API" -- python -c "$PYCONN" 1.1.1.1 443
check "api -> kubernetes API"         BLOCKED kubectl -n "$NS" exec "$API" -- python -c "$PYCONN" kubernetes.default 443
check "api -> frontend (lateral)"     BLOCKED kubectl -n "$NS" exec "$API" -- python -c "$PYCONN" "$REL-frontend" 80

exit $failures
