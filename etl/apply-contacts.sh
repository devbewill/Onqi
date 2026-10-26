#!/usr/bin/env bash
# Applica contatti ricercati a mano da un CSV.
# Input: name,address,instagram,facebook,website
# Uso: etl/apply-contacts.sh <csv>
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

CSV="${1:?uso: etl/apply-contacts.sh <csv>}"
[ -f "$CSV" ] || { echo "File non trovato: $CSV" >&2; exit 1; }

PGURL="host=127.0.0.1 port=${POSTGRES_PORT} dbname=${POSTGRES_DB} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD}"

{
  cat <<'PREAMBLE'
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL onqi.manual_edit = 'on';
CREATE TEMP TABLE contacts_input (
  name text,
  address text,
  instagram text,
  facebook text,
  website text
) ON COMMIT DROP;
\copy contacts_input FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
PREAMBLE
  cat "$CSV"
  cat <<'POSTAMBLE'
\.
\i etl/contacts/apply.sql
COMMIT;
POSTAMBLE
} | psql "$PGURL" -q
