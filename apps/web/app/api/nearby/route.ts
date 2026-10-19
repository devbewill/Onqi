import type { NextRequest } from "next/server";
import { parsePoint, placesWithinRadius } from "@/lib/places";

const LIMIT = 5000;

// GET /api/nearby?lat=&lon=&radius=  (raggio in metri, default 500)
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const from = parsePoint(params);
  if (!from) return Response.json({ error: "lat e lon obbligatori" }, { status: 400 });

  const radius = Math.min(Math.max(Number(params.get("radius") ?? 500), 50), 2000);
  const places = await placesWithinRadius(from, radius, LIMIT);
  return Response.json({ places, truncated: places.length === LIMIT });
}
