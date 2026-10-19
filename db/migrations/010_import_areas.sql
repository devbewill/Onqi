-- Aree di import definite da un poligono (es. tutta Milano dentro la
-- circonvallazione esterna) oltre che da un CAP.
CREATE TABLE import_areas (
  code     text PRIMARY KEY,
  postcode text,                              -- area = un CAP
  geom     geometry(MultiPolygon, 4326),      -- oppure area = poligono
  CHECK (postcode IS NOT NULL OR geom IS NOT NULL)
);
CREATE INDEX import_areas_geom_idx ON import_areas USING gist (geom);

-- Il punto (o il CAP) appartiene all'area?
CREATE FUNCTION onqi_in_area(p_area text, p_geom geography, p_postcode text) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM import_areas a
    WHERE a.code = p_area
      AND CASE WHEN a.geom IS NOT NULL THEN ST_Covers(a.geom, p_geom::geometry)
               ELSE a.postcode = p_postcode END
  )
$$;
