-- Estrae da Overture Maps i luoghi dentro un rettangolo e li salva in Parquet locale.
-- Variabili (impostate da etl/import.sh): release, xmin, xmax, ymin, ymax, out
INSTALL spatial; LOAD spatial;
INSTALL httpfs;  LOAD httpfs;
SET s3_region = 'us-west-2';

COPY (
  SELECT
    id,
    names.primary                 AS name,
    basic_category,
    taxonomy.primary              AS category,
    taxonomy.hierarchy            AS category_hierarchy,
    confidence,
    operating_status,
    addresses[1].freeform         AS address,
    addresses[1].locality         AS locality,
    addresses[1].postcode         AS postcode,
    websites[1]                   AS website,
    phones[1]                     AS phone,
    emails[1]                     AS email,
    socials,
    brand.names.primary           AS brand,
    ST_X(geometry)                AS lon,
    ST_Y(geometry)                AS lat,
    to_json(sources)              AS sources
  FROM read_parquet(
    's3://overturemaps-us-west-2/release/' || getvariable('release') || '/theme=places/type=place/*',
    hive_partitioning = 1
  )
  WHERE bbox.xmin BETWEEN getvariable('xmin') AND getvariable('xmax')
    AND bbox.ymin BETWEEN getvariable('ymin') AND getvariable('ymax')
) TO (getvariable('out')) (FORMAT parquet);
