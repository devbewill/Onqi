-- OpenStreetMap: staging, categorie più fini, normalizzazione nomi, parser orari.
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE TABLE staging.osm_places (
  area              text NOT NULL,
  osm_type          text NOT NULL,   -- node | way | relation
  osm_id            bigint NOT NULL,
  name              text NOT NULL,
  osm_tag           text NOT NULL,   -- tag principale, es. 'amenity=bar'
  tags              text NOT NULL,   -- JSON con tutti i tag
  lon               double precision NOT NULL,
  lat               double precision NOT NULL,
  postcode          text,            -- addr:postcode
  postcode_inferred text,
  geom              geography(Point, 4326)
    GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography) STORED,
  PRIMARY KEY (area, osm_type, osm_id)
);
CREATE INDEX osm_places_geom_idx ON staging.osm_places USING gist (geom);

-- ---------------------------------------------------------------------------
-- Categorie che OSM distingue e Overture no
-- ---------------------------------------------------------------------------
INSERT INTO categories (slug, name_it, parent_id)
SELECT v.slug, v.name_it, p.id
FROM (VALUES
  ('gelateria',              'Gelaterie',                      'food_drink'),
  ('panetteria_pasticceria', 'Panetterie e pasticcerie',       'grocery'),
  ('enoteca',                'Enoteche',                       'grocery'),
  ('tabacchi_edicola',       'Tabacchi ed edicole',            'shopping'),
  ('gioielleria',            'Gioiellerie e orologerie',       'shopping'),
  ('ottica',                 'Ottici e apparecchi acustici',   'health'),
  ('sartoria_riparazioni',   'Sartorie, calzolai e riparazioni','services')
) AS v(slug, name_it, parent)
JOIN categories p ON p.slug = v.parent;

