import { pool } from "@/lib/db";

export type HoursRow = { weekday: number; opens: string; closes: string; source: string };
export type SourceRecord = { source: string; sourceId: string; raw: Record<string, unknown>; fetchedAt: string };
export type EditRecord = { field: string; oldValue: unknown; newValue: unknown; createdAt: string };
export type TransitInfo = {
  name: string;
  meters: number;
  lines: { code: string | null; type: number }[];
};

export type PlaceDetail = {
  id: string;
  name: string;
  categoryId: number;
  categoryName: string;
  macro: string;
  macroName: string;
  lat: number;
  lon: number;
  address: string | null;
  postcode: string | null;
  city: string | null;
  phone: string | null;
  website: string | null;
  email: string | null;
  socials: string[] | null;
  vatNumber: string | null;
  ateco: string | null;
  atecoLabel: string | null;
  brand: string | null;
  confidence: number | null;
  status: string;
  isPublic: boolean;
  nonPublicReason: string | null;
  lockedFields: string[];
  attributes: Record<string, string>;
  sourceAttributes: Record<string, string>;
  nil: string | null;
  transit: TransitInfo | null;
  openNow: boolean | null;
  hours: HoursRow[];
  sources: SourceRecord[];
  edits: EditRecord[];
  createdAt: string;
  updatedAt: string;
};

