"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
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

// Naviglio Grande, all'altezza della Darsena: dentro il CAP 20143 importato.
const DEFAULT_POSITION = { lat: 45.4515, lon: 9.1745 };

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
type PlacesResult = { key: string; places: NearbyPlace[]; truncated: boolean };

function OpenBadge({ openNow }: { openNow: boolean | null }) {
  if (openNow === null) return <span className="text-xs text-zinc-400">orari n.d.</span>;
  return openNow ? (
    <span className="rounded bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800">aperto ora</span>
  ) : (
    <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs font-medium text-zinc-600">chiuso</span>
  );
}

function formatDistance(m: number) {
  return m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1)} km`;
}

export default function Explorer() {
  const mapContainer = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const listRefs = useRef<Record<string, HTMLLIElement | null>>({});

  const [position, setPosition] = useState<Position>(DEFAULT_POSITION);
  // Rettangolo visibile della mappa (ovest,sud,est,nord), aggiornato a fine spostamento
  const [bbox, setBbox] = useState<string | null>(null);
  const [result, setResult] = useState<PlacesResult>({ key: "", places: [], truncated: false });
  const [macro, setMacro] = useState<string | null>(null);
  const [openOnly, setOpenOnly] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const [geoError, setGeoError] = useState<string | null>(null);
  const [mapReady, setMapReady] = useState(false);
  // Incrementato dopo una modifica manuale, per ricaricare la lista
  const [revision, setRevision] = useState(0);

  const [query, setQuery] = useState("");
  const [searchResult, setSearchResult] = useState<{ q: string; places: NearbyPlace[] }>({ q: "", places: [] });
  const [searchOpen, setSearchOpen] = useState(false);

  // --- Attività nel rettangolo visibile --------------------------------------
  const requestKey = bbox ? `bbox=${bbox}&lat=${position.lat}&lon=${position.lon}&v=${revision}` : null;
  const loading = requestKey !== null && result.key !== requestKey;
  const places = result.places;

  useEffect(() => {
    if (!requestKey) return;
    const controller = new AbortController();
    fetch(`/api/places?${requestKey}`, { signal: controller.signal })
      .then((r) => r.json())
      .then((data) => setResult({ key: requestKey, places: data.places ?? [], truncated: !!data.truncated }))
      .catch((e) => e.name !== "AbortError" && console.error(e));
    return () => controller.abort();
  }, [requestKey]);

  // --- Ricerca per nome (con attesa di 250 ms tra un tasto e l'altro) -----------
  const trimmedQuery = query.trim();
  const searching = trimmedQuery.length >= 2 && searchResult.q !== trimmedQuery;
  const suggestions = trimmedQuery.length >= 2 ? searchResult.places : [];

  useEffect(() => {
    if (trimmedQuery.length < 2) return;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      const params = new URLSearchParams({ q: trimmedQuery, lat: String(position.lat), lon: String(position.lon) });
      fetch(`/api/search?${params}`, { signal: controller.signal })
        .then((r) => r.json())
        .then((data) => setSearchResult({ q: trimmedQuery, places: data.places ?? [] }))
        .catch((e) => e.name !== "AbortError" && console.error(e));
    }, 250);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [trimmedQuery, position]);

  const macros = useMemo(() => {
    const counts = new Map<string, { name: string; n: number }>();
    for (const p of places) {
      const c = counts.get(p.macro) ?? { name: p.macroName, n: 0 };
      c.n++;
      counts.set(p.macro, c);
    }
    return [...counts.entries()].sort((a, b) => b[1].n - a[1].n);
  }, [places]);

  const visible = useMemo(
    () => places.filter((p) => (!macro || p.macro === macro) && (!openOnly || p.openNow === true)),
    [places, macro, openOnly],
  );

  const openCount = useMemo(() => places.filter((p) => p.openNow === true).length, [places]);

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

    const updateBbox = () => {
      const b = m.getBounds();
      setBbox([b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].map((v) => v.toFixed(5)).join(","));
    };

    m.on("load", () => {
      m.addSource("areas", { type: "geojson", data: "/api/areas" });
      m.addLayer({
        id: "areas-fill",
        type: "fill",
        source: "areas",
        paint: { "fill-color": "#1c7ed6", "fill-opacity": 0.04 },
      });
      m.addLayer({
        id: "areas-line",
        type: "line",
        source: "areas",
        paint: { "line-color": "#1c7ed6", "line-opacity": 0.5, "line-width": 1.5, "line-dasharray": [3, 2] },
      });
      m.addLayer({
        id: "areas-label",
        type: "symbol",
        source: "areas",
        layout: {
          "text-field": ["concat", "CAP ", ["get", "postcode"]],
          "text-font": ["Noto Sans Regular"], // font disponibile su OpenFreeMap
          "text-size": 12,
        },
        paint: { "text-color": "#1c7ed6", "text-halo-color": "#ffffff", "text-halo-width": 1.5 },
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
            13, ["case", ["get", "selected"], 9, 2.5],
            16, ["case", ["get", "selected"], 9, 5.5],
          ],
          "circle-color": ["get", "color"],
          "circle-opacity": ["case", ["==", ["get", "open"], "closed"], 0.45, 0.95],
          "circle-stroke-width": [
            "interpolate", ["linear"], ["zoom"],
            13, ["case", ["get", "selected"], 3, 0.5],
            16, ["case", ["get", "selected"], 3, 1.5],
          ],
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
      updateBbox();
    });

    m.on("moveend", updateBbox);
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
    (m.getSource("me") as GeoJSONSource).setData({
      type: "Point",
      coordinates: [position.lon, position.lat],
    });
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
  }, [mapReady, position, visible, selected]);

  // Porta in vista nella lista l'attività selezionata (anche dopo il caricamento della zona)
  useEffect(() => {
    if (selected) listRefs.current[selected]?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [selected, visible]);

  const locate = () => {
    setGeoError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const p = { lat: pos.coords.latitude, lon: pos.coords.longitude };
        setPosition(p);
        map.current?.flyTo({ center: [p.lon, p.lat], zoom: 16 });
      },
      () => setGeoError("Posizione non disponibile"),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  };

  // Con il pannello aperto a destra (desktop) il punto va centrato nella parte visibile.
  // offset e non padding: il padding di MapLibre resterebbe anche a pannello chiuso.
  const panelOffset = (): [number, number] => [window.innerWidth >= 640 ? -230 : 0, 0];

  const selectFromList = (p: NearbyPlace) => {
    setSelected(p.id);
    map.current?.easeTo({ center: [p.lon, p.lat], offset: panelOffset() });
  };

  const selectFromSearch = (p: NearbyPlace) => {
    setSearchOpen(false);
    setQuery(p.name);
    setMacro(null);
    setOpenOnly(false);
    setSelected(p.id);
    map.current?.flyTo({ center: [p.lon, p.lat], zoom: 17, offset: panelOffset() });
  };

  return (
    <div className="flex h-dvh w-full flex-col overflow-hidden md:flex-row">
      <div className="relative h-[45dvh] shrink-0 md:order-2 md:h-full md:flex-1">
        <div ref={mapContainer} className="h-full w-full" />
        <div className="absolute bottom-3 left-3 rounded-md bg-white/90 px-2 py-1 text-xs text-zinc-600 shadow">
          Tocca la mappa per spostarti · dati solo nei CAP tratteggiati
        </div>
      </div>

      <aside className="flex min-h-0 min-w-0 flex-1 flex-col border-zinc-200 bg-white md:order-1 md:w-[420px] md:flex-none md:border-r">
        <header className="space-y-3 border-b border-zinc-200 p-4">
          <div className="flex items-center justify-between">
            <h1 className="text-xl font-semibold tracking-tight">ONQI</h1>
            <button
              type="button"
              onClick={locate}
              className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm hover:bg-zinc-50"
            >
              Usa la mia posizione
            </button>
          </div>
          {geoError && <p className="text-xs text-red-600">{geoError}</p>}

          <div className="relative">
            <input
              type="search"
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                setSearchOpen(true);
              }}
              onFocus={() => setSearchOpen(true)}
              onBlur={() => setTimeout(() => setSearchOpen(false), 150)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && suggestions[0]) selectFromSearch(suggestions[0]);
                if (e.key === "Escape") setSearchOpen(false);
              }}
              placeholder="Cerca un'attività per nome"
              aria-label="Cerca un'attività per nome"
              className="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-zinc-500"
            />
            {searchOpen && trimmedQuery.length >= 2 && (
              <ul className="absolute z-10 mt-1 max-h-80 w-full overflow-y-auto rounded-md border border-zinc-200 bg-white shadow-lg">
                {suggestions.map((p) => (
                  <li key={p.id}>
                    <button
                      type="button"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => selectFromSearch(p)}
                      className="flex w-full items-start justify-between gap-3 px-3 py-2 text-left hover:bg-zinc-50"
                    >
                      <span className="min-w-0">
                        <span className="block truncate text-sm font-medium">{p.name}</span>
                        <span className="block truncate text-xs text-zinc-500">
                          {p.categoryName}
                          {p.address && ` · ${p.address}`}
                        </span>
                      </span>
                      <span className="shrink-0 text-xs tabular-nums text-zinc-500">{formatDistance(p.distance)}</span>
                    </button>
                  </li>
                ))}
                {!searching && suggestions.length === 0 && (
                  <li className="px-3 py-2 text-sm text-zinc-500">Nessuna attività trovata</li>
                )}
                {searching && suggestions.length === 0 && (
                  <li className="px-3 py-2 text-sm text-zinc-500">Ricerca…</li>
                )}
              </ul>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-1.5">
            <button
              type="button"
              onClick={() => setMacro(null)}
              className={`rounded-full px-2.5 py-1 text-xs ${
                macro === null ? "bg-zinc-900 text-white" : "bg-zinc-100 hover:bg-zinc-200"
              }`}
            >
              Tutte ({places.length})
            </button>
            {macros.map(([slug, { name, n }]) => (
              <button
                type="button"
                key={slug}
                onClick={() => setMacro(macro === slug ? null : slug)}
                className={`flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs ${
                  macro === slug ? "bg-zinc-900 text-white" : "bg-zinc-100 hover:bg-zinc-200"
                }`}
              >
                <span className="h-2 w-2 rounded-full" style={{ background: MACRO_COLORS[slug] }} />
                {name} ({n})
              </button>
            ))}
          </div>

          <div className="flex items-center justify-between text-xs text-zinc-500">
            <span>
              {loading
                ? "Caricamento…"
                : `${visible.length} attività in quest'area · ${openCount} aperte ora`}
            </span>
            <label className="flex items-center gap-1.5 text-sm text-zinc-800">
              <input type="checkbox" checked={openOnly} onChange={(e) => setOpenOnly(e.target.checked)} />
              Aperti ora
            </label>
          </div>
          {result.truncated && (
            <p className="text-xs text-amber-700">Mostro le 1000 più vicine: avvicina la mappa per vederle tutte.</p>
          )}
        </header>

        <ul className="min-h-0 flex-1 divide-y divide-zinc-100 overflow-y-auto">
          {!loading && visible.length === 0 && (
            <li className="px-4 py-6 text-sm text-zinc-500">
              Nessuna attività qui. Per ora ci sono dati solo nelle zone tratteggiate sulla mappa.
            </li>
          )}
          {visible.map((p) => (
            <li
              key={p.id}
              ref={(el) => {
                listRefs.current[p.id] = el;
              }}
              onClick={() => selectFromList(p)}
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
