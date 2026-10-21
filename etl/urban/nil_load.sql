-- Caricamento del GeoJSON dei NIL (Comune di Milano) in staging.nil_raw.
DELETE FROM pg.staging.nil_raw;

INSERT INTO pg.staging.nil_raw (id_nil, name, geom_json)
SELECT CAST(json_extract_string(f, '$.properties.ID_NIL') AS integer),
       json_extract_string(f, '$.properties.NIL'),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('file')) t
CROSS JOIN unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);
