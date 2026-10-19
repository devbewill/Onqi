import { pool } from "@/lib/db";

// Contorno di ogni CAP importato, per mostrare sulla mappa dove ci sono dati.
// Si escludono i punti isolati (CAP probabilmente errato): servono almeno 3
// attività dello stesso CAP entro 150 m.
const AREAS_SQL = `
  SELECT json_build_object('type', 'FeatureCollection', 'features', coalesce(json_agg(f), '[]')) AS fc
  FROM (
    SELECT json_build_object(
             'type', 'Feature',
             'properties', json_build_object('postcode', postcode),
             'geometry', ST_AsGeoJSON(ST_Buffer(ST_ConcaveHull(ST_Collect(geom::geometry), 0.3), 0.0008))::json
           ) AS f
    FROM places p
    WHERE p.is_public
      AND (SELECT count(*) FROM places n
            WHERE n.is_public AND n.postcode = p.postcode AND ST_DWithin(n.geom, p.geom, 150)) >= 4
    GROUP BY postcode
  ) x`;

export async function GET() {
  const { rows } = await pool.query<{ fc: GeoJSON.FeatureCollection }>(AREAS_SQL);
  return Response.json(rows[0].fc);
}
