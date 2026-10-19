-- Carica la risposta Overpass nella staging Postgres (sostituisce l'area).
-- Variabili: area, file. Il catalogo 'pg' è collegato da etl/import.sh.
DELETE FROM pg.staging.osm_places WHERE area = getvariable('area');

INSERT INTO pg.staging.osm_places (area, osm_type, osm_id, name, osm_tag, tags, lon, lat, postcode)
SELECT
  getvariable('area'), e.type, e.id, e.tags->>'name',
  coalesce('amenity=' || (e.tags->>'amenity'), 'shop=' || (e.tags->>'shop'),
           'craft=' || (e.tags->>'craft'), 'office=' || (e.tags->>'office'),
           'healthcare=' || (e.tags->>'healthcare'), 'leisure=' || (e.tags->>'leisure'),
           'tourism=' || (e.tags->>'tourism')),
  e.tags::varchar,
  coalesce(e.lon, e.center.lon), coalesce(e.lat, e.center.lat),
  regexp_extract(e.tags->>'addr:postcode', '\d{5}')
FROM (
  SELECT unnest(elements) AS e
  FROM read_json(getvariable('file'), columns = {
    elements: 'STRUCT(type VARCHAR, id BIGINT, lat DOUBLE, lon DOUBLE,
                      center STRUCT(lat DOUBLE, lon DOUBLE), tags JSON)[]'
  })
)
WHERE e.tags->>'name' IS NOT NULL;
