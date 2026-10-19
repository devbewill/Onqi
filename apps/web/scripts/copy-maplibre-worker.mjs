// MapLibre v6 carica il worker da un file separato, che il bundler non include:
// lo serviamo da public/ (vedi setWorkerUrl in app/explorer.tsx).
import { copyFileSync, mkdirSync } from "node:fs";

mkdirSync("public/maplibre", { recursive: true });
copyFileSync("node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs", "public/maplibre/maplibre-gl-worker.mjs");
