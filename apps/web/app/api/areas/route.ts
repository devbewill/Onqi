import { pool } from "@/lib/db";

// Zona coperta dai dati, per disegnarla sulla mappa: unione dei poligoni di
// import (es. circonvallazione) e del contorno delle aree per CAP. Per i CAP si
// escludono i punti isolati (CAP probabilmente errato): servono almeno 4 attività
// dello stesso CAP entro 150 m.
const AREAS_SQL = `
  WITH parts AS (
    SELECT geom AS g FROM import_areas WHERE geom IS NOT NULL
    UNION ALL
    SELECT ST_Buffer(ST_ConcaveHull(ST_Collect(p.geom::geometry), 0.3), 0.0008)
    FROM places p
    JOIN import_areas a ON a.geom IS NULL AND a.postcode = p.postcode
    WHERE p.is_public
      AND (SELECT count(*) FROM places n
            WHERE n.is_public AND n.postcode = p.postcode AND ST_DWithin(n.geom, p.geom, 150)) >= 4
    GROUP BY p.postcode
  )
  SELECT json_build_object('type', 'FeatureCollection', 'features', json_build_array(
           json_build_object('type', 'Feature', 'properties', json_build_object('label', 'Zona coperta'),
                             'geometry', ST_AsGeoJSON(ST_Union(g))::json))) AS fc
  FROM parts`;

export async function GET() {
  const { rows } = await pool.query<{ fc: GeoJSON.FeatureCollection }>(AREAS_SQL);
  return Response.json(rows[0].fc);
}
