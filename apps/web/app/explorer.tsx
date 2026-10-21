"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  LngLatBounds,
  Map as MapLibreMap,
  NavigationControl,
  type GeoJSONSource,
  type MapLayerMouseEvent,
  type MapMouseEvent,
  setWorkerUrl,
} from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { NearbyPlace } from "@/lib/types";
import PlacePanel from "./place-panel";

setWorkerUrl("/maplibre/maplibre-gl-worker.mjs");

// Naviglio Grande, all'altezza della Darsena: punto di partenza se la posizione
// non è disponibile o è fuori Milano.
const DEFAULT_POSITION = { lat: 45.4515, lon: 9.1745 };
const RADIUS = 500;

const MACRO_COLORS: Record<string, string> = {
  food_drink: "#e8590c",
  nightlife: "#9c36b5",
  grocery: "#2f9e44",
  shopping: "#1c7ed6",
  health: "#e03131",
  beauty: "#d6336c",
  sport: "#0c8599",
  culture: "#f08c00",
  lodging: "#5f3dc4",
  services: "#495057",
  community: "#5c940d",
};

type Position = { lat: number; lon: number };
type Category = { id: number; slug: string; name: string; macro: string; macroName: string; isPublic: boolean };
type ListResult = { key: string; places: NearbyPlace[]; truncated: boolean };

function circleGeoJSON(center: Position, radius: number): GeoJSON.Feature<GeoJSON.Polygon> {
  const points = 64;
  const coords: [number, number][] = [];
  const dLat = radius / 111_320;
  const dLon = radius / (111_320 * Math.cos((center.lat * Math.PI) / 180));
  for (let i = 0; i <= points; i++) {
    const a = (i / points) * 2 * Math.PI;
    coords.push([center.lon + dLon * Math.cos(a), center.lat + dLat * Math.sin(a)]);
  }
  return { type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [coords] } };
}

// Il punto è nella zona con dati? Lo chiede al server: la zona coperta cambia
// con gli import (prima la sola circonvallazione, oggi tutto il comune).
async function isCovered(p: Position): Promise<boolean> {
  try {
    const r = await fetch(`/api/areas?lat=${p.lat}&lon=${p.lon}`);
    if (!r.ok) return false;
    return (await r.json()).covered === true;
  } catch {
    return false;
  }
}

// Posizione reale: si usa sempre, anche se è fuori dalla zona con dati (avviso).
function requestPosition(onResult: (p: Position | null, message: string | null) => void) {
  if (!navigator.geolocation) {
    onResult(null, "Posizione non disponibile su questo dispositivo: ti mostro la Darsena.");
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (geo) => {
      const p = { lat: geo.coords.latitude, lon: geo.coords.longitude };
      isCovered(p).then((covered) => {
        if (covered) onResult(p, null);
        else
          onResult(
            p,
            `La posizione rilevata (${p.lat.toFixed(4)}, ${p.lon.toFixed(4)}) è fuori dalla zona con dati: la uso comunque, ma qui intorno l'elenco sarà vuoto. Tocca la mappa per spostarti.`,
          );
      });
    },
    () => onResult(null, "Posizione non concessa: ti mostro la Darsena. Tocca la mappa per spostarti."),
    { enableHighAccuracy: true, timeout: 10_000 },
  );
}

