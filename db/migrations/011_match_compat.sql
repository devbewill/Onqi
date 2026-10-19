-- Due record di fonti diverse possono essere lo stesso place solo se non
-- appartengono uno a un luogo/struttura non commerciale (piazza, alloggio
-- privato, fermata, scuola...) e l'altro no. Evita abbinamenti come
-- "Farmacia Sant'Eustorgio" -> "Piazza Sant'Eustorgio": il nome contiene lo
-- stesso riferimento al luogo e da solo sembrerebbe simile.
CREATE FUNCTION onqi_categories_compatible(a int, b int) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT (SELECT slug FROM categories WHERE id = a) IN (
           'luogo', 'residenziale', 'trasporti', 'culto', 'istruzione', 'pubblica_amministrazione')
       = (SELECT slug FROM categories WHERE id = b) IN (
           'luogo', 'residenziale', 'trasporti', 'culto', 'istruzione', 'pubblica_amministrazione')
$$;
