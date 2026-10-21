#!/usr/bin/env bash
# Orari del trasporto pubblico di Milano in formato GTFS (ATM via AMAT,
# CC BY 4.0) — ferma le tabelle transit_* usate dall'app. Città intera, non
# per-area: basta eseguirlo una volta a aggiornamento del feed (quindicinale).
# Uso: etl/gtfs/import.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; source .env; set +a

PG="host=127.0.0.1 port=${POSTGRES_PORT} dbname=${POSTGRES_DB} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD}"
mkdir -p data

if [ ! -f data/gtfs/stops.txt ]; then
  echo "==> Download GTFS (dati.comune.milano.it/gtfs.zip)"
  curl -sfL -m 600 -o data/gtfs.zip.tmp https://dati.comune.milano.it/gtfs.zip
  mv data/gtfs.zip.tmp data/gtfs.zip
  unzip -qo data/gtfs.zip -d data/gtfs
fi

echo "==> Caricamento GTFS in transit_*"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE dir='data/gtfs';" < etl/gtfs/load.sql

PSQL="docker exec onqi-db psql -q -U $POSTGRES_USER -d $POSTGRES_DB"
$PSQL -c "SELECT (SELECT count(*) FROM transit_stops) fermate,
                (SELECT count(*) FROM transit_routes) linee,
                (SELECT count(*) FROM transit_stop_routes) fermata_linee"
