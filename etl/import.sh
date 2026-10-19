#!/usr/bin/env bash
# Importa le attività di un'area definita in etl/areas.csv: Overture, poi OSM, poi Comune di Milano.
# Uso: etl/import.sh <area> [release]
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

AREA="${1:?uso: etl/import.sh <area> [release]}"
RELEASE="${2:-$(curl -s https://stac.overturemaps.org/catalog.json | sed -E 's/.*"latest":"([^"]+)".*/\1/')}"

ROW=$(awk -F, -v a="$AREA" 'NR > 1 && $1 == a' etl/areas.csv)
[ -n "$ROW" ] || { echo "Area '$AREA' non trovata in etl/areas.csv" >&2; exit 1; }
IFS=, read -r _ POSTCODE XMIN XMAX YMIN YMAX <<< "$ROW"

FILE="data/overture_${AREA}_${RELEASE}.parquet"
PG="host=127.0.0.1 port=${POSTGRES_PORT} dbname=${POSTGRES_DB} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD}"
mkdir -p data

if [ ! -f "$FILE" ]; then
  echo "==> Estrazione Overture $RELEASE per $AREA"
  duckdb -bail -cmd "SET VARIABLE release='$RELEASE'; SET VARIABLE xmin=$XMIN; SET VARIABLE xmax=$XMAX;
               SET VARIABLE ymin=$YMIN; SET VARIABLE ymax=$YMAX; SET VARIABLE out='$FILE';" \
    < etl/overture/extract.sql
fi

echo "==> Caricamento in staging"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE area='$AREA'; SET VARIABLE release='$RELEASE';
             SET VARIABLE file='$FILE';" < etl/overture/load.sql

psql_() { docker exec -i onqi-db psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"; }

echo "==> Trasformazione Overture in places"
psql_ -v area="$AREA" -v postcode="$POSTCODE" < etl/overture/transform.sql

# --- OpenStreetMap (Overpass) ---------------------------------------------
OSM_FILE="data/osm_${AREA}.json"
if [ ! -f "$OSM_FILE" ]; then
  echo "==> Download OSM da Overpass"
  QUERY=$(sed "s/{{bbox}}/$YMIN,$XMIN,$YMAX,$XMAX/g" etl/osm/query.overpassql)
  for wait in 0 15 30 60 120; do
    sleep "$wait"
    curl -s -m 200 -A "onqi-etl/0.1" --data-urlencode "data=$QUERY" \
      https://overpass-api.de/api/interpreter -o "$OSM_FILE.tmp" || true
    if grep -q '"elements"' "$OSM_FILE.tmp" 2>/dev/null; then mv "$OSM_FILE.tmp" "$OSM_FILE"; break; fi
    echo "    Overpass occupato, riprovo..."
  done
  [ -f "$OSM_FILE" ] || { echo "Download OSM fallito" >&2; rm -f "$OSM_FILE.tmp"; exit 1; }
fi

echo "==> Caricamento OSM in staging"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE area='$AREA'; SET VARIABLE file='$OSM_FILE';" < etl/osm/load.sql

echo "==> Abbinamento OSM e orari"
psql_ -v area="$AREA" -v postcode="$POSTCODE" < etl/osm/transform.sql

# --- Comune di Milano: esercizi di vicinato e pubblici esercizi -------------
COMUNE_BASE="https://dati.comune.milano.it/dataset"
declare -a COMUNE_FILES=(
  "comune_vicinato.csv|$COMUNE_BASE/f6764e63-4a8c-46f0-9dc8-7a671e0a3950/resource/95ef10f2-c825-451d-aa3d-6ff4ed7fd267/download/ds49_commercio_esercizi_vicinato_sede_fissa.csv"
  "comune_pe_in_piano.csv|$COMUNE_BASE/f0671ce0-8c11-4ee8-95e5-c09913d00f83/resource/d70a4002-af24-42db-9ace-00d4a102ccb8/download/ds58_commercio_pubblici_esercizi_in_piano.csv"
  "comune_pe_fuori_piano.csv|$COMUNE_BASE/726fb09b-e2ce-4407-8579-51aef8027498/resource/bdb64cee-0f60-4271-8e35-dcda7a07de33/download/ds59_commercio_pubblici_esercizi_fuori_piano.csv"
)
for entry in "${COMUNE_FILES[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  if [ ! -f "data/$name" ]; then
    echo "==> Download $name"
    curl -sf -m 300 -o "data/$name.tmp" "$url" && mv "data/$name.tmp" "data/$name"
  fi
done

echo "==> Caricamento Comune in staging"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE dir='data';" < etl/comune/load.sql

echo "==> Abbinamento Comune"
psql_ -v postcode="$POSTCODE" < etl/comune/transform.sql

psql_ -c "SELECT count(*) AS places,
                 count(*) FILTER (WHERE EXISTS (SELECT 1 FROM opening_hours o WHERE o.place_id = p.id)) AS con_orari
          FROM places p WHERE postcode = '$POSTCODE';"
