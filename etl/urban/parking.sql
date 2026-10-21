-- Da staging a parking: geometrie e posti dei parcheggi e delle aree di
-- sosta del Comune di Milano.
\set ON_ERROR_STOP on
BEGIN;

TRUNCATE parking;
INSERT INTO parking (id, kind, name, address, spaces, rate_eur_h, info, geom, area)
SELECT r.kind || ':' || coalesce(r.id, row_number() OVER (PARTITION BY r.kind ORDER BY r.name)::text),
       r.kind, r.name, r.address, r.spaces, r.rate, r.info,
       ST_Centroid(g.geom),
       CASE WHEN GeometryType(g.geom) = 'MULTIPOLYGON' THEN g.geom END
FROM staging.parking_raw r
CROSS JOIN LATERAL (SELECT ST_GeomFromGeoJSON(r.geom_json) AS geom) g;

COMMIT;
