import type { NextRequest } from "next/server";
import { parsePoint, searchPlaces } from "@/lib/places";

const SLUG = /^[a-z_]{1,40}$/;

// GET /api/search?q=&macro=&category=&lat=&lon=
// Serve almeno un testo (2+ caratteri) o una tipologia (macro o categoria).
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const from = parsePoint(params);
  if (!from) return Response.json({ error: "lat e lon obbligatori" }, { status: 400 });

  const q = (params.get("q") ?? "").trim().slice(0, 80);
  const macro = params.get("macro") || undefined;
  const category = params.get("category") || undefined;
  if ((macro && !SLUG.test(macro)) || (category && !SLUG.test(category))) {
    return Response.json({ error: "tipologia non valida" }, { status: 400 });
  }
  if (q.length < 2 && !macro && !category) return Response.json({ places: [] });

  return Response.json({ places: await searchPlaces(from, q.length >= 2 ? q : "", { macro, category }, 50) });
}
