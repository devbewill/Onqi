-- Abbina gli esercizi comunali di un'area ai place esistenti e aggiunge quelli
-- mancanti che hanno un'insegna. Da eseguire dopo Overture e OSM.
-- Variabili psql: area (vedi import_areas)
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE com ON COMMIT DROP AS
SELECT c.*,
       onqi_street_key(c.via) AS skey,
       substring(c.civico FROM '^\d+')::int AS num,
       coalesce(m.category_id, (SELECT id FROM categories WHERE slug = 'negozi_specializzati')) AS category_id
FROM staging.comune_esercizi c
LEFT JOIN category_mappings m ON m.source = 'comune' AND m.source_category = c.tipo
WHERE c.geom IS NOT NULL AND onqi_in_area(:'area', c.geom, c.cap);

-- 1. Collegamenti già fatti in import precedenti.
CREATE TEMP TABLE links ON COMMIT DROP AS
SELECT ps.source_id AS codice, ps.place_id
FROM place_sources ps JOIN com c ON c.codice = ps.source_id
WHERE ps.source = 'comune';

-- 2. Nuovi abbinamenti con place di categorie pubbliche: stesso indirizzo
--    (via + civico, entro 150 m) e tipo compatibile, oppure insegna molto simile
--    entro 60 m. Vince l'insegna più simile, poi il più vicino.
--    Chiavi d'indirizzo calcolate una volta sola per place: con tutta Milano le
--    coppie "entro 150 m" sarebbero milioni.
CREATE TEMP TABLE pa ON COMMIT DROP AS
SELECT p.id, p.name, p.geom, a.street_key, a.civico, pc.slug AS category_slug, mc.slug AS macro_slug
FROM places p
JOIN categories pc ON pc.id = p.category_id AND pc.is_public
JOIN categories mc ON mc.id = pc.parent_id
CROSS JOIN LATERAL onqi_address_parts(p.address) a
WHERE ST_DWithin(p.geom, (SELECT ST_Collect(geom::geometry)::geography FROM com), 200)
  AND NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.place_id = p.id AND ps.source = 'comune');
CREATE INDEX ON pa USING gist (geom);
CREATE INDEX ON pa (street_key, civico);

CREATE TEMP TABLE pairs ON COMMIT DROP AS
WITH free AS (
  SELECT c.* FROM com c WHERE NOT EXISTS (SELECT 1 FROM links l WHERE l.codice = c.codice)
), cand AS (
  SELECT f.codice, f.insegna, f.tipo, f.geom AS cgeom, pa.*, true AS same_address
  FROM free f
  JOIN pa ON pa.street_key = f.skey AND pa.civico = f.num AND ST_DWithin(pa.geom, f.geom, 150)
  UNION ALL
  SELECT f.codice, f.insegna, f.tipo, f.geom, pa.*, false
  FROM free f
  JOIN pa ON f.insegna IS NOT NULL AND ST_DWithin(pa.geom, f.geom, 60)
          AND (pa.street_key IS DISTINCT FROM f.skey OR pa.civico IS DISTINCT FROM f.num)
)
SELECT codice, id AS place_id, same_address,
       onqi_comune_compatible(tipo, category_slug, macro_slug) AS compatible,
       coalesce(onqi_name_score(name, insegna), 0) AS name_score,
       ST_Distance(geom, cgeom) AS dist
FROM cand;
DELETE FROM pairs
WHERE NOT ((same_address AND compatible) OR (name_score >= 0.6 AND dist <= 60));

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM pairs
    ORDER BY same_address::int + name_score - dist / 500 DESC
  LOOP
    IF NOT EXISTS (SELECT 1 FROM links WHERE codice = r.codice OR place_id = r.place_id) THEN
      INSERT INTO links VALUES (r.codice, r.place_id);
    END IF;
  END LOOP;
END $$;

-- 3. Esercizi con insegna senza corrispondenza: nuovi place.
WITH new AS MATERIALIZED (
  SELECT gen_random_uuid() AS place_id, c.*
  FROM com c
  WHERE c.insegna IS NOT NULL AND length(c.insegna) >= 3
    AND NOT EXISTS (SELECT 1 FROM links l WHERE l.codice = c.codice)
), ins AS (
  INSERT INTO places (id, name, category_id, geom, address, postcode, city, status)
  SELECT place_id, initcap(insegna), category_id, geom,
         initcap(via) || ' ' || civico, cap, 'Milano', 'active'
  FROM new
)
INSERT INTO links SELECT codice, place_id FROM new;

-- 4. Provenienza: un place collegato è un esercizio censito dal Comune.
INSERT INTO place_sources (source, source_id, place_id, raw)
SELECT 'comune', c.codice, l.place_id,
       jsonb_build_object('dataset', c.dataset, 'via', c.via, 'civico', c.civico, 'insegna', c.insegna,
                          'tipo', c.tipo, 'ateco', c.ateco, 'superficie', c.superficie)
FROM links l JOIN com c ON c.codice = l.codice
ON CONFLICT (source, source_id) DO UPDATE SET raw = excluded.raw, fetched_at = now();

-- Confermato dal Comune; se il nome è una ragione sociale, meglio l'insegna.
UPDATE places p
SET status     = CASE WHEN p.status = 'unverified' THEN 'active' ELSE p.status END,
    name       = CASE WHEN c.insegna IS NOT NULL AND length(c.insegna) >= 3
                           AND p.name ~* '\m(s\.?r\.?l|s\.?n\.?c|s\.?a\.?s|s\.?p\.?a)\M'
                      THEN initcap(c.insegna) ELSE p.name END,
    updated_at = now()
FROM links l JOIN com c ON c.codice = l.codice
WHERE p.id = l.place_id;

-- 5. Esercizio aperto al pubblico o no (una conferma comunale annulla "sede_legale").
DO $$ BEGIN PERFORM onqi_refresh_public(); END $$;

COMMIT;
