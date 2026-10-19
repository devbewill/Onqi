import { pool } from "@/lib/db";

// Categorie selezionabili (secondo livello), raggruppate per macro-categoria.
export async function GET() {
  const { rows } = await pool.query(
    `SELECT c.id, c.name_it AS name, m.slug AS macro, m.name_it AS "macroName", c.is_public AS "isPublic"
       FROM categories c JOIN categories m ON m.id = c.parent_id
      ORDER BY m.is_public DESC, m.name_it, c.name_it`,
  );
  return Response.json({ categories: rows });
}
