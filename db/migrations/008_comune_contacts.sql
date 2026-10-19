-- Elenchi ufficiali del Comune di Milano (esercizi di vicinato e pubblici
-- esercizi) e contatti aggiuntivi (email, social).

-- ---------------------------------------------------------------------------
-- Contatti
-- ---------------------------------------------------------------------------
ALTER TABLE places ADD COLUMN email text, ADD COLUMN socials text[];
ALTER TABLE staging.overture_places ADD COLUMN email text, ADD COLUMN socials text[];

-- ---------------------------------------------------------------------------
-- Indirizzi confrontabili tra fonti
-- ---------------------------------------------------------------------------
-- Chiave della via: parole significative in ordine alfabetico, senza tipo di
-- strada né articoli. "Via PONTI ETTORE" e "Via Ettore Ponti" -> "ettore ponti";
-- "Ripa PORTA TICINESE (DI)" e "Ripa di Porta Ticinese" -> "porta ticinese".
CREATE FUNCTION onqi_street_key(s text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT nullif(string_agg(DISTINCT w, ' ' ORDER BY w), '')
  FROM unnest(regexp_split_to_array(
         lower(public.unaccent('public.unaccent'::regdictionary, coalesce(s, ''))), '[^a-z0-9]+')) AS w
  WHERE w <> ''
    AND w NOT IN (
      'via', 'viale', 'vle', 'v', 'piazza', 'piazzale', 'piazzetta', 'p', 'pza', 'pzza', 'pzle', 'ple',
      'corso', 'cso', 'c', 'largo', 'lgo', 'vicolo', 'strada', 'alzaia', 'ripa', 'privata', 'pvt',
      'galleria', 'passaggio', 'bastioni', 'foro', 'ponte', 'cavalcavia', 'rotonda', 'salita',
      'borgo', 'contrada', 'localita', 'sottopassaggio', 'milano', 'mi',
      'di', 'de', 'del', 'della', 'dello', 'dei', 'degli', 'delle', 'd', 'l', 'la', 'il', 'lo', 'le')
$$;

-- Separa "Via Ettore Ponti, 35/A" in chiave della via e numero civico.
CREATE FUNCTION onqi_address_parts(a text, OUT street_key text, OUT civico int)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT onqi_street_key(m[1]),
         CASE WHEN m[2]::int BETWEEN 1 AND 1999 THEN m[2]::int END  -- 20143 è un CAP, non un civico
  FROM (SELECT regexp_match(coalesce(a, ''), '^(.*?)[\s,]+(?:n\.?\s*)?(\d{1,5})\s*[a-zA-Z]?(?:\s*/\s*\w+)?\s*$') AS m) x
$$;

-- ---------------------------------------------------------------------------
-- Staging Comune (tutta la città, sostituita a ogni import)
-- ---------------------------------------------------------------------------
CREATE TABLE staging.comune_esercizi (
  codice     text PRIMARY KEY,
  dataset    text NOT NULL,   -- vicinato | pubblico_esercizio | pubblico_esercizio_fuori_piano
  via        text,
  civico     text,
  cap        text,
  insegna    text,
  tipo       text,            -- chiave per category_mappings source 'comune'
  ateco      text,
  superficie double precision,
  lon        double precision,
  lat        double precision,
  geom       geography(Point, 4326)
    GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED
);
CREATE INDEX comune_esercizi_geom_idx ON staging.comune_esercizi USING gist (geom);
CREATE INDEX comune_esercizi_cap_idx ON staging.comune_esercizi (cap);

-- Un esercizio comunale di questo tipo può essere un place di questa categoria?
-- Allo stesso civico convivono più attività: senza questo controllo un
-- parrucchiere (artigiano, non censito qui) verrebbe abbinato al negozio accanto.
CREATE FUNCTION onqi_comune_compatible(tipo text, category_slug text, macro_slug text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN tipo LIKE 'pe:%' THEN
      macro_slug IN ('food_drink', 'nightlife') OR category_slug IN ('panetteria_pasticceria', 'enoteca', 'hotel')
    WHEN tipo = 'vicinato:alimentare' THEN
      macro_slug IN ('grocery', 'food_drink')
    WHEN tipo = 'vicinato:misto' THEN
      macro_slug IN ('grocery', 'shopping', 'food_drink')
    WHEN tipo = 'vicinato:monopolio' THEN
      category_slug IN ('tabacchi_edicola', 'bar', 'caffetteria', 'supermercato')
    WHEN tipo = 'vicinato:non alimentare' THEN
      macro_slug IN ('shopping', 'health', 'culture')
      OR category_slug IN ('telefonia', 'profumeria', 'copisteria', 'agenzia_viaggi', 'noleggio')
    ELSE true
  END
$$;

-- Tipo comunale -> categoria Onqi (usata per gli esercizi non presenti nelle altre fonti).
-- Pubblici esercizi: lettera della tipologia storica; vicinato: settore merceologico.
INSERT INTO category_mappings (source, source_category, category_id)
SELECT 'comune', v.src, c.id
FROM (VALUES
  ('pe:a', 'ristorante'), ('pe:b', 'ristorante'), ('pe:d', 'ristorante'),
  ('pe:c', 'street_food'), ('pe:e', 'bar'), ('pe:f', 'bar'), ('pe:g', 'bar'),
  ('pe:h', 'bar'), ('pe:i', 'discoteca'), ('pe:?', 'bar'),
  ('vicinato:alimentare', 'alimentari'), ('vicinato:misto', 'supermercato'),
  ('vicinato:non alimentare', 'negozi_specializzati'), ('vicinato:monopolio', 'tabacchi_edicola'),
  ('vicinato:?', 'negozi_specializzati')
) AS v(src, slug)
JOIN categories c ON c.slug = v.slug;
