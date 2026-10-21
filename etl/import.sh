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
IFS=, read -r _ POSTCODE POLYGON XMIN XMAX YMIN YMAX <<< "$ROW"

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

# Definizione dell'area: un CAP oppure un poligono GeoJSON (etl/areas/*.geojson)
if [ -n "$POLYGON" ]; then
  GEOJSON=$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["geometry"]))' "etl/areas/$POLYGON")
else
  GEOJSON=""
fi
psql_ -v code="$AREA" -v postcode="$POSTCODE" -v geojson="$GEOJSON" <<'SQL'
INSERT INTO import_areas (code, postcode, geom)
VALUES (:'code', nullif(:'postcode', ''),
        CASE WHEN :'geojson' <> '' THEN ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(:'geojson'), 4326)) END)
ON CONFLICT (code) DO UPDATE SET postcode = excluded.postcode, geom = excluded.geom;
SQL

echo "==> Trasformazione Overture in places"
psql_ -v area="$AREA" < etl/overture/transform.sql

# --- OpenStreetMap (Overpass) ---------------------------------------------
# Il bbox viene diviso in tile: le query piccole vanno molto meglio di una
# query su tutta la città (che Overpass rifiuta quando è saturo). Ogni tile
# prova a turno i mirror pubblici.
OSM_FILE="data/osm_${AREA}.json"
OVERPASS_MIRRORS=(
  "https://overpass-api.de/api/interpreter"
  "https://overpass.kumi.systems/api/interpreter"
  "https://overpass.private.coffee/api/interpreter"
)
TILES="${OSM_TILES:-3}"

if [ ! -f "$OSM_FILE" ]; then
  echo "==> Download OSM da Overpass ($TILES x $TILES tile)"
  TILE_DIR="data/osm_${AREA}_tiles"
  mkdir -p "$TILE_DIR"
  TILE_LIST=$(awk -v xmin="$XMIN" -v xmax="$XMAX" -v ymin="$YMIN" -v ymax="$YMAX" -v n="$TILES" '
    BEGIN{ dx = (xmax - xmin) / n; dy = (ymax - ymin) / n
      for (i = 0; i < n; i++) for (j = 0; j < n; j++) {
        x1 = xmin + i * dx; x2 = (i == n - 1) ? xmax : xmin + (i + 1) * dx
        y1 = ymin + j * dy; y2 = (j == n - 1) ? ymax : ymin + (j + 1) * dy
        printf "%d_%d %.6f,%.6f,%.6f,%.6f\n", i, j, y1, x1, y2, x2
      } }')
  OK=1
  while read -r name bbox; do
    TILE_FILE="$TILE_DIR/$name.json"
    [ -f "$TILE_FILE" ] && continue   # tile già scaricato
    QUERY=$(sed "s/{{bbox}}/$bbox/g" etl/osm/query.overpassql)
    for attempt in 1 2 3; do
      for mirror in "${OVERPASS_MIRRORS[@]}"; do
        curl -s -m 300 -A "onqi-etl/0.1" --data-urlencode "data=$QUERY" \
          "$mirror" -o "$TILE_FILE.tmp" || true
        if grep -q '"elements"' "$TILE_FILE.tmp" 2>/dev/null; then
          mv "$TILE_FILE.tmp" "$TILE_FILE"; break 2
        fi
      done
      echo "    tile $name: Overpass occupato, riprovo ($attempt)..."
      sleep $((attempt * 20))
    done
    [ -f "$TILE_FILE" ] || { echo "    tile $name: fallito" >&2; OK=0; }
  done <<< "$TILE_LIST"

  if [ "$OK" = "1" ]; then
    python3 - "$OSM_FILE" "$TILE_DIR"/*.json <<'PY'
import json, sys
out, seen = sys.argv[1], {}
for path in sys.argv[2:]:
    with open(path) as fh:
        for e in json.load(fh).get("elements", []):
            seen[(e.get("type"), e.get("id"))] = e
with open(out, "w") as fh:
    json.dump({"elements": list(seen.values())}, fh)
print(f"    elementi unici: {len(seen)}")
if not seen:
    sys.exit("nessun elemento OSM nel merge")
PY
  else
    echo "Download OSM fallito: tile mancanti" >&2
    exit 1
  fi
fi

echo "==> Caricamento OSM in staging"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE area='$AREA'; SET VARIABLE file='$OSM_FILE';" < etl/osm/load.sql

echo "==> Abbinamento OSM e orari"
psql_ -v area="$AREA" < etl/osm/transform.sql

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
psql_ -v area="$AREA" < etl/comune/transform.sql

# --- Contesto urbano: quartieri NIL -----------------------------------------
NIL_URL="https://dati.comune.milano.it/dataset/e8e765fc-d882-40b8-95d8-16ff3d39eb7c/resource/9c4e0776-56fc-4f3d-8a90-f4992a3be426/download/ds964_nil_wm.geojson"
if [ ! -f data/nil.geojson ]; then
  echo "==> Download NIL"
  curl -sf -m 120 -o data/nil.geojson.tmp "$NIL_URL" && mv data/nil.geojson.tmp data/nil.geojson
fi
echo "==> Caricamento NIL in staging"
duckdb -bail -cmd "INSTALL postgres; LOAD postgres; ATTACH '$PG' AS pg (TYPE postgres);
             SET VARIABLE file='data/nil.geojson';" < etl/urban/nil_load.sql
echo "==> Assegnazione quartiere"
psql_ -v area="$AREA" < etl/urban/nil.sql

# --- Fermate e linee del trasporto pubblico (GTFS, tabelle cittadine) --------
if [ "$(psql_ -tAc "SELECT count(*) FROM transit_stops")" = "0" ]; then
  etl/gtfs/import.sh
fi

psql_ -v area="$AREA" <<'SQL'
SELECT count(*) AS places, count(*) FILTER (WHERE is_public) AS pubblici,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM opening_hours o WHERE o.place_id = p.id)) AS con_orari
FROM places p WHERE onqi_in_area(:'area', p.geom, p.postcode);
SQL
