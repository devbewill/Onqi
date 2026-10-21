-- Contesto urbano #2: fermate e linee del trasporto pubblico (feed GTFS di
-- ATM generato da AMAT, dati.comune.milano.it/gtfs.zip) — CC BY 4.0. Serve a
-- mostrare in scheda quale ferrota è più vicina e con quali linee.
CREATE TABLE transit_stops (
  stop_id         text PRIMARY KEY,
  stop_code       text,
  stop_name       text NOT NULL,
  stop_lat        double precision NOT NULL,
  stop_lon        double precision NOT NULL,
  location_type   smallint,
  parent_station  text,
  geom geography(Point, 4326)
    GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(stop_lon, stop_lat), 4326)::geography) STORED
);
CREATE INDEX transit_stops_geom_idx ON transit_stops USING gist (geom);

CREATE TABLE transit_routes (
  route_id         text PRIMARY KEY,
  route_short_name text,
  route_long_name  text,
  route_type       smallint NOT NULL   -- 0 tram, 1 metro, 3 bus
);

CREATE TABLE transit_stop_routes (
  stop_id  text NOT NULL,
  route_id text NOT NULL,
  PRIMARY KEY (stop_id, route_id)
);