function formatDistance(m: number) {
  return m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1)} km`;
}

function OpenBadge({ openNow }: { openNow: boolean | null }) {
  if (openNow === null) return <span className="text-xs text-zinc-400">orari n.d.</span>;
  return openNow ? (
    <span className="rounded bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800">aperto ora</span>
  ) : (
    <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs font-medium text-zinc-600">chiuso</span>
  );
}

export default function Explorer() {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const listRefs = useRef<Record<string, HTMLLIElement | null>>({});

  const [position, setPosition] = useState<Position>(DEFAULT_POSITION);
  const [geoMessage, setGeoMessage] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [mapReady, setMapReady] = useState(false);
  const [openOnly, setOpenOnly] = useState(false);
  // Incrementato dopo una modifica manuale, per ricaricare la lista
  const [revision, setRevision] = useState(0);

  // Ricerca: testo e tipologia ("macro:food_drink" o "category:bar")
  const [query, setQuery] = useState("");
  const [type, setType] = useState("");
  const [categories, setCategories] = useState<Category[]>([]);

  const trimmedQuery = query.trim();
  const searchMode = trimmedQuery.length >= 2 || type !== "";

  // --- Vicino a me (raggio fisso) oppure ricerca in tutta Milano ------------------
  const pos = `lat=${position.lat}&lon=${position.lon}`;
  const requestUrl = useMemo(() => {
    if (!searchMode) return `/api/nearby?${pos}&radius=${RADIUS}&v=${revision}`;
    const params = new URLSearchParams({ q: trimmedQuery, lat: String(position.lat), lon: String(position.lon) });
    const [kind, slug] = type.split(":");
    if (kind === "macro") params.set("macro", slug);
    if (kind === "category") params.set("category", slug);
    return `/api/search?${params}&v=${revision}`;
  }, [searchMode, pos, trimmedQuery, type, position, revision]);

  const [result, setResult] = useState<ListResult>({ key: "", places: [], truncated: false });
  const loading = result.key !== requestUrl;

  useEffect(() => {
    const controller = new AbortController();
    // Mentre si scrive si aspettano 250 ms tra un tasto e l'altro
    const timer = setTimeout(
      () => {
        fetch(requestUrl, { signal: controller.signal })
          .then((r) => r.json())
          .then((data) => setResult({ key: requestUrl, places: data.places ?? [], truncated: !!data.truncated }))
          .catch((e) => e.name !== "AbortError" && console.error(e));
      },
      searchMode ? 250 : 0,
    );
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [requestUrl, searchMode]);

  useEffect(() => {
    fetch("/api/categories")
      .then((r) => r.json())
      .then((d) => setCategories((d.categories ?? []).filter((c: Category) => c.isPublic)))
      .catch(console.error);
  }, []);

  const macros = useMemo(() => {
    const seen = new Map<string, string>();
    for (const c of categories) seen.set(c.macro, c.macroName);
    return [...seen.entries()];
  }, [categories]);

  const visible = useMemo(
    () => result.places.filter((p) => !openOnly || p.openNow === true),
    [result.places, openOnly],
  );
  const openCount = useMemo(() => result.places.filter((p) => p.openNow === true).length, [result.places]);

  // --- Posizione ------------------------------------------------------------------
  const goToMyPosition = () =>
    requestPosition((p, message) => {
      setGeoMessage(message);
      if (!p) return;
      setPosition(p);
      map.current?.flyTo({ center: [p.lon, p.lat], zoom: 16 });
    });

  // --- Mappa --------------------------------------------------------------------
  useEffect(() => {
    if (!mapContainer.current || map.current) return;
    const m = new MapLibreMap({
      container: mapContainer.current,
      style: "https://tiles.openfreemap.org/styles/positron",
      center: [DEFAULT_POSITION.lon, DEFAULT_POSITION.lat],
      zoom: 15.5,
      attributionControl: { compact: true },
    });
    m.addControl(new NavigationControl({ showCompass: false }), "top-right");

    m.on("load", () => {
      m.addSource("areas", { type: "geojson", data: "/api/areas" });
      m.addLayer({
        id: "areas-line",
        type: "line",
        source: "areas",
        paint: { "line-color": "#1c7ed6", "line-opacity": 0.45, "line-width": 1.5, "line-dasharray": [3, 2] },
      });

      m.addSource("radius", { type: "geojson", data: circleGeoJSON(DEFAULT_POSITION, RADIUS) });
      m.addLayer({
        id: "radius-fill",
        type: "fill",
        source: "radius",
        paint: { "fill-color": "#1c7ed6", "fill-opacity": 0.06 },
      });
      m.addLayer({
        id: "radius-line",
        type: "line",
        source: "radius",
        paint: { "line-color": "#1c7ed6", "line-opacity": 0.4, "line-width": 1.5 },
      });

      m.addSource("places", { type: "geojson", data: { type: "FeatureCollection", features: [] } });
      m.addLayer({
        id: "places",
        type: "circle",
        source: "places",
        paint: {
          // lo zoom deve stare al livello più esterno dell'espressione
          "circle-radius": [
            "interpolate", ["linear"], ["zoom"],
            12, ["case", ["get", "selected"], 9, 3],
            16, ["case", ["get", "selected"], 9, 5.5],
          ],
          "circle-color": ["get", "color"],
          "circle-opacity": ["case", ["==", ["get", "open"], "closed"], 0.45, 0.95],
          "circle-stroke-width": ["case", ["get", "selected"], 3, 1.5],
          "circle-stroke-color": "#ffffff",
        },
      });

      m.addSource("me", {
        type: "geojson",
        data: { type: "Point", coordinates: [DEFAULT_POSITION.lon, DEFAULT_POSITION.lat] },
      });
      m.addLayer({
        id: "me",
        type: "circle",
        source: "me",
        paint: {
          "circle-radius": 8,
          "circle-color": "#1c7ed6",
          "circle-stroke-width": 3,
          "circle-stroke-color": "#ffffff",
        },
      });
      setMapReady(true);

      // All'apertura: prova a usare la posizione reale
      requestPosition((p, message) => {
        setGeoMessage(message);
        if (!p) return;
        setPosition(p);
        m.jumpTo({ center: [p.lon, p.lat] });
      });
    });

    m.on("click", "places", (e: MapLayerMouseEvent) => {
      const id = e.features?.[0]?.properties?.id as string | undefined;
      if (id) setSelected(id);
    });
    m.on("click", (e: MapMouseEvent) => {
      if (m.queryRenderedFeatures(e.point, { layers: ["places"] }).length) return;
      setPosition({ lat: e.lngLat.lat, lon: e.lngLat.lng });
    });
    m.on("mouseenter", "places", () => (m.getCanvas().style.cursor = "pointer"));
    m.on("mouseleave", "places", () => (m.getCanvas().style.cursor = ""));

    map.current = m;
    return () => {
      m.remove();
      map.current = null;
      setMapReady(false);
    };
  }, []);

  // Aggiornamento layer quando cambiano dati, filtri o selezione
  useEffect(() => {
    const m = map.current;
    if (!m || !mapReady) return;
    (m.getSource("me") as GeoJSONSource).setData({ type: "Point", coordinates: [position.lon, position.lat] });
    (m.getSource("radius") as GeoJSONSource).setData(
      searchMode ? { type: "FeatureCollection", features: [] } : circleGeoJSON(position, RADIUS),
    );
    (m.getSource("places") as GeoJSONSource).setData({
      type: "FeatureCollection",
      features: visible.map((p) => ({
        type: "Feature",
        properties: {
          id: p.id,
          color: MACRO_COLORS[p.macro] ?? "#868e96",
          open: p.openNow === null ? "unknown" : p.openNow ? "open" : "closed",
          selected: p.id === selected,
        },
        geometry: { type: "Point", coordinates: [p.lon, p.lat] },
      })),
    });
  }, [mapReady, position, visible, selected, searchMode]);

  // Nuovi risultati di ricerca: inquadra tutti i risultati
  useEffect(() => {
    const m = map.current;
    if (!m || !mapReady || !searchMode || loading || result.places.length === 0) return;
    const bounds = new LngLatBounds();
    for (const p of result.places) bounds.extend([p.lon, p.lat]);
    bounds.extend([position.lon, position.lat]);
    m.fitBounds(bounds, { padding: 60, maxZoom: 16, duration: 600 });
    // solo quando arrivano risultati nuovi
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [result.key]);

  // Porta in vista nella lista l'attività selezionata
  useEffect(() => {
    if (selected) listRefs.current[selected]?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [selected, visible]);

  // Con il pannello aperto a destra (desktop) il punto va centrato nella parte visibile.
  // offset e non padding: il padding di MapLibre resterebbe anche a pannello chiuso.
  const panelOffset = (): [number, number] => [window.innerWidth >= 640 ? -230 : 0, 0];

  const select = (p: NearbyPlace) => {
    setSelected(p.id);
    map.current?.flyTo({ center: [p.lon, p.lat], zoom: Math.max(map.current.getZoom(), 16), offset: panelOffset() });
  };

  const clearSearch = () => {
    setQuery("");
    setType("");
    map.current?.flyTo({ center: [position.lon, position.lat], zoom: 15.5 });
  };

  const typeLabel = type
    ? type.startsWith("macro:")
      ? macros.find(([slug]) => `macro:${slug}` === type)?.[1]
      : categories.find((c) => `category:${c.slug}` === type)?.name
    : null;

  return (
    <div className="flex h-dvh w-full flex-col overflow-hidden md:flex-row">
      <div className="relative h-[45dvh] shrink-0 md:order-2 md:h-full md:flex-1">
        <div ref={mapContainer} className="h-full w-full" />
        <div className="absolute bottom-3 left-3 rounded-md bg-white/90 px-2 py-1 text-xs text-zinc-600 shadow">
          Tocca la mappa per spostarti · dati nella zona tratteggiata
        </div>
      </div>

      <aside className="flex min-h-0 min-w-0 flex-1 flex-col border-zinc-200 bg-white md:order-1 md:w-[420px] md:flex-none md:border-r">
        <header className="space-y-3 border-b border-zinc-200 p-4">
          <div className="flex items-center justify-between">
            <h1 className="text-xl font-semibold tracking-tight">ONQI</h1>
            <button
              type="button"
              onClick={goToMyPosition}
              className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-50"
            >
              Usa la mia posizione
            </button>
          </div>
          {geoMessage && <p className="text-xs text-amber-700">{geoMessage}</p>}

          <div className="space-y-2">
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Cerca un luogo per nome"
              aria-label="Cerca un luogo per nome"
              className="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-zinc-500"
            />
            <div className="flex items-center gap-3">
              <select
                value={type}
                onChange={(e) => setType(e.target.value)}
                aria-label="Tipologia di attività"
                className="min-w-0 flex-1 rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-sm"
              >
                <option value="">Tutte le tipologie</option>
                {macros.map(([slug, name]) => (
                  <optgroup key={slug} label={name}>
                    <option value={`macro:${slug}`}>{name}: tutto</option>
                    {categories
                      .filter((c) => c.macro === slug)
                      .map((c) => (
                        <option key={c.slug} value={`category:${c.slug}`}>
                          {c.name}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </select>
              <label className="flex shrink-0 items-center gap-1.5 text-sm">
                <input type="checkbox" checked={openOnly} onChange={(e) => setOpenOnly(e.target.checked)} />
                Aperti ora
              </label>
            </div>
          </div>

          <div className="flex items-center justify-between gap-2 text-xs text-zinc-500">
            <span>
              {loading
                ? "Caricamento…"
                : searchMode
                  ? `${visible.length} risultati in tutta Milano${typeLabel ? ` · ${typeLabel}` : ""}`
                  : `${visible.length} attività entro ${RADIUS} m · ${openCount} aperte ora`}
            </span>
            {searchMode && (
              <button type="button" onClick={clearSearch} className="shrink-0 text-blue-700 hover:underline">
                Torna a vicino a me
              </button>
            )}
          </div>
          {result.truncated && !searchMode && (
            <p className="text-xs text-amber-700">Mostro le {result.places.length} più vicine.</p>
          )}
        </header>

        <ul className="min-h-0 flex-1 divide-y divide-zinc-100 overflow-y-auto">
          {!loading && visible.length === 0 && (
            <li className="px-4 py-6 text-sm text-zinc-500">
              {searchMode
                ? "Nessun risultato. Prova un altro nome o un'altra tipologia."
                : `Nessuna attività entro ${RADIUS} m da qui. I dati coprono tutto il comune di Milano: sposta la mappa o usa la ricerca.`}
            </li>
          )}
          {visible.map((p) => (
            <li
              key={p.id}
              ref={(el) => {
                listRefs.current[p.id] = el;
              }}
              onClick={() => select(p)}
              className={`cursor-pointer px-4 py-3 ${p.id === selected ? "bg-blue-50" : "hover:bg-zinc-50"}`}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate font-medium">{p.name}</p>
                  <p className="flex min-w-0 items-center gap-1.5 text-xs text-zinc-500">
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: MACRO_COLORS[p.macro] }} />
                    {p.categoryName}
                    {p.address && <span className="min-w-0 truncate">· {p.address}</span>}
                  </p>
                </div>
                <span className="shrink-0 text-xs tabular-nums text-zinc-500">{formatDistance(p.distance)}</span>
              </div>

              <div className="mt-1.5 flex flex-wrap items-center gap-2">
                <OpenBadge openNow={p.openNow} />
                {p.sources.includes("comune") && (
                  <span className="rounded bg-blue-50 px-1.5 py-0.5 text-xs text-blue-700" title="Censito negli elenchi del Comune di Milano">
                    censito dal Comune
                  </span>
                )}
                {p.hoursToday && <span className="text-xs text-zinc-500">oggi {p.hoursToday}</span>}
                {p.promos.map((promo) => (
                  <span key={promo.title} className="rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-800">
                    {promo.title}
                  </span>
                ))}
              </div>
            </li>
          ))}
        </ul>

        {selected && (
          <PlacePanel
            key={selected}
            placeId={selected}
            onClose={() => setSelected(null)}
            onSaved={() => setRevision((r) => r + 1)}
          />
        )}

        <footer className="border-t border-zinc-200 px-4 py-2 text-[11px] text-zinc-400">
          Dati © OpenStreetMap contributors (ODbL), Overture Maps Foundation, Comune di Milano (CC BY)
        </footer>
      </aside>
    </div>
  );
}
