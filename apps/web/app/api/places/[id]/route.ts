import type { NextRequest } from "next/server";
import { getPlaceDetail, updatePlace, ValidationError, type PlacePatch } from "@/lib/place-detail";

const UUID = /^[0-9a-f-]{36}$/i;

export async function GET(_req: NextRequest, ctx: RouteContext<"/api/places/[id]">) {
  const { id } = await ctx.params;
  if (!UUID.test(id)) return Response.json({ error: "id non valido" }, { status: 400 });
  const place = await getPlaceDetail(id);
  if (!place) return Response.json({ error: "Attività non trovata" }, { status: 404 });
  return Response.json(place);
}

// Modifica manuale di uno o più campi. I campi modificati restano bloccati:
// gli import successivi non li sovrascrivono.
export async function PATCH(request: NextRequest, ctx: RouteContext<"/api/places/[id]">) {
  const { id } = await ctx.params;
  if (!UUID.test(id)) return Response.json({ error: "id non valido" }, { status: 400 });

  let patch: PlacePatch;
  try {
    patch = await request.json();
  } catch {
    return Response.json({ error: "JSON non valido" }, { status: 400 });
  }

  try {
    return Response.json(await updatePlace(id, patch));
  } catch (e) {
    if (e instanceof ValidationError) return Response.json({ error: e.message }, { status: 400 });
    throw e;
  }
}
