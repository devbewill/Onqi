-- Carica il Parquet estratto nella staging Postgres (sostituisce l'area).
-- Variabili: area, release, file. Il catalogo 'pg' è collegato da etl/import.sh.

DELETE FROM pg.staging.overture_places WHERE area = getvariable('area');

INSERT INTO pg.staging.overture_places
  (area, id, release, name, basic_category, category, category_hierarchy, confidence,
   operating_status, address, locality, postcode, website, phone, email, socials, brand, lon, lat, sources)
SELECT
  getvariable('area'), id, getvariable('release'), name, basic_category, category,
  category_hierarchy, confidence, operating_status, address, locality,
  regexp_extract(postcode, '\d{5}'), website, phone, email, socials, brand, lon, lat, sources::varchar
FROM read_parquet(getvariable('file'));
