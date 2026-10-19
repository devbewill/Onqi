-- Dalla staging Overture a places / place_sources per un'area.
-- Variabili psql: area, postcode
\set ON_ERROR_STOP on
BEGIN;

-- 1. CAP mancante: lo deduco dal CAP più frequente tra i 7 vicini più prossimi.
UPDATE staging.overture_places s
SET postcode_inferred = (
  -- a parità di voti vince il CAP del vicino più prossimo (risultato stabile tra un import e l'altro)
  SELECT n.postcode
  FROM (
    SELECT n.postcode, n.geom <-> s.geom AS dist
    FROM staging.overture_places n
    WHERE n.area = s.area AND n.postcode IS NOT NULL
    ORDER BY n.geom <-> s.geom, n.id
    LIMIT 7
  ) n
  GROUP BY n.postcode
  ORDER BY count(*) DESC, min(n.dist)
  LIMIT 1
)
WHERE s.area = :'area' AND s.postcode IS NULL;

-- 2. Record da importare: CAP dell'area, non chiusi, affidabili. Si importano tutte
--    le categorie (anche non pubbliche): la dettagliata vince sulla generica e
--    quelle non mappate finiscono in 'altro'.
CREATE TEMP TABLE candidates ON COMMIT DROP AS
SELECT s.*, coalesce(d.category_id, m.category_id,
                     (SELECT id FROM categories WHERE slug = 'altro')) AS category_id
FROM staging.overture_places s
LEFT JOIN category_mappings m
  ON m.source = 'overture' AND m.source_category = s.basic_category
LEFT JOIN category_mappings d
  ON d.source = 'overture_detail' AND d.source_category = s.category
WHERE s.area = :'area'
  AND coalesce(s.postcode, s.postcode_inferred) = :'postcode'
  AND s.name IS NOT NULL
  AND s.confidence >= 0.3;

-- 3. Aggiorna i place già importati in passato. Nome e categoria restano
--    quelli di OSM se il place è stato abbinato a OSM.
UPDATE places p
SET name        = CASE WHEN osm.linked THEN p.name ELSE c.name END,
    category_id = CASE WHEN osm.linked THEN p.category_id ELSE c.category_id END,
    geom        = c.geom,
    address     = c.address,
    postcode    = coalesce(c.postcode, c.postcode_inferred),
    city        = c.locality,
    phone       = c.phone,
    website     = c.website,
    email       = c.email,
    socials     = c.socials,
    brand       = c.brand,
    confidence  = c.confidence,
    status      = CASE WHEN c.operating_status = 'permanently_closed' THEN 'closed' ELSE p.status END,
    updated_at  = now()
FROM candidates c
JOIN place_sources ps ON ps.source = 'overture' AND ps.source_id = c.id
CROSS JOIN LATERAL (
  SELECT EXISTS (SELECT 1 FROM place_sources o WHERE o.place_id = ps.place_id AND o.source = 'osm') AS linked
) osm
WHERE p.id = ps.place_id;

-- 4. Record Overture nuovi che corrispondono a un place nato solo da OSM (es. importato
--    con un'area vicina prima di questa): li collego invece di creare un doppione.
--    Stesso criterio dell'abbinamento OSM (etl/osm/transform.sql), accoppiamento 1:1 greedy.
CREATE TEMP TABLE links (source_id text, place_id uuid) ON COMMIT DROP;

CREATE TEMP TABLE pairs ON COMMIT DROP AS
SELECT c.id AS source_id, p.id AS place_id,
       onqi_name_score(c.name, p.name) - ST_Distance(c.geom, p.geom) / 150 AS score
FROM candidates c
JOIN places p ON ST_DWithin(p.geom, c.geom, 60)
WHERE NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.source = 'overture' AND ps.source_id = c.id)
  AND NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.place_id = p.id AND ps.source = 'overture');
DELETE FROM pairs WHERE score < 0.45;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pairs ORDER BY score DESC LOOP
    IF NOT EXISTS (SELECT 1 FROM links WHERE source_id = r.source_id OR place_id = r.place_id) THEN
      INSERT INTO links VALUES (r.source_id, r.place_id);
    END IF;
  END LOOP;
END $$;

UPDATE places p
SET phone      = coalesce(p.phone, c.phone),
    website    = coalesce(p.website, c.website),
    email      = coalesce(p.email, c.email),
    socials    = coalesce(p.socials, c.socials),
    confidence = c.confidence,
    updated_at = now()
FROM links l JOIN candidates c ON c.id = l.source_id
WHERE p.id = l.place_id;

INSERT INTO place_sources (source, source_id, place_id, raw)
SELECT 'overture', c.id, l.place_id,
       jsonb_build_object('release', c.release, 'basic_category', c.basic_category,
                          'category', c.category, 'sources', c.sources::jsonb)
FROM links l JOIN candidates c ON c.id = l.source_id;

-- 5. Inserisce i nuovi (i chiusi in modo permanente non entrano).
WITH new AS MATERIALIZED (
  SELECT gen_random_uuid() AS place_id, c.*
  FROM candidates c
  WHERE c.operating_status IS DISTINCT FROM 'permanently_closed'
    AND NOT EXISTS (
      SELECT 1 FROM place_sources ps WHERE ps.source = 'overture' AND ps.source_id = c.id
    )
), ins AS (
  INSERT INTO places (id, name, category_id, geom, address, postcode, city,
                      phone, website, email, socials, brand, confidence)
  SELECT place_id, name, category_id, geom, address, coalesce(postcode, postcode_inferred),
         locality, phone, website, email, socials, brand, confidence
  FROM new
)
INSERT INTO place_sources (source, source_id, place_id, raw)
SELECT 'overture', id, place_id,
       jsonb_build_object('release', release, 'basic_category', basic_category,
                          'category', category, 'sources', sources::jsonb)
FROM new;

-- 6. Esercizio aperto al pubblico o no (vedi db/migrations/007_public_flag.sql).
DO $$ BEGIN PERFORM onqi_refresh_public(); END $$;

COMMIT;
