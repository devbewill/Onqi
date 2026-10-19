"use client";

import { useEffect, useState, type ReactNode } from "react";
import type { HoursRow, PlaceDetail, PlacePatch, SourceRecord } from "@/lib/place-detail";

type Category = { id: number; name: string; macro: string; macroName: string; isPublic: boolean };

const WEEKDAYS = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"];

const SOURCE_LABELS: Record<string, string> = {
  overture: "Overture Maps",
  osm: "OpenStreetMap",
  comune: "Comune di Milano",
};

const STATUS_LABELS: Record<string, string> = {
  active: "Attiva",
  unverified: "Da verificare",
  closed: "Chiusa / non esiste più",
};

const REASON_LABELS: Record<string, string> = {
  categoria: "la categoria non è aperta al pubblico",
  sede_legale: "probabile sede legale (solo registro imprese)",
  manuale: "impostato a mano",
};

// Dettagli extra: valore manuale (places.attributes) o, in mancanza, tag OSM.
const YES_NO = [
  { value: "yes", label: "Sì" },
  { value: "no", label: "No" },
];
const ATTRIBUTES: { key: string; label: string; osm: string; options?: { value: string; label: string }[] }[] = [
  { key: "description", label: "Descrizione", osm: "description" },
  { key: "cuisine", label: "Cucina", osm: "cuisine" },
  {
    key: "wheelchair",
    label: "Accessibile in sedia a rotelle",
    osm: "wheelchair",
    options: [...YES_NO, { value: "limited", label: "In parte" }],
  },
  { key: "outdoor_seating", label: "Tavoli all'aperto", osm: "outdoor_seating", options: YES_NO },
  { key: "takeaway", label: "Asporto", osm: "takeaway", options: YES_NO },
  { key: "delivery", label: "Consegna a domicilio", osm: "delivery", options: YES_NO },
  { key: "payment_cards", label: "Pagamento con carta", osm: "payment:credit_cards", options: YES_NO },
  { key: "wifi", label: "Wi-Fi", osm: "internet_access", options: YES_NO },
];

function osmTags(sources: SourceRecord[]): Record<string, string> {
  return (sources.find((s) => s.source === "osm")?.raw as Record<string, string>) ?? {};
}

function osmValue(tags: Record<string, string>, key: string) {
  const v = tags[key];
  if (key === "internet_access" && v) return v === "no" ? "no" : "yes";
  return v ?? null;
}

function optionLabel(options: { value: string; label: string }[] | undefined, v: string) {
  return options?.find((o) => o.value === v)?.label ?? v;
}

// --- Orari ------------------------------------------------------------------------

function hoursToText(hours: HoursRow[], weekday: number) {
  return hours
    .filter((h) => h.weekday === weekday)
    .map((h) => `${h.opens}-${h.closes}`)
    .join(", ");
}

const INTERVAL = /^(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})$/;

function parseDay(text: string): { opens: string; closes: string }[] | null {
  const t = text.trim().toLowerCase();
  if (t === "" || t === "chiuso") return [];
  const out = [];
  for (const part of t.split(",")) {
    const m = part.trim().match(INTERVAL);
    if (!m) return null;
    const pad = (h: string, mm: string) => `${h.padStart(2, "0")}:${mm}`;
    out.push({ opens: pad(m[1], m[2]), closes: pad(m[3], m[4]) });
  }
  return out;
}

// --- Componenti di base --------------------------------------------------------------

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border-b border-zinc-100 px-5 py-4">
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-zinc-500">{title}</h3>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function Missing() {
  return <span className="text-sm text-zinc-400">Non presente</span>;
}

function LockedTag() {
  return <span className="ml-1.5 rounded bg-amber-50 px-1 py-0.5 text-[10px] text-amber-700">modificato a mano</span>;
}

function EditButton({ empty, onClick }: { empty: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="shrink-0 text-xs text-blue-700 hover:underline">
      {empty ? "Aggiungi" : "Modifica"}
    </button>
  );
}

