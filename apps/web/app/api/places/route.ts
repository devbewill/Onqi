import type { NextRequest } from "next/server";
import { parsePoint, placesInBox } from "@/lib/places";

const LIMIT = 1000;

// GET /api/places?bbox=ovest,sud,est,nord&lat=&lon=
// Attività nel rettangolo visibile, ordinate per distanza da lat/lon.
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const from = parsePoint(params);
  const bbox = (params.get("bbox") ?? "").split(",").map(Number);
  if (!from || bbox.length !== 4 || !bbox.every(Number.isFinite)) {
    return Response.json({ error: "bbox, lat e lon obbligatori" }, { status: 400 });
  }

  const places = await placesInBox(from, bbox as [number, number, number, number], LIMIT);
  return Response.json({ places, truncated: places.length === LIMIT });
}
