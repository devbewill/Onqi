#!/usr/bin/env bash
# Applica in ordine le migration di db/migrations non ancora applicate.
# Di default usa il container locale; con DATABASE_URL punta a un altro database.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

if [ -n "${DATABASE_URL:-}" ]; then
  psql_() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"; }
else
  psql_() { docker exec -i onqi-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"; }
fi

psql_ -q -c "SET client_min_messages = warning; CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())"

for f in db/migrations/*.sql; do
  v=$(basename "$f" .sql)
  if [ -z "$(psql_ -tAc "SELECT 1 FROM schema_migrations WHERE version = '$v'")" ]; then
    echo "==> $v"
    { cat "$f"; echo; echo "INSERT INTO schema_migrations (version) VALUES ('$v');"; } | psql_ -q -1
  fi
done
