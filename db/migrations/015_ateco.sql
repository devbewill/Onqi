-- Codice ATECO censito dal Comune (registro di vicinato): codice numerico e
-- descrizione separati. Arrivano già insieme nel CSV ("47.71.10 - Commercio
-- al dettaglio di..."): qui si spezzano per ricerche e raggruppamenti.
ALTER TABLE places
  ADD COLUMN ateco       text,
  ADD COLUMN ateco_label text;

-- Backfill: payload del Comune già salvato in place_sources.
UPDATE places p
SET ateco = a.code, ateco_label = a.label
FROM (SELECT DISTINCT ON (ps.place_id) ps.place_id,
             (regexp_match(ps.raw->>'ateco', '^(\d[\d.]*\d)\s*[-–]\s*(.+)$'))[1] AS code,
             (regexp_match(ps.raw->>'ateco', '^(\d[\d.]*\d)\s*[-–]\s*(.+)$'))[2] AS label
        FROM place_sources ps
       WHERE ps.source = 'comune' AND ps.raw ? 'ateco' AND ps.raw->>'ateco' <> ''
       ORDER BY ps.place_id, ps.fetched_at DESC) a
WHERE p.id = a.place_id;
