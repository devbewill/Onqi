-- Abbina gli esercizi comunali di un CAP ai place esistenti e aggiunge quelli
-- mancanti che hanno un'insegna. Da eseguire dopo Overture e OSM.
-- Variabili psql: postcode
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE com ON COMMIT DROP AS
SELECT c.*,
       onqi_street_key(c.via) AS skey,
       substring(c.civico FROM '^\d+')::int AS num,
       coalesce(m.category_id, (SELECT id FROM categories WHERE slug = 'negozi_specializzati')) AS category_id
FROM staging.comune_esercizi c
LEFT JOIN category_mappings m ON m.source = 'comune' AND m.source_category = c.tipo
WHERE c.cap = :'postcode' AND c.geom IS NOT NULL;

-- 1. Collegamenti già fatti in import precedenti.
CREATE TEMP TABLE links ON COMMIT DROP AS
SELECT ps.source_id AS codice, ps.place_id
FROM place_sources ps JOIN com c ON c.codice = ps.source_id
WHERE ps.source = 'comune';

-- 2. Nuovi abbinamenti con place di categorie pubbliche entro 150 m:
--    stesso indirizzo (via + civico) e tipo compatibile, oppure insegna molto
--    simile entro 60 m. Vince l'insegna più simile, poi il più vicino.
CREATE TEMP TABLE pairs ON COMMIT DROP AS
SELECT c.codice, p.id AS place_id,
       (a.street_key = c.skey AND a.civico = c.num) AS same_address,
       onqi_comune_compatible(c.tipo, pc.slug, mc.slug) AS compatible,
       coalesce(onqi_name_score(p.name, c.insegna), 0) AS name_score,
       ST_Distance(p.geom, c.geom) AS dist
FROM com c
JOIN places p ON ST_DWithin(p.geom, c.geom, 150)
JOIN categories pc ON pc.id = p.category_id AND pc.is_public
JOIN categories mc ON mc.id = pc.parent_id
CROSS JOIN LATERAL onqi_address_parts(p.address) a
WHERE NOT EXISTS (SELECT 1 FROM links l WHERE l.codice = c.codice)
  AND NOT EXISTS (SELECT 1 FROM place_sources ps WHERE ps.place_id = p.id AND ps.source = 'comune');
DELETE FROM pairs
WHERE NOT ((coalesce(same_address, false) AND compatible) OR (name_score >= 0.6 AND dist <= 60));

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM pairs
    ORDER BY coalesce(same_address, false)::int + name_score - dist / 500 DESC
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
