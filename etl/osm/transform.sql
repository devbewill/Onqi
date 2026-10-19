-- Da staging OSM a places: abbina ai place esistenti, aggiunge i mancanti,
-- importa gli orari. Da eseguire dopo l'import Overture della stessa area.
-- Variabili psql: area (vedi import_areas)
\set ON_ERROR_STOP on
BEGIN;

-- 1. CAP mancante: dal CAP più frequente tra i 7 punti Overture più vicini.
UPDATE staging.osm_places s
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

CREATE TEMP TABLE candidates ON COMMIT DROP AS
SELECT s.*, s.osm_type || '/' || s.osm_id AS source_id,
       coalesce(m.category_id, k.category_id,
                (SELECT id FROM categories WHERE slug = 'altro')) AS category_id,
       s.tags::jsonb AS t
FROM staging.osm_places s
LEFT JOIN category_mappings m ON m.source = 'osm' AND m.source_category = s.osm_tag
LEFT JOIN category_mappings k
  ON k.source = 'osm' AND k.source_category = split_part(s.osm_tag, '=', 1) || '=*'
WHERE s.area = :'area'
  AND onqi_in_area(:'area', s.geom, coalesce(s.postcode, s.postcode_inferred));

-- 2. Abbinamento: record OSM già collegati in import precedenti...
CREATE TEMP TABLE matches ON COMMIT DROP AS
SELECT c.source_id, ps.place_id
FROM candidates c
JOIN place_sources ps ON ps.source = 'osm' AND ps.source_id = c.source_id;

-- ...poi i nuovi: place entro 60 m con nome simile e non ancora legato a OSM.
-- Il punteggio cala con la distanza (-0.1 ogni 15 m). Accoppiamento 1:1 greedy.
CREATE TEMP TABLE pairs ON COMMIT DROP AS
SELECT c.source_id, p.id AS place_id,
       onqi_name_score(c.name, p.name) - ST_Distance(c.geom, p.geom) / 150 AS score
FROM candidates c
JOIN places p ON ST_DWithin(p.geom, c.geom, 60)
WHERE NOT EXISTS (SELECT 1 FROM matches mm WHERE mm.source_id = c.source_id)
  AND NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.place_id = p.id AND ps.source = 'osm')
  AND onqi_categories_compatible(c.category_id, p.category_id);
DELETE FROM pairs WHERE score < 0.45;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pairs ORDER BY score DESC LOOP
    IF NOT EXISTS (SELECT 1 FROM matches WHERE source_id = r.source_id OR place_id = r.place_id) THEN
      INSERT INTO matches VALUES (r.source_id, r.place_id);
    END IF;
  END LOOP;
END $$;

-- 3. Arricchisce i place abbinati. OSM è curato a mano: vince su categoria e,
--    quando il nome attuale è una ragione sociale, anche sul nome.
UPDATE places p
SET name        = CASE WHEN onqi_is_legal_name(p.name) THEN c.name ELSE p.name END,
    category_id = c.category_id,
    phone       = coalesce(p.phone, c.t->>'phone', c.t->>'contact:phone'),
    website     = coalesce(p.website, c.t->>'website', c.t->>'contact:website'),
    vat_number  = coalesce(p.vat_number, onqi_vat_normalize(c.t->>'ref:vatin')),
    email       = coalesce(p.email, c.t->>'email', c.t->>'contact:email'),
    status      = CASE WHEN p.status = 'unverified' THEN 'active' ELSE p.status END,
    updated_at  = now()
FROM matches m
JOIN candidates c ON c.source_id = m.source_id
WHERE p.id = m.place_id;

-- 4. Record OSM senza corrispondenza: nuovi place.
WITH new AS MATERIALIZED (
  SELECT gen_random_uuid() AS place_id, c.*
  FROM candidates c
  WHERE NOT EXISTS (SELECT 1 FROM matches m WHERE m.source_id = c.source_id)
), ins AS (
  INSERT INTO places (id, name, category_id, geom, address, postcode, city, phone, website, email,
                      brand, vat_number, status)
  SELECT place_id, name, category_id, geom,
         nullif(concat_ws(', ', t->>'addr:street', t->>'addr:housenumber'), ''),
         coalesce(postcode, postcode_inferred), coalesce(t->>'addr:city', 'Milano'),
         coalesce(t->>'phone', t->>'contact:phone'), coalesce(t->>'website', t->>'contact:website'),
         coalesce(t->>'email', t->>'contact:email'), t->>'brand', onqi_vat_normalize(t->>'ref:vatin'), 'active'
  FROM new
)
INSERT INTO matches SELECT source_id, place_id FROM new;

-- Provenienza per tutti i record OSM dell'area (nuovi e abbinati).
INSERT INTO place_sources (source, source_id, place_id, raw)
SELECT 'osm', m.source_id, m.place_id, c.t
FROM matches m JOIN candidates c ON c.source_id = m.source_id
ON CONFLICT (source, source_id) DO UPDATE SET raw = excluded.raw, fetched_at = now();

-- 5. Orari OSM (rigenerati a ogni import), tranne dove sono stati inseriti a mano.
DELETE FROM opening_hours o USING matches m WHERE o.place_id = m.place_id AND o.source = 'osm';
INSERT INTO opening_hours (place_id, weekday, opens, closes, source)
SELECT m.place_id, h.weekday, h.opens, h.closes, 'osm'
FROM matches m
JOIN candidates c ON c.source_id = m.source_id
CROSS JOIN LATERAL osm_opening_hours(c.t->>'opening_hours') h
WHERE NOT EXISTS (SELECT 1 FROM opening_hours o WHERE o.place_id = m.place_id AND o.source = 'manual');

-- 6. Esercizio aperto al pubblico o no (vedi db/migrations/007_public_flag.sql).
DO $$ BEGIN PERFORM onqi_refresh_public(); END $$;

COMMIT;
