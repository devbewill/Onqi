-- Caricamento dei dataset di sosta e parcheggi del Comune di Milano in
-- staging.parking_raw. Variabile: dir (cartella con i GeoJSON scaricati).
DELETE FROM pg.staging.parking_raw;

-- ds342: parcheggi pubblici (con numero di posti)
INSERT INTO pg.staging.parking_raw (kind, id, name, address, spaces, rate, info, geom_json)
SELECT 'pubblico',
       json_extract_string(f, '$.properties.id'),
       json_extract_string(f, '$.properties.nome'),
       json_extract_string(f, '$.properties.indirizzo'),
       TRY_CAST(round(TRY_CAST(json_extract_string(f, '$.properties.n_posti') AS DOUBLE)) AS INTEGER),
       NULL,
       json_extract_string(f, '$.properties.tipo'),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('dir') || '/park_pub.geojson') t,
     unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);

-- ds45: parcheggi di interscambio (i posti sono nel campo testo "2200 POSTI AUTO")
INSERT INTO pg.staging.parking_raw (kind, id, name, address, spaces, rate, info, geom_json)
SELECT 'interscambio',
       NULL,
       json_extract_string(f, '$.properties.Nome'),
       json_extract_string(f, '$.properties.indirizzo'),
       TRY_CAST(regexp_extract(json_extract_string(f, '$.properties.TAB1'), '([0-9]+)\s*POSTI', 1) AS INTEGER),
       NULL,
       json_extract_string(f, '$.properties.INFO'),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('dir') || '/park_interscambio.geojson') t,
     unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);

-- ds740: sosta riservata ai turisti (stalli, regole, tariffa)
INSERT INTO pg.staging.parking_raw (kind, id, name, address, spaces, rate, info, geom_json)
SELECT 'turistico',
       json_extract_string(f, '$.properties.id_amat'),
       json_extract_string(f, '$.properties.localizzaz'),
       json_extract_string(f, '$.properties.localizzaz'),
       TRY_CAST(json_extract_string(f, '$.properties.num_stalli') AS INTEGER),
       TRY_CAST(regexp_extract(json_extract_string(f, '$.properties.costo_ora'), '([0-9]+[.,]?[0-9]*)', 1) AS DOUBLE),
       concat_ws(' · ',
                 nullif(json_extract_string(f, '$.properties.tipologia'), ''),
                 nullif(json_extract_string(f, '$.properties.regole'), ''),
                 nullif(json_extract_string(f, '$.properties.note'), '')),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('dir') || '/sosta_turistici.geojson') t,
     unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);

-- ds670: aree di sosta biciclette
INSERT INTO pg.staging.parking_raw (kind, id, name, address, spaces, rate, info, geom_json)
SELECT 'bici',
       json_extract_string(f, '$.properties.id_amat'),
       concat_ws(' ', json_extract_string(f, '$.properties.via_nome'),
                      json_extract_string(f, '$.properties.num_civico')),
       concat_ws(' ', json_extract_string(f, '$.properties.via_nome'),
                      json_extract_string(f, '$.properties.num_civico')),
       TRY_CAST(json_extract_string(f, '$.properties.stalli_totali') AS INTEGER),
       NULL,
       concat_ws(' · ',
                 nullif(json_extract_string(f, '$.properties.veicoli'), ''),
                 nullif(json_extract_string(f, '$.properties.stallo_man'), ''),
                 nullif(json_extract_string(f, '$.properties.ubicazione'), '')),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('dir') || '/bike_areesosta.geojson') t,
     unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);

-- ds83: ambiti di sosta (poligoni con tariffa e posti)
INSERT INTO pg.staging.parking_raw (kind, id, name, address, spaces, rate, info, geom_json)
SELECT 'ambito',
       json_extract_string(f, '$.properties.ambito'),
       json_extract_string(f, '$.properties.nome'),
       NULL,
       TRY_CAST(json_extract_string(f, '$.properties.posti_pagamento') AS INTEGER),
       TRY_CAST(regexp_extract(json_extract_string(f, '$.properties.euro_h_g'), '([0-9]+[.,]?[0-9]*)', 1) AS DOUBLE),
       concat_ws(' · ',
                 nullif(json_extract_string(f, '$.properties.tipo_sosta'), ''),
                 nullif(concat_ws(' ',
                   nullif(json_extract_string(f, '$.properties.inizio_g'), ''),
                   nullif(json_extract_string(f, '$.properties.fine_g'), '')), ''),
                 nullif(concat_ws(' ',
                   nullif(json_extract_string(f, '$.properties.inizio_s'), ''),
                   nullif(json_extract_string(f, '$.properties.fine_s'), '')), '')),
       json_extract_string(f, '$.geometry')
FROM read_text(getvariable('dir') || '/sosta_ambiti.geojson') t,
     unnest(json_extract(t.content, '$.features[*]')::json[]) AS u(f);
