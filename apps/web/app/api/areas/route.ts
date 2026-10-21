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

// Il punto è dentro la zona coperta? (stessa unione usata per il disegno)
const COVERED_SQL = `
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
  SELECT ST_Covers(ST_Union(g), ST_SetSRID(ST_MakePoint($1, $2), 4326)) AS covered
  FROM parts`;

// GET /api/areas[?lat=&lon=]
// Con lat/lon risponde anche 'covered': true se il punto è nella zona con dati.
export async function GET(request: Request) {
  const url = new URL(request.url);
  const lat = Number(url.searchParams.get("lat"));
  const lon = Number(url.searchParams.get("lon"));
  const hasPoint = url.searchParams.has("lat") && url.searchParams.has("lon")
    && Number.isFinite(lat) && Number.isFinite(lon);

  const { rows } = await pool.query<{ fc: GeoJSON.FeatureCollection }>(AREAS_SQL);
  const fc = rows[0].fc;
  if (!hasPoint) return Response.json(fc);

  const r = await pool.query<{ covered: boolean }>(COVERED_SQL, [lon, lat]);
  return Response.json({ ...fc, covered: r.rows[0]?.covered ?? false });
}