function SaveCancel({ saving, onCancel }: { saving: boolean; onCancel: () => void }) {
  return (
    <div className="mt-1.5 flex gap-2">
      <button
        type="submit"
        disabled={saving}
        className="rounded-md bg-zinc-900 px-3 py-1 text-xs text-white disabled:opacity-50"
      >
        {saving ? "Salvo…" : "Salva"}
      </button>
      <button type="button" onClick={onCancel} className="rounded-md px-3 py-1 text-xs text-zinc-600 hover:bg-zinc-100">
        Annulla
      </button>
    </div>
  );
}

type SaveFn = (patch: PlacePatch) => Promise<void>;

function EditableField({
  label,
  value,
  locked,
  onSave,
  multiline,
  render,
  hint,
}: {
  label: string;
  value: string | null;
  locked?: boolean;
  onSave: (v: string) => Promise<void>;
  multiline?: boolean;
  render?: (v: string) => ReactNode;
  hint?: string;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await onSave(draft);
      setEditing(false);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-xs text-zinc-500">
          {label}
          {locked && <LockedTag />}
        </span>
        {!editing && (
          <EditButton
            empty={!value}
            onClick={() => {
              setDraft(value ?? "");
              setEditing(true);
            }}
          />
        )}
      </div>
      {editing ? (
        <form onSubmit={submit} className="mt-1">
          {multiline ? (
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              rows={3}
              autoFocus
              className="w-full rounded-md border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-500"
            />
          ) : (
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              autoFocus
              className="w-full rounded-md border border-zinc-300 px-2 py-1.5 text-sm outline-none focus:border-zinc-500"
            />
          )}
          {hint && <p className="mt-1 text-[11px] text-zinc-400">{hint}</p>}
          {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
          <SaveCancel saving={saving} onCancel={() => setEditing(false)} />
        </form>
      ) : (
        <div className="mt-0.5 break-words text-sm">{value ? (render ? render(value) : value) : <Missing />}</div>
      )}
    </div>
  );
}

function SelectField({
  label,
  value,
  display,
  locked,
  children,
  onSave,
}: {
  label: string;
  value: string;
  display: ReactNode;
  locked?: boolean;
  children: ReactNode;
  onSave: (v: string) => Promise<void>;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await onSave(draft);
      setEditing(false);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-xs text-zinc-500">
          {label}
          {locked && <LockedTag />}
        </span>
        {!editing && (
          <EditButton
            empty={!value}
            onClick={() => {
              setDraft(value);
              setEditing(true);
            }}
          />
        )}
      </div>
      {editing ? (
        <form onSubmit={submit} className="mt-1">
          <select
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            autoFocus
            className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-sm"
          >
            {children}
          </select>
          {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
          <SaveCancel saving={saving} onCancel={() => setEditing(false)} />
        </form>
      ) : (
        <div className="mt-0.5 text-sm">{display}</div>
      )}
    </div>
  );
}

function HoursEditor({ hours, onSave }: { hours: HoursRow[]; onSave: SaveFn }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const manual = hours.some((h) => h.source === "manual");

  const start = () => {
    setDraft(WEEKDAYS.map((_, i) => hoursToText(hours, i + 1)));
    setError(null);
    setEditing(true);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const openingHours = [];
    for (let i = 0; i < 7; i++) {
      const parsed = parseDay(draft[i]);
      if (!parsed) {
        setError(`${WEEKDAYS[i]}: usa il formato 09:00-13:00, 15:00-19:00 (vuoto = chiuso)`);
        return;
      }
      openingHours.push(...parsed.map((p) => ({ weekday: i + 1, ...p })));
    }
    setSaving(true);
    setError(null);
    try {
      await onSave({ openingHours });
      setEditing(false);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  if (editing) {
    return (
      <form onSubmit={submit} className="space-y-1.5">
        {WEEKDAYS.map((day, i) => (
          <label key={day} className="flex items-center gap-2 text-sm">
            <span className="w-20 shrink-0 text-zinc-600">{day}</span>
            <input
              value={draft[i]}
              onChange={(e) => setDraft(draft.map((d, j) => (j === i ? e.target.value : d)))}
              placeholder="chiuso"
              className="w-full rounded-md border border-zinc-300 px-2 py-1 text-sm outline-none focus:border-zinc-500"
            />
          </label>
        ))}
        <p className="text-[11px] text-zinc-400">Esempio: 09:00-13:00, 15:00-19:00. Dopo mezzanotte: 18:00-02:00.</p>
        {error && <p className="text-xs text-red-600">{error}</p>}
        <SaveCancel saving={saving} onCancel={() => setEditing(false)} />
      </form>
    );
  }

  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between">
        <span className="text-xs text-zinc-500">
          {hours.length ? `Fonte: ${manual ? "inseriti a mano" : "OpenStreetMap"}` : "Orari settimanali"}
          {manual && <LockedTag />}
        </span>
        <EditButton empty={!hours.length} onClick={start} />
      </div>
      {hours.length ? (
        <table className="w-full text-sm">
          <tbody>
            {WEEKDAYS.map((day, i) => (
              <tr key={day}>
                <td className="w-24 py-0.5 text-zinc-600">{day}</td>
                <td className="py-0.5">{hoursToText(hours, i + 1) || <span className="text-zinc-400">chiuso</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <Missing />
      )}
    </div>
  );
}

function SourceCard({ s }: { s: SourceRecord }) {
  const raw = s.raw ?? {};
  let summary: ReactNode = null;
  let link: string | null = null;
  if (s.source === "osm") {
    link = `https://www.openstreetmap.org/${s.sourceId}`;
    summary = `${Object.keys(raw).length} tag`;
  } else if (s.source === "overture") {
    const datasets = ((raw.sources as { dataset: string }[]) ?? [])
      .map((x) => x.dataset)
      .filter((d) => d !== "Overture");
    summary = `categoria ${raw.category ?? raw.basic_category} · da ${datasets.join(", ") || "?"} · release ${raw.release}`;
  } else if (s.source === "comune") {
    summary = [
      raw.dataset === "vicinato" ? "esercizio di vicinato" : "pubblico esercizio",
      raw.insegna && `insegna "${raw.insegna}"`,
      `${raw.via} ${raw.civico}`,
      raw.superficie && `${raw.superficie} m²`,
    ]
      .filter(Boolean)
      .join(" · ");
  }

  return (
    <div className="rounded-md border border-zinc-200 p-2.5 text-sm">
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-medium">{SOURCE_LABELS[s.source] ?? s.source}</span>
        {link ? (
          <a href={link} target="_blank" rel="noreferrer" className="truncate text-xs text-blue-700 underline">
            {s.sourceId}
          </a>
        ) : (
          <span className="truncate text-xs text-zinc-400">{s.sourceId}</span>
        )}
      </div>
      {summary && <p className="mt-0.5 text-xs text-zinc-600">{summary}</p>}
      <details className="mt-1">
        <summary className="cursor-pointer text-xs text-zinc-500">Tutti i dati salvati</summary>
        <pre className="mt-1 max-h-64 overflow-auto rounded bg-zinc-50 p-2 text-[11px] leading-snug">
          {JSON.stringify(raw, null, 2)}
        </pre>
      </details>
    </div>
  );
}

// --- Pannello ---------------------------------------------------------------------

export default function PlacePanel({
  placeId,
  onClose,
  onSaved,
}: {
  placeId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [detail, setDetail] = useState<PlaceDetail | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);

  useEffect(() => {
    const controller = new AbortController();
    fetch(`/api/places/${placeId}`, { signal: controller.signal })
      .then(async (r) => {
        const data = await r.json();
        if (!r.ok) throw new Error(data.error ?? "Errore nel caricamento");
        setDetail(data);
      })
      .catch((e) => e.name !== "AbortError" && setLoadError(e.message));
    return () => controller.abort();
  }, [placeId]);

  useEffect(() => {
    fetch("/api/categories")
      .then((r) => r.json())
      .then((d) => setCategories(d.categories ?? []))
      .catch(console.error);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const save: SaveFn = async (patch) => {
    const r = await fetch(`/api/places/${placeId}`, {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(patch),
    });
    const data = await r.json();
    if (!r.ok) throw new Error(data.error ?? "Salvataggio non riuscito");
    setDetail(data);
    onSaved();
  };

  const d = detail;
  const locked = (f: string) => !!d?.lockedFields.includes(f);
  const tags = d ? osmTags(d.sources) : {};
  const macros = [...new Set(categories.map((c) => c.macroName))];

  return (
    <aside
      className="panel-enter fixed inset-y-0 right-0 z-30 flex w-full flex-col border-l border-zinc-200 bg-white shadow-2xl sm:w-[460px]"
      aria-label="Scheda attività"
    >
      <header className="flex items-start justify-between gap-3 border-b border-zinc-200 px-5 py-4">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold leading-tight">{d?.name ?? (loadError ? "Errore" : "Caricamento…")}</h2>
          {d && (
            <p className="mt-0.5 text-sm text-zinc-500">
              {d.categoryName} · {d.macroName}
            </p>
          )}
          {d && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {d.openNow === true && (
                <span className="rounded bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800">aperto ora</span>
              )}
              {d.openNow === false && (
                <span className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs font-medium text-zinc-600">chiuso ora</span>
              )}
              {d.sources.some((s) => s.source === "comune") && (
                <span className="rounded bg-blue-50 px-1.5 py-0.5 text-xs text-blue-700">censito dal Comune</span>
              )}
              {!d.isPublic && (
                <span className="rounded bg-red-50 px-1.5 py-0.5 text-xs text-red-700">non aperto al pubblico</span>
              )}
              {d.status === "closed" && (
                <span className="rounded bg-red-50 px-1.5 py-0.5 text-xs text-red-700">chiusa</span>
              )}
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label="Chiudi"
          className="-mr-1 rounded-md p-1 text-xl leading-none text-zinc-500 hover:bg-zinc-100"
        >
          ×
        </button>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {loadError && <p className="p-5 text-sm text-red-600">{loadError}</p>}
        {d && (
          <>
            <Section title="Scheda">
              <EditableField label="Nome" value={d.name} locked={locked("name")} onSave={(v) => save({ name: v })} />
              <SelectField
                label="Categoria"
                value={String(d.categoryId)}
                locked={locked("category_id")}
                display={`${d.categoryName} (${d.macroName})`}
                onSave={(v) => save({ categoryId: Number(v) })}
              >
                {macros.map((m) => (
                  <optgroup key={m} label={m}>
                    {categories
                      .filter((c) => c.macroName === m)
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </SelectField>
              <EditableField
                label="Partita IVA"
                value={d.vatNumber}
                locked={locked("vat_number")}
                onSave={(v) => save({ vatNumber: v })}
                hint="11 cifre, verificata con la cifra di controllo"
              />
            </Section>

            <Section title="Indirizzo e contatti">
              <EditableField label="Indirizzo" value={d.address} locked={locked("address")} onSave={(v) => save({ address: v })} />
              <EditableField label="CAP" value={d.postcode} locked={locked("postcode")} onSave={(v) => save({ postcode: v })} />
              <EditableField
                label="Telefono"
                value={d.phone}
                locked={locked("phone")}
                onSave={(v) => save({ phone: v })}
                render={(v) => (
                  <a href={`tel:${v.replace(/\s/g, "")}`} className="text-blue-700 underline">
                    {v}
                  </a>
                )}
              />
              <EditableField
                label="Sito web"
                value={d.website}
                locked={locked("website")}
                onSave={(v) => save({ website: v })}
                render={(v) => (
                  <a href={v} target="_blank" rel="noreferrer" className="text-blue-700 underline">
                    {v}
                  </a>
                )}
              />
              <EditableField
                label="Email"
                value={d.email}
                locked={locked("email")}
                onSave={(v) => save({ email: v })}
                render={(v) => (
                  <a href={`mailto:${v}`} className="text-blue-700 underline">
                    {v}
                  </a>
                )}
              />
              <EditableField
                label="Social"
                value={d.socials?.join("\n") ?? null}
                locked={locked("socials")}
                multiline
                hint="Un indirizzo per riga (Instagram, Facebook...)"
                onSave={(v) => save({ socials: v.split("\n").map((s) => s.trim()).filter(Boolean) })}
                render={(v) => (
                  <span className="block space-y-0.5">
                    {v.split("\n").map((u) => (
                      <a key={u} href={u} target="_blank" rel="noreferrer" className="block truncate text-blue-700 underline">
                        {u.replace(/^https?:\/\/(www\.)?/, "")}
                      </a>
                    ))}
                  </span>
                )}
              />
            </Section>

            <Section title="Orari">
              <HoursEditor hours={d.hours} onSave={save} />
            </Section>

            <Section title="Dettagli">
              {ATTRIBUTES.map((a) => {
                const manual = d.attributes[a.key] ?? null;
                const fromOsm = osmValue(tags, a.osm);
                const value = manual ?? fromOsm;
                const label = manual === null && fromOsm !== null ? `${a.label} (da OSM)` : a.label;
                if (a.options) {
                  return (
                    <SelectField
                      key={a.key}
                      label={label}
                      value={value ?? ""}
                      locked={manual !== null}
                      display={value ? optionLabel(a.options, value) : <Missing />}
                      onSave={(v) => save({ attributes: { [a.key]: v || null } })}
                    >
                      <option value="">Non indicato</option>
                      {a.options.map((o) => (
                        <option key={o.value} value={o.value}>
                          {o.label}
                        </option>
                      ))}
                    </SelectField>
                  );
                }
                return (
                  <EditableField
                    key={a.key}
                    label={label}
                    value={value}
                    locked={manual !== null}
                    multiline={a.key === "description"}
                    onSave={(v) => save({ attributes: { [a.key]: v || null } })}
                  />
                );
              })}
            </Section>

            <Section title="Stato e visibilità">
              <SelectField
                label="Stato"
                value={d.status}
                locked={locked("status")}
                display={STATUS_LABELS[d.status] ?? d.status}
                onSave={(v) => save({ status: v })}
              >
                {Object.entries(STATUS_LABELS).map(([v, l]) => (
                  <option key={v} value={v}>
                    {l}
                  </option>
                ))}
              </SelectField>
              <SelectField
                label="Esercizio aperto al pubblico"
                value={d.isPublic ? "yes" : "no"}
                locked={locked("is_public")}
                display={
                  d.isPublic
                    ? "Sì, visibile nell'app"
                    : `No, nascosto${d.nonPublicReason ? `: ${REASON_LABELS[d.nonPublicReason]}` : ""}`
                }
                onSave={(v) => save({ isPublic: v === "yes" })}
              >
                <option value="yes">Sì, mostralo nell&apos;app</option>
                <option value="no">No, nascondilo</option>
              </SelectField>
            </Section>

            <Section title="Fonti e dati salvati">
              {d.sources.map((s) => (
                <SourceCard key={`${s.source}:${s.sourceId}`} s={s} />
              ))}
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs text-zinc-600">
                <dt className="text-zinc-400">Coordinate</dt>
                <dd>
                  {d.lat.toFixed(6)}, {d.lon.toFixed(6)}
                </dd>
                <dt className="text-zinc-400">Catena</dt>
                <dd>{d.brand ?? "—"}</dd>
                <dt className="text-zinc-400">Affidabilità fonte</dt>
                <dd>{d.confidence !== null ? d.confidence.toFixed(2) : "—"}</dd>
                <dt className="text-zinc-400">Aggiornata</dt>
                <dd>{new Date(d.updatedAt).toLocaleString("it-IT")}</dd>
                <dt className="text-zinc-400">ID Onqi</dt>
                <dd className="truncate">{d.id}</dd>
              </dl>
            </Section>

            {d.edits.length > 0 && (
              <Section title="Modifiche manuali">
                <ul className="space-y-1 text-xs text-zinc-600">
                  {d.edits.map((e, i) => (
                    <li key={i}>
                      <span className="text-zinc-400">{new Date(e.createdAt).toLocaleString("it-IT")}</span> · {e.field}
                    </li>
                  ))}
                </ul>
              </Section>
            )}
          </>
        )}
      </div>
    </aside>
  );
}
