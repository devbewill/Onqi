-- Un place è aperto in un dato istante? NULL se non conosciamo gli orari.
-- Gli orari sono in ora locale di Milano; una fascia con closes < opens
-- prosegue dopo la mezzanotte e va controllata anche il giorno successivo.
CREATE FUNCTION onqi_is_open(p_place uuid, p_at timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE sql STABLE AS $$
  WITH local AS (
    SELECT extract(isodow FROM p_at AT TIME ZONE 'Europe/Rome')::smallint AS dow,
           (p_at AT TIME ZONE 'Europe/Rome')::time AS t
  )
  SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM opening_hours WHERE place_id = p_place) THEN NULL
    ELSE EXISTS (
      SELECT 1
      FROM opening_hours h, local l
      WHERE h.place_id = p_place
        AND (h.valid_from IS NULL OR (p_at AT TIME ZONE 'Europe/Rome')::date >= h.valid_from)
        AND (h.valid_to   IS NULL OR (p_at AT TIME ZONE 'Europe/Rome')::date <= h.valid_to)
        AND (
          -- fascia del giorno corrente
          (h.weekday = l.dow AND l.t >= h.opens AND (h.closes <= h.opens OR l.t < h.closes))
          -- coda dopo mezzanotte della fascia di ieri
          OR (h.weekday = (l.dow + 5) % 7 + 1 AND h.closes < h.opens AND l.t < h.closes)
        )
    )
  END
$$;
