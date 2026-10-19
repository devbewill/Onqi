import type { NextRequest } from "next/server";
import { parsePoint, searchPlaces } from "@/lib/places";

// GET /api/search?q=&lat=&lon=
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const from = parsePoint(params);
  const q = (params.get("q") ?? "").trim();
  if (!from) return Response.json({ error: "lat e lon obbligatori" }, { status: 400 });
  if (q.length < 2) return Response.json({ places: [] });

  return Response.json({ places: await searchPlaces(from, q.slice(0, 80), 10) });
}
