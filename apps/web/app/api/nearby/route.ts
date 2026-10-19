import type { NextRequest } from "next/server";
import { parsePoint, placesWithinRadius } from "@/lib/places";

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const from = parsePoint(params);
  if (!from) return Response.json({ error: "lat e lon obbligatori" }, { status: 400 });

  const radius = Math.min(Math.max(Number(params.get("radius") ?? 400), 50), 2000);
  return Response.json({ places: await placesWithinRadius(from, radius) });
}
