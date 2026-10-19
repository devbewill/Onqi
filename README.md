# ONQI

Discover the shops, bars and public venues around you — and what they are offering right now.

The current stage is a web prototype for Milan: a database of every business that is open to the
public (built from open data) and a map-based web app to explore it, check what is open now and
edit each place by hand. Merchant-published promotions come next.

## Stack

| Layer | Technology |
|---|---|
| Database | PostgreSQL 17 + PostGIS 3.5 (`pg_trgm`, `unaccent`, `btree_gist`), Docker |
| Data import | Bash, [DuckDB](https://duckdb.org) (remote Parquet/CSV/JSON → Postgres), plain SQL |
| Data sources | [Overture Maps](https://overturemaps.org) Places, [OpenStreetMap](https://www.openstreetmap.org) via Overpass, [Comune di Milano open data](https://dati.comune.milano.it) |
| Web app | Next.js 16 (App Router, route handlers), React 19, TypeScript, Tailwind CSS 4 |
| Map | MapLibre GL JS 6, [OpenFreeMap](https://openfreemap.org) vector tiles |

## Getting started

Requirements: Docker, Node.js 20+, DuckDB (`brew install duckdb`).

```bash
# 1. Database
cp .env.example .env
docker compose up -d          # PostgreSQL + PostGIS on 127.0.0.1:5440
./db/migrate.sh               # applies pending migrations

# 2. Data (one postcode area at a time, see etl/areas.csv)
./etl/import.sh 20143
./etl/import.sh 20146
./etl/import.sh 20149

# 3. Web app
cd apps/web
cp .env.example .env.local
npm install
npm run dev                   # http://localhost:3000
```

Each import takes well under a minute and is idempotent: running it again updates existing places
without creating duplicates. To add an area, add a row (postcode + bounding box) to
`etl/areas.csv`. To start from scratch: `docker compose down -v && docker compose up -d && ./db/migrate.sh`.

## Architecture

```
┌──────────────────────┐   ┌─────────────────────────────────────┐   ┌──────────────────────┐
│ Overture Maps (S3)   │   │ etl/import.sh <area>                │   │ apps/web (Next.js)   │
│ OpenStreetMap        │──▶│  extract → staging.* → transform    │──▶│  /api/* route        │
│ Comune di Milano     │   │  (DuckDB)            (SQL in PG)    │   │  handlers + map UI   │
└──────────────────────┘   └─────────────────────────────────────┘   └──────────────────────┘
                                          │                                    ▲
                                          ▼                                    │
                              PostgreSQL + PostGIS: places, place_sources, opening_hours,
                              categories, promotions, place_edits
```

```
db/migrations/   versioned SQL schema, applied by db/migrate.sh (tracked in schema_migrations)
etl/             import pipeline: overture/, osm/, comune/, areas.csv, import.sh
apps/web/        Next.js app: app/ (UI + API routes), lib/ (queries, types)
data/            downloaded source files (git-ignored)
```

### Data model

- **`places`** — one row per real-world place: name, category, PostGIS point, address, contacts,
  VAT number, status, `is_public` flag, manually locked fields and extra attributes.
- **`place_sources`** — every source record merged into a place, with its full raw payload
  (provenance; lets imports be re-run safely).
- **`categories`** / **`category_mappings`** — ONQI's own two-level taxonomy and the translation from
  each source's categories. Each category says whether it is open to the public.
- **`opening_hours`** — weekly hours (local Milan time; `closes < opens` means past midnight),
  from OSM or entered by hand. `onqi_is_open(place, at)` answers "is it open now?".
- **`promotions`** / **`promotion_occurrences`** — promotions as rules plus their concrete time
  ranges (`tstzrange`, GiST-indexed), so "what is on right now nearby" is a single indexed query.
- **`place_edits`** — audit log of manual edits.

### Import pipeline

`etl/import.sh <area>` runs three steps, each as *extract → staging table → SQL transform*:

1. **Overture Maps** — DuckDB reads only the area's bounding box from the global Parquet release on
   S3. Missing postcodes are inferred from the nearest neighbours; records are filtered by postcode
   and upserted into `places`.
2. **OpenStreetMap** — Overpass query for shops, amenities, offices and crafts. Each OSM node is
   matched to an existing place within 60 m by name similarity (`onqi_name_score`, penalised by
   distance, greedy 1:1); unmatched nodes become new places. OSM provides the most precise
   categories and the `opening_hours` tag, parsed by `osm_opening_hours()`.
3. **Comune di Milano** — official registers of retail shops and food & drink venues. Matched by
   address (street words in any order + house number, `onqi_street_key`) with a compatible type;
   matched places are marked as confirmed, unmatched entries with a sign name become new places.

**Public vs. non-public.** Everything is stored, but the app only shows places where a person can
walk in (shops, bars, associations…). `onqi_refresh_public()` runs after every import and sets
`non_public_reason`: `categoria` (offices, professionals, clinics, schools, public bodies, parks…)
or `sede_legale` (only known from the business register, with a company-form name such as "Srl",
and not confirmed by any other source). A manual choice (`manuale`) always wins.

**Manual edits.** `PATCH /api/places/[id]` runs inside a transaction with
`SET LOCAL onqi.manual_edit = 'on'`. Edited columns are added to `places.locked_fields`, and the
`places_protect_locked` trigger stops later imports from overwriting them. Hand-entered opening
hours replace OSM ones; extra details (cuisine, accessibility…) live in `places.attributes`, falling
back to OSM tags.

### Web app

| Route | Purpose |
|---|---|
| `GET /api/places?bbox=&lat=&lon=` | public places in the visible map area, sorted by distance |
| `GET /api/nearby?lat=&lon=&radius=` | public places within a radius |
| `GET /api/search?q=&lat=&lon=` | name search (accent-insensitive, trigram similarity) |
| `GET /api/areas` | outline of each imported postcode area |
| `GET /api/places/[id]` | full detail of a place, including raw source data |
| `PATCH /api/places/[id]` | manual edit (fields, opening hours, attributes, visibility) |
| `GET /api/categories` | categories for the edit form |

The UI (`app/explorer.tsx`) shows the map and a list that follows the visible area, with
category/open-now filters and search; `app/place-panel.tsx` is the side panel with every stored
field, editable inline. MapLibre v6 loads its worker from a separate file, copied to
`public/maplibre/` by the `postinstall` script.

> The editing API has no authentication yet — add it before deploying anywhere public.

## Data licences

- OpenStreetMap data © OpenStreetMap contributors, [ODbL](https://opendatacommons.org/licenses/odbl/).
- Overture Maps Places, [CDLA Permissive 2.0](https://cdla.dev/permissive-2-0/).
- Comune di Milano open data, CC BY 4.0.

The app must display the attributions above.
