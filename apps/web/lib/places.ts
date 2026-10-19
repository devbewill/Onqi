import { pool } from "@/lib/db";
import type { NearbyPlace } from "@/lib/types";

// Campi restituiti per ogni attività. $1, $2 = lon, lat del punto da cui misurare la distanza.
const PLACE_FIELDS = `
  p.id, p.name,
  c.slug AS category, c.name_it AS "categoryName",
  m.slug AS macro, m.name_it AS "macroName",
  round(ST_Distance(p.geom, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography))::int AS distance,
  ST_Y(p.geom::geometry) AS lat, ST_X(p.geom::geometry) AS lon,
  p.address, p.phone, p.website, p.email, p.socials, p.vat_number AS "vatNumber",
  onqi_is_open(p.id) AS "openNow",
  (SELECT string_agg(to_char(h.opens, 'HH24:MI') || '–' || to_char(h.closes, 'HH24:MI'),
                     ', ' ORDER BY h.opens)
     FROM opening_hours h
    WHERE h.place_id = p.id
      AND h.weekday = extract(isodow FROM now() AT TIME ZONE 'Europe/Rome')) AS "hoursToday",
  (SELECT array_agg(s.source ORDER BY s.source)
     FROM place_sources s WHERE s.place_id = p.id) AS sources,
  coalesce((SELECT json_agg(json_build_object('title', pr.title, 'kind', pr.kind,
                                              'until', upper(o.during)))
              FROM promotion_occurrences o
              JOIN promotions pr ON pr.id = o.promotion_id
             WHERE o.place_id = p.id AND o.during @> now()), '[]') AS promos`;

const PLACE_JOINS = `
  JOIN categories c ON c.id = p.category_id
  LEFT JOIN categories m ON m.id = c.parent_id`;

export type Point = { lat: number; lon: number };

export function parsePoint(params: URLSearchParams): Point | null {
  const lat = Number(params.get("lat"));
  const lon = Number(params.get("lon"));
  if (!params.get("lat") || !params.get("lon")) return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  return { lat, lon };
}

export async function placesWithinRadius(from: Point, radius: number) {
  const { rows } = await pool.query<NearbyPlace>(
    `SELECT ${PLACE_FIELDS}
       FROM places p ${PLACE_JOINS}
      WHERE p.status <> 'closed' AND p.is_public
        AND ST_DWithin(p.geom, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
      ORDER BY distance
      LIMIT 300`,
    [from.lon, from.lat, radius],
  );
  return rows;
}

export async function placesInBox(from: Point, bbox: [number, number, number, number], limit: number) {
  const { rows } = await pool.query<NearbyPlace>(
    `SELECT ${PLACE_FIELDS}
       FROM places p ${PLACE_JOINS}
      WHERE p.status <> 'closed' AND p.is_public
        AND p.geom && ST_MakeEnvelope($3, $4, $5, $6, 4326)::geography
      ORDER BY distance
      LIMIT $7`,
    [from.lon, from.lat, ...bbox, limit],
  );
  return rows;
}

// Prima i nomi che contengono il testo cercato, poi i più simili; a parità, i più vicini.
export async function searchPlaces(from: Point, q: string, limit: number) {
  const { rows } = await pool.query<NearbyPlace>(
    `SELECT ${PLACE_FIELDS}
       FROM places p ${PLACE_JOINS},
            LATERAL (SELECT onqi_norm_name($3) AS q) s
      WHERE p.status <> 'closed' AND p.is_public
        AND s.q <> ''
        AND (onqi_norm_name(p.name) LIKE '%' || s.q || '%' OR onqi_norm_name(p.name) % s.q)
      ORDER BY (onqi_norm_name(p.name) LIKE s.q || '%') DESC,
               (onqi_norm_name(p.name) LIKE '%' || s.q || '%') DESC,
               similarity(onqi_norm_name(p.name), s.q) DESC,
               distance
      LIMIT $4`,
    [from.lon, from.lat, q, limit],
  );
  return rows;
}
