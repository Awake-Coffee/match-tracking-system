#!/usr/bin/env bash
# Runs the migrations and SQL tests against a throwaway local Postgres.
# Usage: supabase/tests/run.sh   (needs Postgres server binaries on PATH or
# in /usr/lib/postgresql/<version>/bin)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

if ! command -v initdb >/dev/null 2>&1; then
  pgbin="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)"
  [ -n "$pgbin" ] && export PATH="$pgbin:$PATH"
fi

tmp="$(mktemp -d)"
port="${PGTEST_PORT:-54329}"

# Postgres refuses to run as root; drop to the postgres user when needed.
run_pg() { if [ "$(id -u)" = 0 ]; then su postgres -s /bin/bash -c "PATH=$PATH; $*"; else bash -c "$*"; fi; }
cleanup() { run_pg "pg_ctl -D '$tmp/data' -m immediate stop" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

[ "$(id -u)" = 0 ] && chown -R postgres "$tmp"

run_pg "initdb -D '$tmp/data' -A trust -U postgres >/dev/null"
run_pg "pg_ctl -D '$tmp/data' -o '-p $port -k $tmp' -l '$tmp/log' -w start >/dev/null"

psql_in() { psql -h "$tmp" -p "$port" -U postgres -d "$1" -v ON_ERROR_STOP=1 -q -o /dev/null "${@:2}"; }

psql_in postgres -f "$here/supabase_stub.sql"
for f in "$root"/supabase/migrations/*.sql; do
  psql_in postgres -f "$f"
done
for f in "$here"/*_test.sql; do
  psql_in postgres -f "$f"
done

# Upgrade tests, each in a fresh database: upgrade/<migration>_seed.sql adds
# rows in the schema just before <migration>, then the remaining migrations
# run and upgrade/<migration>_test.sql checks how the rows carried over.
for seed in "$here"/upgrade/*_seed.sql; do
  [ -e "$seed" ] || continue
  migration="$(basename "$seed" _seed.sql)"
  db="upgrade_$migration"
  psql_in postgres -c "create database \"$db\""
  psql_in "$db" -f "$here/supabase_stub.sql"
  for f in "$root"/supabase/migrations/*.sql; do
    [ "$(basename "$f" .sql)" = "$migration" ] && psql_in "$db" -f "$seed"
    psql_in "$db" -f "$f"
  done
  psql_in "$db" -f "$here/upgrade/${migration}_test.sql"
done
