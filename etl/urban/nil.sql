-- Da staging a nil_zones: ricarica i quartieri e assegna ogni place
-- dell'area al proprio NIL. Variabili psql: area (vedi import_areas).
\set ON_ERROR_STOP on
BEGIN;

DELETE FROM nil_zones;
INSERT INTO nil_zones (name, geom)
SELECT name, ST_Multi(ST_GeomFromGeoJSON(geom_json))
FROM staging.nil_raw;

UPDATE places p
SET nil = (SELECT z.name FROM nil_zones z
          WHERE ST_Covers(z.geom, p.geom::geometry) LIMIT 1)
WHERE onqi_in_area(:'area', p.geom, p.postcode);

-- Punti esattamente sul confine (buchi tra i poligoni): quartiere più vicino.
UPDATE places p
SET nil = (SELECT z.name FROM nil_zones z
          WHERE ST_DWithin(z.geom, p.geom::geometry, 100)
          ORDER BY z.geom <-> p.geom::geometry LIMIT 1)
WHERE p.nil IS NULL AND onqi_in_area(:'area', p.geom, p.postcode);

COMMIT;
