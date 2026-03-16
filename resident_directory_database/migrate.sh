#!/bin/bash
set -euo pipefail

# Resident Directory DB migration runner
# Uses db_connection.txt as the canonical connection string.
#
# Usage:
#   ./migrate.sh
#
# Notes:
# - Runs migrations in ./migrations/*.sql (sorted)
# - Then runs seeds in ./seeds/*.sql (sorted)
# - Intended to be safe to run multiple times (DDL is IF NOT EXISTS; seed uses ON CONFLICT)
#
# This script assumes postgres is running (startup.sh does that).

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONN_FILE="${ROOT_DIR}/db_connection.txt"

if [ ! -f "${CONN_FILE}" ]; then
  echo "ERROR: db_connection.txt not found at ${CONN_FILE}"
  exit 1
fi

CONN_STR="$(cat "${CONN_FILE}" | tr -d '\n' | tr -d '\r')"

if [ -z "${CONN_STR}" ]; then
  echo "ERROR: db_connection.txt is empty"
  exit 1
fi

echo "Using connection: ${CONN_STR}"

run_sql_file () {
  local file_path="$1"
  echo "==> Applying: ${file_path}"
  # -v ON_ERROR_STOP=1 ensures psql stops on first error
  psql "${CONN_STR}" -v ON_ERROR_STOP=1 -f "${file_path}"
  echo "✓ Applied: ${file_path}"
}

if [ -d "${ROOT_DIR}/migrations" ]; then
  for f in $(ls -1 "${ROOT_DIR}/migrations"/*.sql 2>/dev/null | sort); do
    run_sql_file "$f"
  done
fi

if [ -d "${ROOT_DIR}/seeds" ]; then
  for f in $(ls -1 "${ROOT_DIR}/seeds"/*.sql 2>/dev/null | sort); do
    run_sql_file "$f"
  done
fi

echo "All migrations and seeds applied successfully."
