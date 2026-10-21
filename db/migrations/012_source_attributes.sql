-- Dettagli extra ricavati automaticamente dalle fonti (tag OSM). Vivono in
-- source_attributes, colonna alimentata dagli import: non sono modifiche
-- manuali e il dato confermato a mano (places.attributes) ha sempre la
-- precedenza, in app e in ogni parser futuro.
ALTER TABLE places ADD COLUMN source_attributes jsonb NOT NULL DEFAULT '{}';

-- Da tag OSM a chiavi curate (stesse chiavi usate in places.attributes).
CREATE FUNCTION onqi_osm_attributes(t jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'description',      t->>'description',
    'cuisine',          t->>'cuisine',
    'wheelchair',       t->>'wheelchair',
    'outdoor_seating',  t->>'outdoor_seating',
    'takeaway',         t->>'takeaway',
    'delivery',         t->>'delivery',
    'wifi',             CASE WHEN t->>'internet_access' IS NOT NULL
                             THEN CASE WHEN t->>'internet_access' = 'no' THEN 'no' ELSE 'yes' END END,
    'payment_cards',    coalesce(
                          CASE WHEN t ? 'payment:credit_cards' THEN t->>'payment:credit_cards' END,
                          CASE WHEN EXISTS (SELECT 1 FROM jsonb_each_text(t) e
                                             WHERE e.key IN ('payment:visa', 'payment:mastercard',
                                                             'payment:maestro', 'payment:contactless',
                                                             'payment:cards')
                                               AND e.value = 'yes') THEN 'yes' END),
    'diet_vegetarian',  t->>'diet:vegetarian',
    'diet_vegan',       t->>'diet:vegan',
    'diet_gluten_free', t->>'diet:gluten_free'
  ))
$$;

-- Riempi i place già importati con l'ultimo payload OSM salvato.
UPDATE places p
SET source_attributes = onqi_osm_attributes(ps.raw)
FROM place_sources ps
WHERE ps.place_id = p.id AND ps.source = 'osm';
