#!/usr/bin/env bash
set -euo pipefail

HOST="${CASSANDRA_HOST:-cassandra}"
PORT="${CASSANDRA_PORT:-9042}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-180}"

start_ts="$(date +%s)"

echo "Waiting for Cassandra at ${HOST}:${PORT} to accept CQL..."

# quick TCP wait first
until nc -z "${HOST}" "${PORT}" >/dev/null 2>&1; do
  now_ts="$(date +%s)"
  if (( now_ts - start_ts > MAX_WAIT_SECONDS )); then
    echo "ERROR: Timed out waiting for TCP ${HOST}:${PORT}"
    exit 1
  fi
  sleep 2
done

# then wait for CQL to respond
until cqlsh "${HOST}" "${PORT}" -e "DESCRIBE KEYSPACES;" >/dev/null 2>&1; do
  now_ts="$(date +%s)"
  if (( now_ts - start_ts > MAX_WAIT_SECONDS )); then
    echo "ERROR: Timed out waiting for CQL on ${HOST}:${PORT}"
    exit 1
  fi
  sleep 2
done

echo "Cassandra is up and accepting CQL."
