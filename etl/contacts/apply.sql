-- Applica contatti ricercati a mano dai CSV di etl/contacts.
-- La tabella contacts_input deve essere creata e popolata dallo script chiamante.
\set ON_ERROR_STOP on

-- Normalizza un handle/URL di un social nel dominio canonico https://www.
CREATE OR REPLACE FUNCTION onqi_social_url(platform text, raw text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN raw IS NULL THEN NULL
    ELSE regexp_replace(
           'https://www.' || platform || '.com/' ||
           regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(raw, '^https?://', '', 'i'),
                   '^www\.', '', 'i'),
                 '^[a-z0-9-]+\.' || platform || '\.com/', '', 'i'),
               '^' || platform || '\.com/', '', 'i'),
             '^@', ''),
           '/+$', '')
  END
$$;

DO $$
DECLARE
  r record;
  v_parts record;
  v_matched uuid[];
  v_scores real[];
  v_target_website text;
  v_target_socials text[];
  v_rec record;
  v_needs_website boolean;
  v_needs_socials boolean;
  v_updated int := 0;
  v_already int := 0;
  v_ambiguous int := 0;
  v_notfound int := 0;
BEGIN
  FOR r IN SELECT name, address, instagram, facebook, website FROM contacts_input LOOP
    SELECT * INTO v_parts FROM onqi_address_parts(r.address);
    IF v_parts.civico IS NULL THEN
      v_notfound := v_notfound + 1;
      CONTINUE;
    END IF;

    SELECT array_agg(id ORDER BY score DESC), array_agg(score ORDER BY score DESC)
    INTO v_matched, v_scores
    FROM (
      SELECT p.id, onqi_name_score(r.name, p.name) AS score
      FROM places p
      WHERE (onqi_address_parts(p.address)).civico = v_parts.civico
        AND (onqi_address_parts(p.address)).street_key = v_parts.street_key
        AND onqi_name_score(r.name, p.name) >= 0.45
    ) c;

    IF v_matched IS NULL THEN
      v_notfound := v_notfound + 1;
      CONTINUE;
    END IF;

    IF array_length(v_matched, 1) > 1 THEN
      v_ambiguous := v_ambiguous + 1;
      CONTINUE;
    END IF;

    -- Sito: forza https assoluto.
    v_target_website := nullif(btrim(r.website), '');
    IF v_target_website IS NOT NULL THEN
      v_target_website := regexp_replace(v_target_website, '^http://', 'https://', 'i');
      IF v_target_website !~* '^https?://' THEN
        v_target_website := 'https://' || v_target_website;
      END IF;
    END IF;

    -- Social target: solo Instagram e Facebook, normalizzati e nell'ordine CSV.
    SELECT array_agg(url ORDER BY ord)
    INTO v_target_socials
    FROM (
      SELECT onqi_social_url('instagram', nullif(btrim(r.instagram), '')) AS url, 1 AS ord
      UNION ALL
      SELECT onqi_social_url('facebook', nullif(btrim(r.facebook), '')) AS url, 2 AS ord
    ) x
    WHERE url IS NOT NULL;

    SELECT * INTO v_rec FROM places WHERE id = v_matched[1];

    v_needs_website := v_target_website IS NOT NULL AND v_rec.website IS NULL;
    v_needs_socials := v_target_socials IS NOT NULL
                       AND NOT (
                         SELECT coalesce(bool_and(t <@ e), false)
                         FROM (
                           SELECT array_agg(DISTINCT regexp_replace(u, '/+$', '')) AS t
                           FROM unnest(v_target_socials) u
                         ) tgt,
                         (
                           SELECT array_agg(DISTINCT regexp_replace(u, '/+$', '')) AS e
                           FROM unnest(coalesce(v_rec.socials, '{}'::text[])) u
                         ) ex
                       );

    IF NOT v_needs_website AND NOT v_needs_socials THEN
      v_already := v_already + 1;
      CONTINUE;
    END IF;

    UPDATE places
    SET website = CASE WHEN v_needs_website THEN v_target_website ELSE website END,
        socials = CASE WHEN v_needs_socials THEN
                       (SELECT coalesce(array_agg(DISTINCT regexp_replace(x, '/+$', '')), '{}')
                        FROM unnest(coalesce(socials, '{}'::text[]) || v_target_socials) x)
                     ELSE socials END,
        locked_fields = (SELECT coalesce(array_agg(DISTINCT f), '{}')
                         FROM unnest(
                           locked_fields
                           || CASE WHEN v_needs_website THEN ARRAY['website'] ELSE '{}'::text[] END
                           || CASE WHEN v_needs_socials THEN ARRAY['socials'] ELSE '{}'::text[] END
                         ) f),
        updated_at = now()
    WHERE id = v_matched[1];

    v_updated := v_updated + 1;
  END LOOP;

  RAISE NOTICE 'Summary: updated=%, already-set=%, ambiguous=%, not-found=%', v_updated, v_already, v_ambiguous, v_notfound;
END $$;