INSERT INTO category_mappings (source, source_category, category_id)
SELECT 'osm', v.src, c.id
FROM (VALUES
  ('amenity=restaurant', 'ristorante'), ('amenity=cafe', 'caffetteria'),
  ('amenity=fast_food', 'street_food'), ('amenity=food_court', 'street_food'),
  ('amenity=bar', 'bar'), ('amenity=pub', 'bar'), ('amenity=biergarten', 'bar'),
  ('amenity=ice_cream', 'gelateria'),
  ('amenity=pharmacy', 'farmacia'), ('amenity=nightclub', 'discoteca'),
  ('amenity=cinema', 'cinema'), ('amenity=theatre', 'teatro'),
  ('amenity=arts_centre', 'spazi_eventi'), ('amenity=marketplace', 'mercato'),
  ('amenity=car_rental', 'noleggio'), ('amenity=casino', 'sala_giochi'),
  ('shop=clothes', 'abbigliamento'), ('shop=shoes', 'abbigliamento'), ('shop=bag', 'abbigliamento'),
  ('shop=fashion_accessories', 'abbigliamento'), ('shop=leather', 'abbigliamento'),
  ('shop=boutique', 'abbigliamento'), ('shop=baby_goods', 'abbigliamento'),
  ('shop=jewelry', 'gioielleria'), ('shop=watches', 'gioielleria'),
  ('shop=hairdresser', 'parrucchiere_estetica'), ('shop=beauty', 'parrucchiere_estetica'),
  ('shop=tattoo', 'parrucchiere_estetica'), ('shop=piercing', 'parrucchiere_estetica'),
  ('shop=massage', 'benessere'),
  ('shop=bakery', 'panetteria_pasticceria'), ('shop=pastry', 'panetteria_pasticceria'),
  ('shop=confectionery', 'panetteria_pasticceria'), ('shop=chocolate', 'panetteria_pasticceria'),
  ('shop=convenience', 'supermercato'), ('shop=supermarket', 'supermercato'),
  ('shop=general', 'supermercato'), ('shop=variety_store', 'supermercato'),
  ('shop=butcher', 'alimentari'), ('shop=deli', 'alimentari'), ('shop=greengrocer', 'alimentari'),
  ('shop=cheese', 'alimentari'), ('shop=seafood', 'alimentari'), ('shop=coffee', 'alimentari'),
  ('shop=tea', 'alimentari'), ('shop=pasta', 'alimentari'), ('shop=food', 'alimentari'),
  ('shop=wine', 'enoteca'), ('shop=alcohol', 'enoteca'),
  ('shop=optician', 'ottica'), ('shop=hearing_aids', 'ottica'),
  ('shop=medical_supply', 'farmacia'), ('shop=orthopedics', 'farmacia'),
  ('shop=furniture', 'casa_ferramenta'), ('shop=houseware', 'casa_ferramenta'),
  ('shop=interior_decoration', 'casa_ferramenta'), ('shop=lighting', 'casa_ferramenta'),
  ('shop=bed', 'casa_ferramenta'), ('shop=bathroom_furnishing', 'casa_ferramenta'),
  ('shop=kitchen', 'casa_ferramenta'), ('shop=hardware', 'casa_ferramenta'),
  ('shop=doityourself', 'casa_ferramenta'), ('shop=paint', 'casa_ferramenta'),
  ('shop=doors', 'casa_ferramenta'), ('shop=garden_centre', 'casa_ferramenta'),
  ('shop=carpet', 'casa_ferramenta'), ('shop=curtain', 'casa_ferramenta'),
  ('shop=household_linen', 'casa_ferramenta'), ('shop=tiles', 'casa_ferramenta'),
  ('shop=flooring', 'casa_ferramenta'), ('shop=window_blind', 'casa_ferramenta'),
  ('shop=tableware', 'casa_ferramenta'), ('shop=cutlery', 'casa_ferramenta'),
  ('shop=household', 'casa_ferramenta'), ('shop=appliance', 'casa_ferramenta'),
  ('shop=electrical', 'casa_ferramenta'),
  ('shop=books', 'libri_musica'), ('shop=music', 'libri_musica'),
  ('shop=musical_instrument', 'libri_musica'), ('shop=anime', 'libri_musica'),
  ('shop=car_repair', 'officina'), ('shop=tyres', 'officina'), ('shop=car_parts', 'officina'),
  ('shop=car', 'officina'), ('shop=motorcycle', 'officina'), ('shop=motorcycle_repair', 'officina'),
  ('shop=laundry', 'lavanderia'), ('shop=dry_cleaning', 'lavanderia'),
  ('shop=florist', 'fiori_regali'), ('shop=gift', 'fiori_regali'), ('shop=party', 'fiori_regali'),
  ('shop=travel_agency', 'agenzia_viaggi'),
  ('shop=perfumery', 'profumeria'), ('shop=cosmetics', 'profumeria'),
  ('shop=chemist', 'profumeria'), ('shop=herbalist', 'profumeria'),
  ('shop=stationery', 'cartoleria'), ('shop=printer_ink', 'cartoleria'),
  ('shop=tobacco', 'tabacchi_edicola'), ('shop=newsagent', 'tabacchi_edicola'),
  ('shop=kiosk', 'tabacchi_edicola'), ('shop=e-cigarette', 'tabacchi_edicola'),
  ('shop=sports', 'articoli_sportivi'), ('shop=bicycle', 'articoli_sportivi'),
  ('shop=outdoor', 'articoli_sportivi'), ('shop=fishing', 'articoli_sportivi'),
  ('shop=copyshop', 'copisteria'), ('shop=printing', 'copisteria'), ('shop=photo', 'copisteria'),
  ('shop=tailor', 'sartoria_riparazioni'), ('shop=shoe_repair', 'sartoria_riparazioni'),
  ('shop=repair', 'sartoria_riparazioni'), ('shop=locksmith', 'sartoria_riparazioni'),
  ('shop=pet', 'animali_negozio'), ('shop=pet_grooming', 'servizi_animali'),
  ('shop=antiques', 'usato'), ('shop=second_hand', 'usato'),
  ('shop=telecommunication', 'telefonia'), ('shop=mobile_phone', 'telefonia'),
  ('shop=mobile_phone_accessories', 'telefonia'),
  ('shop=electronics', 'elettronica'), ('shop=computer', 'elettronica'), ('shop=hifi', 'elettronica'),
  ('shop=camera', 'elettronica'), ('shop=video_games', 'elettronica'),
  ('shop=vacuum_cleaner', 'elettronica'),
  ('shop=toys', 'hobby_giochi'), ('shop=games', 'hobby_giochi'), ('shop=model', 'hobby_giochi'),
  ('shop=craft', 'hobby_giochi'), ('shop=pottery', 'hobby_giochi'), ('shop=frame', 'hobby_giochi'),
  ('shop=fabric', 'hobby_giochi'), ('shop=sewing', 'hobby_giochi'), ('shop=haberdashery', 'hobby_giochi'),
  ('shop=collector', 'hobby_giochi'),
  ('shop=art', 'galleria'),
  ('shop=department_store', 'grandi_magazzini'), ('shop=mall', 'grandi_magazzini'),
  ('shop=erotic', 'negozi_specializzati'), ('shop=cannabis', 'negozi_specializzati'),
  ('shop=military_surplus', 'negozi_specializzati'), ('shop=religion', 'negozi_specializzati'),
  ('craft=electronics_repair', 'sartoria_riparazioni'), ('craft=shoemaker', 'sartoria_riparazioni'),
  ('craft=dressmaker', 'sartoria_riparazioni'), ('craft=tailor', 'sartoria_riparazioni'),
  ('craft=watchmaker', 'sartoria_riparazioni'), ('craft=upholsterer', 'sartoria_riparazioni'),
  ('craft=key_cutter', 'sartoria_riparazioni'), ('craft=locksmith', 'sartoria_riparazioni'),
  ('craft=bag_repair', 'sartoria_riparazioni'),
  ('craft=jeweller', 'gioielleria'), ('craft=goldsmith', 'gioielleria'),
  ('craft=winery', 'birrifici_cantine'), ('craft=brewery', 'birrifici_cantine'),
  ('craft=confectionery', 'panetteria_pasticceria'),
  ('leisure=fitness_centre', 'palestra'), ('leisure=sports_centre', 'palestra'),
  ('leisure=dance', 'palestra'), ('leisure=swimming_pool', 'piscina'),
  ('leisure=escape_game', 'sala_giochi'), ('leisure=amusement_arcade', 'sala_giochi'),
  ('tourism=hotel', 'hotel'), ('tourism=hostel', 'hotel'), ('tourism=guest_house', 'bnb'),
  ('tourism=museum', 'museo'), ('tourism=gallery', 'galleria')
) AS v(src, slug)
JOIN categories c ON c.slug = v.slug;

