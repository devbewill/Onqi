-- Contesto urbano #1: quartieri NIL (Nuclei di Identità Locali) del Comune
-- di Milano (PGT 2030) — CC BY 4.0. Ogni place viene etichettato con il
-- quartiere in cui si trova, per ricerche e schede.
CREATE TABLE nil_zones (
  name text PRIMARY KEY,
  geom geometry(MultiPolygon, 4326) NOT NULL
);
CREATE INDEX nil_zones_geom_idx ON nil_zones USING gist (geom);

ALTER TABLE places ADD COLUMN nil text;
CREATE INDEX places_nil_idx ON places (nil);

-- Riquadro temporaneo per il caricamento del GeoJSON (etl/urban/).
CREATE TABLE staging.nil_raw (
  id_nil    integer,
  name      text NOT NULL,
  geom_json text NOT NULL       -- feature geometry GeoJSON
);
