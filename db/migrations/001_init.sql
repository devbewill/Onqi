-- Schema iniziale Onqi: attività, orari, promo.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS staging;

-- ---------------------------------------------------------------------------
-- Categorie (tassonomia Onqi, due livelli: macro -> categoria)
-- ---------------------------------------------------------------------------
CREATE TABLE categories (
  id        serial PRIMARY KEY,
  parent_id int REFERENCES categories(id),
  slug      text UNIQUE NOT NULL,
  name_it   text NOT NULL
);

-- Traduce la categoria di una fonte nella categoria Onqi.
-- Le categorie sorgente non mappate restano fuori da places.
CREATE TABLE category_mappings (
  source          text NOT NULL,
  source_category text NOT NULL,
  category_id     int  NOT NULL REFERENCES categories(id),
  PRIMARY KEY (source, source_category)
);

-- ---------------------------------------------------------------------------
-- Attività
-- ---------------------------------------------------------------------------
CREATE TABLE places (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  category_id int REFERENCES categories(id),
  geom        geography(Point, 4326) NOT NULL,
  address     text,
  postcode    text,
  city        text,
  phone       text,
  website     text,
  brand       text,
  confidence  real,                                -- affidabilità della fonte (0-1)
  status      text NOT NULL DEFAULT 'unverified',  -- unverified | active | closed
  claimed_by  uuid,                                -- esercente che ha reclamato la scheda
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX places_geom_idx     ON places USING gist (geom);
CREATE INDEX places_name_trgm    ON places USING gin (name gin_trgm_ops);
CREATE INDEX places_category_idx ON places (category_id);
CREATE INDEX places_postcode_idx ON places (postcode);

-- Provenienza: ogni record sorgente punta al place in cui è confluito.
CREATE TABLE place_sources (
  source     text NOT NULL,
  source_id  text NOT NULL,
  place_id   uuid NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  raw        jsonb,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (source, source_id)
);
CREATE INDEX place_sources_place_idx ON place_sources (place_id);

-- ---------------------------------------------------------------------------
-- Orari
-- ---------------------------------------------------------------------------
CREATE TABLE opening_hours (
  id         bigserial PRIMARY KEY,
  place_id   uuid NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  weekday    smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),  -- 1 = lunedì
  opens      time NOT NULL,
  closes     time NOT NULL,   -- closes < opens => scavalca la mezzanotte
  valid_from date,            -- NULL = sempre; valorizzati = orario straordinario
  valid_to   date,
  source     text NOT NULL    -- osm | merchant
);
CREATE INDEX opening_hours_place_idx ON opening_hours (place_id);

-- ---------------------------------------------------------------------------
-- Promo / iniziative (inserite dagli esercenti)
-- ---------------------------------------------------------------------------
CREATE TABLE promotions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id    uuid NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('freebie', 'discount', 'extended_hours', 'event')),
  title       text NOT NULL,
  description text,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz,
  rrule       text,           -- ricorrenza RFC 5545, es. 'FREQ=DAILY'
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX promotions_place_idx ON promotions (place_id);

-- Fasce orarie concrete generate dalle promo (anche ricorrenti):
-- "cosa c'è adesso" = during @> now().
CREATE TABLE promotion_occurrences (
  promotion_id uuid NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  place_id     uuid NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  during       tstzrange NOT NULL,
  PRIMARY KEY (promotion_id, during)
);
CREATE INDEX promotion_occurrences_during_idx ON promotion_occurrences USING gist (during);
CREATE INDEX promotion_occurrences_place_idx  ON promotion_occurrences (place_id);

-- ---------------------------------------------------------------------------
-- Staging: dati grezzi Overture, sovrascritti a ogni import di un'area
-- ---------------------------------------------------------------------------
CREATE TABLE staging.overture_places (
  area               text NOT NULL,
  id                 text NOT NULL,
  release            text NOT NULL,
  name               text,
  basic_category     text,
  category           text,
  category_hierarchy text[],
  confidence         double precision,
  operating_status   text,
  address            text,
  locality           text,
  postcode           text,
  postcode_inferred  text,     -- CAP dedotto dai vicini quando manca
  website            text,
  phone              text,
  brand              text,
  lon                double precision NOT NULL,
  lat                double precision NOT NULL,
  sources            text,
  geom               geography(Point, 4326)
    GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED,
  PRIMARY KEY (area, id)
);
CREATE INDEX overture_places_geom_idx ON staging.overture_places USING gist (geom);