-- ---------------------------------------------------------------------------
-- Nome normalizzato per confrontare le fonti: minuscolo, senza accenti,
-- punteggiatura e forme societarie.
-- ---------------------------------------------------------------------------
CREATE FUNCTION onqi_norm_name(n text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(regexp_replace(
    lower(unaccent('unaccent', coalesce(n, ''))),
    '\m(s\.?r\.?l\.?s?|s\.?n\.?c\.?|s\.?a\.?s\.?|s\.?p\.?a\.?|di\s+\S+\s+\S+\s*&\s*c\.?|& ?c\.?)', ' ', 'g'),
    '[^a-z0-9]+', ' ', 'g'))
$$;

-- Nome "essenziale": senza articoli e parole generiche (bar, ristorante, milano...),
-- che altrimenti farebbero sembrare simili attività diverse.
CREATE FUNCTION onqi_core_name(n text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT coalesce(nullif(btrim(regexp_replace(regexp_replace(onqi_norm_name(n),
    '\m(il|lo|la|i|gli|le|l|un|una|di|da|del|dello|della|dei|degli|delle|e|ed|and|the|al|alla|in'
    '|milano|milan|navigli|naviglio|bar|cafe|caffe|caffetteria|ristorante|restaurant|trattoria'
    '|osteria|pizzeria|pasticceria|panificio|panetteria|enoteca|cantina|gelateria|parrucchiere'
    '|parrucchieri|hair|salon|studio|negozio|shop|store|farmacia|hotel|tabacchi|lounge|cocktail'
    '|pub|spa|sas|snc|srl|c)\M', ' ', 'g'),
    '\s+', ' ', 'g')), ''), onqi_norm_name(n))
$$;

-- Somiglianza tra due nomi (0-1): parole intere e confronto senza spazi
-- ("Na 'Ranita" = "Naranita").
CREATE FUNCTION onqi_name_score(a text, b text) RETURNS real
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT greatest(similarity(ca, cb), strict_word_similarity(ca, cb), strict_word_similarity(cb, ca),
                  similarity(replace(ca, ' ', ''), replace(cb, ' ', '')))
  FROM (SELECT onqi_core_name(a) AS ca, onqi_core_name(b) AS cb) x
$$;

-- Vero se il nome sembra una ragione sociale più che un'insegna.
CREATE FUNCTION onqi_is_legal_name(n text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT n ~* '\m(s\.?r\.?l|s\.?n\.?c|s\.?a\.?s|s\.?p\.?a)\M' OR n = upper(n)
$$;

-- ---------------------------------------------------------------------------
-- Parser del tag OSM opening_hours (sottoinsieme comune della sintassi).
-- Supporta: 24/7; giorni e intervalli anche a cavallo (Su-Mo); più fasce
-- (10:00-13:00,15:00-19:00); off/closed; regole aggiuntive separate da virgola;
-- PH e date specifiche vengono ignorate. Se la stringa contiene altro non
-- restituisce nulla, per non salvare orari sbagliati.
-- ---------------------------------------------------------------------------
CREATE FUNCTION osm_opening_hours(oh text)
RETURNS TABLE (weekday smallint, opens time, closes time)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  day_names text[] := ARRAY['mo','tu','we','th','fr','sa','su'];
  week      text[] := array_fill(NULL::text, ARRAY[7]);  -- per giorno: 'HH:MM-HH:MM,...' oppure ''
  rule      text;
  sub       text;
  first_sub boolean;
  m         text[];
  item      text;
  sel       int[];
  a         int;
  b         int;
  d         int;
  times     text;
  iv        text;
  t1        text;
  t2        text;
  result    smallint[] := '{}';
  r_open    time[] := '{}';
  r_close   time[] := '{}';
BEGIN
  IF oh IS NULL THEN RETURN; END IF;
  -- i commenti tra virgolette ("su appuntamento") non sono orari
  oh := lower(btrim(regexp_replace(oh, '"[^"]*"', '', 'g')));

  IF oh = '24/7' THEN
    RETURN QUERY SELECT g::smallint, '00:00'::time, '24:00'::time FROM generate_series(1, 7) g;
    RETURN;
  END IF;

  FOREACH rule IN ARRAY string_to_array(oh, ';') LOOP
    rule := btrim(rule);
    CONTINUE WHEN rule = '';
    -- "Mo-Fr 10:00-19:00, Sa off": la virgola dopo un orario/off apre una regola aggiuntiva
    rule := regexp_replace(rule, '(\d|off|closed)\s*,\s*([a-z])', '\1|\2', 'g');
    first_sub := true;

    FOREACH sub IN ARRAY string_to_array(rule, '|') LOOP
      sub := btrim(sub);
      -- festivi, vacanze e date specifiche: eccezioni che per ora ignoriamo
      IF sub ~ '^((ph|sh)\s|(easter|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\M)' THEN
        first_sub := false;
        CONTINUE;
      END IF;

      m := regexp_match(sub,
        '^((?:(?:mo|tu|we|th|fr|sa|su|ph)(?:\s*-\s*(?:mo|tu|we|th|fr|sa|su))?\s*,?\s*)+)?(.*)$');
      times := regexp_replace(m[2], '\s+', '', 'g');

      sel := '{}';
      IF m[1] IS NULL THEN
        sel := ARRAY[1, 2, 3, 4, 5, 6, 7];
      ELSE
        FOREACH item IN ARRAY string_to_array(regexp_replace(m[1], '\s+', '', 'g'), ',') LOOP
          CONTINUE WHEN item IN ('', 'ph');
          a := array_position(day_names, split_part(item, '-', 1));
          b := coalesce(array_position(day_names, nullif(split_part(item, '-', 2), '')), a);
          d := a;
          LOOP
            sel := sel || d;
            EXIT WHEN d = b;
            d := d % 7 + 1;
          END LOOP;
        END LOOP;
      END IF;
      CONTINUE WHEN cardinality(sel) = 0;

      IF times = '' THEN
        first_sub := false;
        CONTINUE;  -- giorno con solo un commento: nessuna informazione
      ELSIF times IN ('off', 'closed') THEN
        times := '';
      ELSIF times !~ '^\d{1,2}:\d{2}-\d{1,2}:\d{2}(,\d{1,2}:\d{2}-\d{1,2}:\d{2})*$' THEN
        RETURN;  -- sintassi non supportata
      END IF;

      FOREACH d IN ARRAY sel LOOP
        IF first_sub OR times = '' OR week[d] IS NULL OR week[d] = '' THEN
          week[d] := times;
        ELSE
          week[d] := week[d] || ',' || times;
        END IF;
      END LOOP;
      first_sub := false;
    END LOOP;
  END LOOP;

  FOR d IN 1..7 LOOP
    CONTINUE WHEN week[d] IS NULL OR week[d] = '';
    FOREACH iv IN ARRAY string_to_array(week[d], ',') LOOP
      t1 := split_part(iv, '-', 1);
      t2 := split_part(iv, '-', 2);
      -- 00:00 come chiusura = mezzanotte; 26:00 = 02:00 del giorno dopo
      IF t2 IN ('00:00', '0:00') THEN t2 := '24:00'; END IF;
      IF split_part(t2, ':', 1)::int > 24 THEN
        t2 := (split_part(t2, ':', 1)::int - 24) || ':' || split_part(t2, ':', 2);
      END IF;
      result  := result || d::smallint;
      r_open  := r_open || t1::time;
      r_close := r_close || t2::time;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT u.d, u.o, u.c FROM unnest(result, r_open, r_close) AS u(d, o, c);
EXCEPTION WHEN others THEN
  RETURN;
END;
$$;
