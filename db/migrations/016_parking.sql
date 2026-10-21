-- Mobilità: parcheggi e sosta (Comune di Milano, CC BY 4.0). Sono dati di
-- contesto, non attività: servono a rispondere "dove parcheggio?" e "quanto
-- costa la sosta qui vicino" accanto a ogni attività.
CREATE TABLE parking (
  id         text PRIMARY KEY,
  kind       text NOT NULL,       -- pubblico | interscambio | turistico | bici | ambito
  name       text,
  address    text,
  spaces     int,                 -- posti/stalli
  rate_eur_h numeric,             -- tariffa oraria (€)
  info       text,
  geom       geometry(Point, 4326) NOT NULL,   -- centroide
  area       geometry(MultiPolygon, 4326)      -- poligono (solo ambiti di sosta)
);
CREATE INDEX parking_geom_idx ON parking USING gist (geom);
CREATE INDEX parking_area_idx ON parking USING gist (area);

-- Riquadro temporaneo per il caricamento dei GeoJSON (etl/urban/parking_load.sql).
CREATE TABLE staging.parking_raw (
  kind     text NOT NULL,
  id       text,
  name     text,
  address  text,
  spaces   integer,
  rate     numeric,
  info     text,
  geom_json text NOT NULL
);