export async function getPlaceDetail(id: string) {
  const { rows } = await pool.query<PlaceDetail>(
    `SELECT p.id, p.name, p.category_id AS "categoryId", c.name_it AS "categoryName",
            m.slug AS macro, m.name_it AS "macroName",
            ST_Y(p.geom::geometry) AS lat, ST_X(p.geom::geometry) AS lon,
            p.address, p.postcode, p.city, p.phone, p.website, p.email, p.socials,
            p.vat_number AS "vatNumber", p.ateco, p.ateco_label AS "atecoLabel", p.brand, p.confidence, p.status,
            p.is_public AS "isPublic", p.non_public_reason AS "nonPublicReason",
            p.locked_fields AS "lockedFields", p.attributes, p.source_attributes AS "sourceAttributes",
            p.nil,
            (SELECT json_build_object('name', n.stop_name, 'meters', n.meters,
                                      'lines', coalesce(n.lines, '[]'::json))
               FROM (SELECT s.stop_name,
                            round(ST_Distance(s.geom, p.geom))::int AS meters,
                            (SELECT json_agg(json_build_object('code', r.route_short_name,
                                                               'type', r.route_type)
                                              ORDER BY r.route_type, r.route_short_name)
                               FROM transit_stop_routes sr
                               JOIN transit_routes r ON r.route_id = sr.route_id
                              WHERE sr.stop_id = s.stop_id
                                 OR sr.stop_id = coalesce(s.parent_station, '')
                                 OR sr.stop_id IN (SELECT c.stop_id FROM transit_stops c
                                                    WHERE c.parent_station = s.stop_id)) AS lines
                       FROM transit_stops s
                      ORDER BY s.geom <-> p.geom LIMIT 1) n) AS "transit",
            onqi_is_open(p.id) AS "openNow",
            coalesce((SELECT json_agg(json_build_object('weekday', h.weekday,
                                                        'opens', to_char(h.opens, 'HH24:MI'),
                                                        'closes', to_char(h.closes, 'HH24:MI'),
                                                        'source', h.source) ORDER BY h.weekday, h.opens)
                        FROM opening_hours h WHERE h.place_id = p.id), '[]') AS hours,
            coalesce((SELECT json_agg(json_build_object('source', s.source, 'sourceId', s.source_id,
                                                        'raw', s.raw, 'fetchedAt', s.fetched_at) ORDER BY s.source)
                        FROM place_sources s WHERE s.place_id = p.id), '[]') AS sources,
            coalesce((SELECT json_agg(e) FROM (
                        SELECT field, old_value AS "oldValue", new_value AS "newValue", created_at AS "createdAt"
                          FROM place_edits WHERE place_id = p.id ORDER BY created_at DESC LIMIT 20) e), '[]') AS edits,
            p.created_at AS "createdAt", p.updated_at AS "updatedAt"
       FROM places p
       JOIN categories c ON c.id = p.category_id
       LEFT JOIN categories m ON m.id = c.parent_id
      WHERE p.id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

// --- Modifiche manuali -------------------------------------------------------------

export class ValidationError extends Error {}

const TIME = /^([01]?\d|2[0-4]):[0-5]\d$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const STATUSES = ["active", "unverified", "closed"];

function text(v: unknown, field: string, { required = false } = {}) {
  if (v === null || v === undefined || (typeof v === "string" && v.trim() === "")) {
    if (required) throw new ValidationError(`${field}: obbligatorio`);
    return null;
  }
  if (typeof v !== "string") throw new ValidationError(`${field}: deve essere un testo`);
  return v.trim();
}

function url(v: unknown, field: string) {
  const t = text(v, field);
  if (!t) return null;
  const withScheme = /^https?:\/\//i.test(t) ? t : `https://${t}`;
  try {
    return new URL(withScheme).toString();
  } catch {
    throw new ValidationError(`${field}: indirizzo web non valido`);
  }
}

// Campo dell'API -> colonna di places e funzione che valida il valore.
const FIELDS: Record<string, { column: string; parse: (v: unknown) => unknown }> = {
  name: { column: "name", parse: (v) => text(v, "Nome", { required: true }) },
  address: { column: "address", parse: (v) => text(v, "Indirizzo") },
  postcode: {
    column: "postcode",
    parse: (v) => {
      const t = text(v, "CAP");
      if (t && !/^\d{5}$/.test(t)) throw new ValidationError("CAP: 5 cifre");
      return t;
    },
  },
  phone: { column: "phone", parse: (v) => text(v, "Telefono") },
  website: { column: "website", parse: (v) => url(v, "Sito web") },
  email: {
    column: "email",
    parse: (v) => {
      const t = text(v, "Email");
      if (t && !EMAIL.test(t)) throw new ValidationError("Email non valida");
      return t;
    },
  },
  socials: {
    column: "socials",
    parse: (v) => {
      if (v === null) return null;
      if (!Array.isArray(v)) throw new ValidationError("Social: elenco di indirizzi");
      const list = v.map((s) => url(s, "Social")).filter(Boolean);
      return list.length ? list : null;
    },
  },
  vatNumber: { column: "vat_number", parse: (v) => text(v, "P.IVA") }, // validata in SQL
  categoryId: {
    column: "category_id",
    parse: (v) => {
      if (!Number.isInteger(v)) throw new ValidationError("Categoria non valida");
      return v;
    },
  },
  status: {
    column: "status",
    parse: (v) => {
      if (typeof v !== "string" || !STATUSES.includes(v)) throw new ValidationError("Stato non valido");
      return v;
    },
  },
  isPublic: {
    column: "is_public",
    parse: (v) => {
      if (typeof v !== "boolean") throw new ValidationError("Aperto al pubblico: sì o no");
      return v;
    },
  },
};

export type PlacePatch = Record<string, unknown> & {
  attributes?: Record<string, string | null>;
  openingHours?: { weekday: number; opens: string; closes: string }[];
};

export async function updatePlace(id: string, patch: PlacePatch) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL onqi.manual_edit = 'on'");

    const { rows } = await client.query("SELECT * FROM places WHERE id = $1 FOR UPDATE", [id]);
    const current = rows[0];
    if (!current) throw new ValidationError("Attività non trovata");

    for (const [key, raw] of Object.entries(patch)) {
      if (key === "attributes" || key === "openingHours") continue;
      const field = FIELDS[key];
      if (!field) throw new ValidationError(`Campo non modificabile: ${key}`);
      let value = field.parse(raw);

      if (field.column === "vat_number" && value !== null) {
        const r = await client.query("SELECT onqi_vat_normalize($1) AS v", [value]);
        if (!r.rows[0].v) throw new ValidationError("P.IVA non valida (controlla le 11 cifre)");
        value = r.rows[0].v;
      }
      if (field.column === "category_id") {
        const r = await client.query("SELECT 1 FROM categories WHERE id = $1 AND parent_id IS NOT NULL", [value]);
        if (!r.rowCount) throw new ValidationError("Categoria non valida");
      }

      const extra =
        field.column === "is_public" ? `, non_public_reason = CASE WHEN $1::boolean THEN NULL ELSE 'manuale' END` : "";
      await client.query(
        `UPDATE places
            SET ${field.column} = $1${extra},
                locked_fields = (SELECT array_agg(DISTINCT f) FROM unnest(locked_fields || $2::text) f),
                updated_at = now()
          WHERE id = $3`,
        [value, field.column, id],
      );
      await client.query(
        "INSERT INTO place_edits (place_id, field, old_value, new_value) VALUES ($1, $2, $3, $4)",
        [id, field.column, JSON.stringify(current[field.column] ?? null), JSON.stringify(value)],
      );
    }

    if (patch.attributes) {
      const clean: Record<string, string | null> = {};
      for (const [k, v] of Object.entries(patch.attributes)) {
        if (!/^[a-z_:]{1,40}$/.test(k)) throw new ValidationError(`Dettaglio non valido: ${k}`);
        clean[k] = v === null || v === "" ? null : String(v).slice(0, 500);
      }
      // null = torna al valore della fonte (rimuove la chiave)
      await client.query(
        `UPDATE places
            SET attributes = jsonb_strip_nulls(attributes || $1::jsonb), updated_at = now()
          WHERE id = $2`,
        [JSON.stringify(clean), id],
      );
      await client.query(
        "INSERT INTO place_edits (place_id, field, old_value, new_value) VALUES ($1, 'attributes', $2, $3)",
        [id, JSON.stringify(current.attributes), JSON.stringify(clean)],
      );
    }

    if (patch.openingHours) {
      if (!Array.isArray(patch.openingHours)) throw new ValidationError("Orari non validi");
      for (const h of patch.openingHours) {
        if (!Number.isInteger(h.weekday) || h.weekday < 1 || h.weekday > 7 || !TIME.test(h.opens) || !TIME.test(h.closes)) {
          throw new ValidationError("Orari non validi: usa il formato 09:00-13:00");
        }
      }
      const old = await client.query(
        "SELECT weekday, to_char(opens, 'HH24:MI') AS opens, to_char(closes, 'HH24:MI') AS closes FROM opening_hours WHERE place_id = $1",
        [id],
      );
      // Gli orari manuali sostituiscono quelli delle fonti (anche ai prossimi import).
      await client.query("DELETE FROM opening_hours WHERE place_id = $1", [id]);
      for (const h of patch.openingHours) {
        await client.query(
          "INSERT INTO opening_hours (place_id, weekday, opens, closes, source) VALUES ($1, $2, $3, $4, 'manual')",
          [id, h.weekday, h.opens, h.closes],
        );
      }
      await client.query(
        "INSERT INTO place_edits (place_id, field, old_value, new_value) VALUES ($1, 'opening_hours', $2, $3)",
        [id, JSON.stringify(old.rows), JSON.stringify(patch.openingHours)],
      );
    }

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }

  // Fuori dalla modifica manuale: ricalcola il flag pubblico (es. dopo un cambio di
  // categoria) senza toccare i campi bloccati.
  await pool.query("SELECT onqi_refresh_public()");
  return getPlaceDetail(id);
}
