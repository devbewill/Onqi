-- Ricerca per nome e partita IVA.

-- Le espressioni degli indici girano con search_path ristretto (pg_catalog):
-- unaccent va qualificato con lo schema.
CREATE OR REPLACE FUNCTION onqi_norm_name(n text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(regexp_replace(
    lower(public.unaccent('public.unaccent'::regdictionary, coalesce(n, ''))),
    '\m(s\.?r\.?l\.?s?|s\.?n\.?c\.?|s\.?a\.?s\.?|s\.?p\.?a\.?|di\s+\S+\s+\S+\s*&\s*c\.?|& ?c\.?)', ' ', 'g'),
    '[^a-z0-9]+', ' ', 'g'))
$$;

-- Ricerca senza accenti e maiuscole: indice trigram sul nome normalizzato.
CREATE INDEX places_norm_name_trgm ON places USING gin (public.onqi_norm_name(name) gin_trgm_ops);

ALTER TABLE places ADD COLUMN vat_number text;

-- Partita IVA italiana valida (11 cifre + cifra di controllo). Accetta il prefisso IT.
CREATE FUNCTION onqi_vat_normalize(v text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN n ~ '^\d{11}$' AND (
      (SELECT sum(CASE WHEN i % 2 = 1 THEN d ELSE (d * 2) / 10 + (d * 2) % 10 END)
         FROM (SELECT i, substr(n, i, 1)::int AS d FROM generate_series(1, 10) i) x)
      + substr(n, 11, 1)::int) % 10 = 0
    THEN n
  END
  FROM (SELECT regexp_replace(upper(coalesce(v, '')), '^IT|[^0-9A-Z]', '', 'g') AS n) x
$$;
