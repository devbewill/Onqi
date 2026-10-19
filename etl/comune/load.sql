-- Carica i tre elenchi comunali (tutta Milano) nella staging Postgres.
-- Variabili: dir (cartella con i CSV). Il catalogo 'pg' è collegato da etl/import.sh.
DELETE FROM pg.staging.comune_esercizi;

INSERT INTO pg.staging.comune_esercizi
  (codice, dataset, via, civico, cap, insegna, tipo, ateco, superficie, lon, lat)
SELECT Codice, 'vicinato', DescrizioneVia, Civico, CAP::varchar, nullif(trim(insegna), ''),
       'vicinato:' || CASE
         WHEN lower(settore_merceologico) LIKE '%monopolio%' THEN 'monopolio'
         WHEN lower(settore_merceologico) LIKE 'alimentarenon%' THEN 'misto'
         WHEN lower(settore_merceologico) IN ('alimentare', 'non alimentare') THEN lower(settore_merceologico)
         ELSE '?' END,
       codice_ateco, superficie_vendita, LONG_X_4326, LAT_Y_4326
FROM read_csv(getvariable('dir') || '/comune_vicinato.csv', sample_size = -1)
UNION ALL
SELECT Codice, 'pubblico_esercizio', DescrizioneVia, Civico, CAP::varchar, nullif(trim(insegna), ''),
       'pe:' || coalesce(nullif(regexp_extract(lower(denominazione_pe), '^([a-i]) -', 1), ''), '?'),
       NULL, superficie_somministrazione, LONG_X_4326, LAT_Y_4326
FROM read_csv(getvariable('dir') || '/comune_pe_in_piano.csv', sample_size = -1)
UNION ALL
SELECT Codice, 'pubblico_esercizio_fuori_piano', DescrizioneVia, Civico, CAP::varchar, nullif(trim(insegna), ''),
       'pe:' || coalesce(nullif(regexp_extract(lower(settore_storico_pe), '^([a-i]) -', 1), ''), '?'),
       NULL, superficie_somministrazione, LONG_X_4326, LAT_Y_4326
FROM read_csv(getvariable('dir') || '/comune_pe_fuori_piano.csv', sample_size = -1);
