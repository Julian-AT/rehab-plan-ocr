"use client";
import { useState } from "react";
import type {
  Annotation,
  Appointment,
  FieldAssessment,
  PrintedState,
  ReferenceSource,
} from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { emptyAppointment } from "@/lib/validation";
import { command } from "@/lib/native";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { fieldLabels } from "@/features/simple/appointment-sheet";

const fields = [
  "date",
  "start",
  "end",
  "title",
  "location",
  "therapist",
  "notes",
] as const;
const states: [PrintedState, string][] = [
  ["unreviewed", "Noch offen"],
  ["legible", "Lesbar gedruckt"],
  ["not_printed", "Nicht gedruckt"],
  ["illegible", "Unleserlich"],
  ["cropped", "Abgeschnitten"],
  ["contradictory", "Widersprüchlich"],
];
type Entry = {
  filename: string;
  sha256: string;
  verified?: boolean;
  reviewed_rows?: number;
  reference_rows?: number;
};

export function ReferenceReview({ w }: { w: Workbench }) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [reference, setReference] = useState<Annotation | null>(null);
  const [image, setImage] = useState("");
  const [selected, setSelected] = useState(0);
  const [field, setField] = useState<string>("title");
  const [saved, setSaved] = useState(false);
  const [splitFrozen, setSplitFrozen] = useState(false);
  const [lineId, setLineId] = useState<string | null>(null);
  const [geometryTarget, setGeometryTarget] = useState<
    "field" | "row" | "table" | "line"
  >("field");
  const [drawing, setDrawing] = useState(false);
  const [points, setPoints] = useState<{ x: number; y: number }[]>([]);
  const a = reference?.appointments[selected];
  const source = reference?.sources?.[0];
  const focus =
    geometryTarget === "table"
      ? (source?.table_polygon ?? [])
      : geometryTarget === "row"
        ? (a?.row_polygon ?? [])
        : geometryTarget === "line"
          ? (reference?.lines?.find((l) => l.id === lineId)?.polygon ?? [])
          : (a?.fields?.[field]?.polygon ?? a?.row_polygon ?? []);
  const allPoints = focus.length ? focus : (source?.table_polygon ?? []);
  const x = Math.max(0, Math.min(...allPoints.map((p) => p.x)) - 60);
  const y = Math.max(0, Math.min(...allPoints.map((p) => p.y)) - 100);
  const right = Math.min(
    source?.width ?? 0,
    Math.max(...allPoints.map((p) => p.x)) + 60,
  );
  const bottom = Math.min(
    source?.height ?? 0,
    Math.max(...allPoints.map((p) => p.y)) + 100,
  );
  function change(next: Annotation) {
    setReference({
      ...next,
      verified: false,
      reviewed_at: null,
      content_hash: null,
      approval_hash: null,
    });
    setSaved(false);
  }
  function editAppointment(patch: Partial<Appointment>) {
    if (!reference || !a) return;
    change({
      ...reference,
      appointments: reference.appointments.map((v, i) =>
        i === selected ? { ...v, ...patch } : v,
      ),
    });
  }
  function editSource(patch: Partial<ReferenceSource>) {
    if (!reference || !source) return;
    change({
      ...reference,
      sources: [
        {
          ...source,
          ...patch,
          relationships_confirmed: patch.relationships_confirmed ?? false,
        },
      ],
    });
  }
  async function refreshInventory() {
    const inventory = await command<{
      entries: Entry[];
      split_frozen: boolean;
    }>("dataset", { path: null });
    setEntries(inventory.entries);
    setSplitFrozen(inventory.split_frozen);
  }
  async function save(approve: boolean) {
    if (!reference) return;
    await w.execute(
      approve
        ? "Referenz wird freigegeben"
        : "Prüffortschritt wird gespeichert",
      async () => {
        await command("save_annotation", {
          annotation: {
            ...reference,
            verified: approve,
            reviewed_at: approve ? new Date().toISOString() : null,
          },
        });
        setReference(
          await command<Annotation>("provisional_reference", {
            hash: reference.document_hashes[0],
          }),
        );
        setSaved(true);
        await refreshInventory();
      },
    );
  }
  const reviewed =
    reference?.appointments.filter((row) =>
      fields.every((f) => row.fields?.[f]?.confirmed_at != null),
    ).length ?? 0;
  return (
    <section
      aria-label="Referenzen mit Originalfotos prüfen"
      className="flex flex-col gap-4"
    >
      <h2 className="text-lg font-medium">Foto gegen Referenz prüfen</h2>
      <p>
        Jedes Original einzeln prüfen, einschließlich Mahlzeiten und leerer
        Zellen. Erst die ausdrückliche Freigabe erlaubt Training und Bewertung.
      </p>
      <Button
        disabled={!w.native || !!w.busy}
        variant="outline"
        onClick={() => w.execute("Originale laden", refreshInventory)}
      >
        20 Originale / Inventar öffnen
      </Button>
      {entries.length > 0 && (
        <Button
          disabled={!!w.busy || (!!reference && !saved)}
          variant="outline"
          onClick={() =>
            w.execute(
              "Bestätigte Seiten in vier Entwicklungsfalten einfrieren",
              async () => {
                await command("freeze_reference_groups");
                if (reference)
                  setReference(
                    await command<Annotation>("provisional_reference", {
                      hash: reference.document_hashes[0],
                    }),
                  );
                setSaved(true);
                await refreshInventory();
              },
            )
          }
        >
          Bestätigte Seitengruppen einfrieren (vier Entwicklungsfalten)
        </Button>
      )}
      {entries.length > 0 && (
        <label>
          Originalfoto
          <select
            className="mt-1 w-full rounded border p-2"
            value={reference?.document_hashes[0] ?? ""}
            disabled={!!w.busy || (!!reference && !saved)}
            onChange={(e) =>
              w.execute("Referenz und Foto laden", async () => {
                const [ref, photo] = await Promise.all([
                  command<Annotation>("provisional_reference", {
                    hash: e.target.value,
                  }),
                  command<{ base64: string }>("dataset_image", {
                    hash: e.target.value,
                  }),
                ]);
                setReference(ref);
                setImage(`data:image/png;base64,${photo.base64}`);
                setSelected(0);
                setLineId(null);
                setDrawing(false);
                setPoints([]);
                setGeometryTarget("field");
                setSaved(true);
              })
            }
          >
            <option value="" disabled>
              Foto auswählen
            </option>
            {entries.map((e) => (
              <option key={e.sha256} value={e.sha256}>
                {e.filename} ·{" "}
                {e.verified
                  ? "freigegeben"
                  : `${e.reviewed_rows ?? 0}/${e.reference_rows ?? "?"} Zeilen geprüft`}
              </option>
            ))}
          </select>
        </label>
      )}
      {reference && source && (
        <>
          <label>
            Art der Eingabe
            <select
              value={reference.input_class ?? "rehabilitation_plan"}
              onChange={(e) =>
                change({
                  ...reference,
                  input_class: e.target.value as Annotation["input_class"],
                })
              }
            >
              <option value="rehabilitation_plan">Rehabilitationsplan</option>
              <option value="non_plan">Kein Plan</option>
              <option value="unusable">Nicht brauchbar</option>
            </select>
          </label>
          <p role="status">
            {reviewed} / {reference.appointments.length} Zeilen bestätigt ·{" "}
            {saved ? "Gespeichert" : "Änderungen noch speichern"} ·{" "}
            {reference.verified
              ? "Freigegeben"
              : "Nicht für Training freigegeben"}
          </p>
          <details>
            <summary>Seite und Aufnahmeserie zuordnen</summary>
            <div className="grid gap-3 py-3 sm:grid-cols-2">
              <label>
                Logische Seite
                <Input
                  value={source.logical_page}
                  onChange={(e) => editSource({ logical_page: e.target.value })}
                />
              </label>
              <label>
                Aufnahmeserie
                <Input
                  value={source.capture_series}
                  onChange={(e) =>
                    editSource({ capture_series: e.target.value })
                  }
                />
              </label>
              <label>
                Behandlungstage (mit Komma)
                <Input
                  value={source.treatment_days.join(", ")}
                  onChange={(e) =>
                    editSource({
                      treatment_days: e.target.value
                        .split(",")
                        .map((v) => v.trim())
                        .filter(Boolean),
                    })
                  }
                />
              </label>
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={source.relationships_confirmed}
                  onChange={(e) =>
                    editSource({ relationships_confirmed: e.target.checked })
                  }
                />
                Seite, Serie und überlappende Tage geprüft
              </label>
            </div>
          </details>
          <div className="grid min-w-0 gap-4 lg:grid-cols-2">
            <div className="min-w-0 lg:sticky lg:top-4 lg:self-start">
              <svg
                viewBox={`0 0 ${source.width} ${source.height}`}
                className="max-h-[65vh] w-full rounded border"
                role="img"
                aria-label="Originalfoto mit markierter Terminzeile"
                onClick={(e) => {
                  if (!drawing) return;
                  const svg = e.currentTarget;
                  const point = svg.createSVGPoint();
                  point.x = e.clientX;
                  point.y = e.clientY;
                  const matrix = svg.getScreenCTM();
                  if (!matrix) return;
                  const p = point.matrixTransform(matrix.inverse());
                  const next = [...points, { x: p.x, y: p.y }];
                  setPoints(next);
                  if (next.length === 4) {
                    const assessment = a?.fields?.[field];
                    if (geometryTarget === "table")
                      editSource({ table_polygon: next });
                    else if (geometryTarget === "row" && a)
                      editAppointment({
                        row_polygon: next,
                        fields: Object.fromEntries(
                          Object.entries(a.fields ?? {}).map(([f, v]) => [
                            f,
                            { ...v, confirmed_at: null, confirmed_value: null },
                          ]),
                        ),
                      });
                    else if (geometryTarget === "line" && a && assessment)
                      change({
                        ...reference,
                        lines: reference.lines?.map((l) =>
                          l.id === lineId ? { ...l, polygon: next } : l,
                        ),
                        appointments: reference.appointments.map((row) =>
                          row.id === a.id
                            ? {
                                ...row,
                                fields: {
                                  ...row.fields,
                                  [field]: {
                                    ...assessment,
                                    confirmed_at: null,
                                    confirmed_value: null,
                                  },
                                },
                              }
                            : row,
                        ),
                      });
                    else if (assessment && a)
                      editAppointment({
                        fields: {
                          ...a.fields,
                          [field]: {
                            ...assessment,
                            polygon: next,
                            confirmed_at: null,
                            confirmed_value: null,
                          },
                        },
                      });
                    setDrawing(false);
                    setPoints([]);
                  }
                }}
              >
                <image
                  href={image}
                  width={source.width}
                  height={source.height}
                />
                {a?.row_polygon && (
                  <polygon
                    points={a.row_polygon.map((p) => `${p.x},${p.y}`).join(" ")}
                    fill="rgba(20,140,160,0.12)"
                    stroke="#008299"
                    strokeWidth={5}
                  />
                )}
                {focus.length > 0 && (
                  <polygon
                    points={focus.map((p) => `${p.x},${p.y}`).join(" ")}
                    fill="none"
                    stroke="#b45309"
                    strokeWidth={5}
                  />
                )}
                {points.map((p, i) => (
                  <circle key={i} cx={p.x} cy={p.y} r={15} fill="#b45309" />
                ))}
              </svg>
              {a && allPoints.length > 0 && (
                <svg
                  viewBox={`${x} ${y} ${right - x} ${bottom - y}`}
                  className="mt-3 max-h-64 w-full border"
                  role="img"
                  aria-label="Vergrößerter Feldausschnitt und Nachbarzeilen"
                >
                  <image
                    href={image}
                    width={source.width}
                    height={source.height}
                  />
                </svg>
              )}
              <label>
                Geometrie
                <select
                  className="m-2 rounded border p-2"
                  value={geometryTarget}
                  onChange={(e) => {
                    setGeometryTarget(e.target.value as typeof geometryTarget);
                    setDrawing(false);
                    setPoints([]);
                  }}
                >
                  <option value="field">Feldzelle</option>
                  <option value="row">Terminblock</option>
                  <option value="table">
                    Termintabelle (Patientenkopf ausschließen)
                  </option>
                  <option value="line" disabled={!lineId}>
                    Ausgewählte Textzeile
                  </option>
                </select>
              </label>
              <Button
                variant="outline"
                onClick={() => {
                  setDrawing(!drawing);
                  setPoints([]);
                }}
              >
                {drawing
                  ? "Markierung abbrechen"
                  : "Vier Ecken im Foto korrigieren"}
              </Button>
              {drawing && (
                <p>
                  Oben links, oben rechts, unten rechts, unten links anklicken.
                </p>
              )}
            </div>
            <div className="flex min-w-0 flex-col gap-3">
              <label>
                Terminzeile
                <select
                  className="mt-1 w-full rounded border p-2"
                  value={selected}
                  onChange={(e) => setSelected(Number(e.target.value))}
                >
                  {reference.appointments.map((row, i) => (
                    <option key={row.id} value={i}>
                      {i + 1}. {row.date} {row.start} {row.title}
                    </option>
                  ))}
                </select>
              </label>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  onClick={() => {
                    const row = emptyAppointment(null);
                    row.fields = Object.fromEntries(
                      fields.map((f) => [
                        f,
                        {
                          state: "unreviewed" as const,
                          polygon: [],
                          frame: "original",
                          reasons: [],
                          confirmed_at: null,
                          confirmed_value: null,
                        },
                      ]),
                    );
                    change({
                      ...reference,
                      coverage_confirmed: false,
                      appointments: [...reference.appointments, row],
                    });
                    setSelected(reference.appointments.length);
                  }}
                >
                  Fehlenden Termin ergänzen
                </Button>
                <Button
                  variant="outline"
                  disabled={!a}
                  onClick={() => {
                    if (!a) return;
                    change({
                      ...reference,
                      coverage_confirmed: false,
                      appointments: reference.appointments.filter(
                        (v) => v.id !== a.id,
                      ),
                      lines: reference.lines?.filter(
                        (l) => l.appointment_id !== a.id,
                      ),
                    });
                    setSelected(0);
                  }}
                >
                  Diesen Referenztermin entfernen
                </Button>
              </div>
              {a &&
                fields.map((f) => {
                  const assessment: FieldAssessment = a.fields?.[f] ?? {
                    state: "unreviewed",
                    polygon: [],
                    frame: "original",
                    reasons: [],
                    confirmed_at: null,
                    confirmed_value: null,
                  };
                  return (
                    <div
                      key={f}
                      className="rounded border p-3"
                      onFocus={() => setField(f)}
                    >
                      <label>
                        {fieldLabels[f]}
                        <Input
                          value={a[f] ?? ""}
                          onChange={(e) => {
                            const value = ["date", "start", "end"].includes(f)
                              ? e.target.value || null
                              : e.target.value;
                            editAppointment({
                              [f]: value,
                              fields: {
                                ...a.fields,
                                [f]: {
                                  ...assessment,
                                  confirmed_at: null,
                                  confirmed_value: null,
                                },
                              },
                            });
                          }}
                        />
                      </label>
                      <select
                        aria-label={`${fieldLabels[f]} Druckzustand`}
                        className="mt-2 w-full rounded border p-2"
                        value={assessment.state}
                        onChange={(e) => {
                          const state = e.target.value as PrintedState;
                          editAppointment({
                            ...(state === "not_printed"
                              ? {
                                  [f]: ["date", "start", "end"].includes(f)
                                    ? null
                                    : "",
                                }
                              : {}),
                            fields: {
                              ...a.fields,
                              [f]: {
                                ...assessment,
                                state,
                                confirmed_at: null,
                                confirmed_value: null,
                              },
                            },
                          });
                        }}
                      >
                        {states.map(([state, label]) => (
                          <option key={state} value={state}>
                            {label}
                          </option>
                        ))}
                      </select>
                      <Button
                        variant="ghost"
                        onClick={() => {
                          setField(f);
                          setGeometryTarget("field");
                        }}
                      >
                        Ausschnitt zeigen
                      </Button>
                      <details>
                        <summary>Textpolygone und Fehlerursachen</summary>
                        {reference.lines
                          ?.filter(
                            (l) => l.appointment_id === a.id && l.field === f,
                          )
                          .map((line) => (
                            <div key={line.id} className="my-2">
                              <Button
                                variant="ghost"
                                onClick={() => {
                                  setLineId(line.id);
                                  setField(f);
                                  setGeometryTarget("line");
                                }}
                              >
                                Textpolygon zeigen / korrigieren
                              </Button>
                              <select
                                aria-label="Druckzustand der Textzeile"
                                value={line.state}
                                onChange={(e) =>
                                  change({
                                    ...reference,
                                    lines: reference.lines?.map((l) =>
                                      l.id === line.id
                                        ? {
                                            ...l,
                                            state: e.target
                                              .value as PrintedState,
                                          }
                                        : l,
                                    ),
                                    appointments: reference.appointments.map(
                                      (row) =>
                                        row.id === a.id
                                          ? {
                                              ...row,
                                              fields: {
                                                ...row.fields,
                                                [f]: {
                                                  ...assessment,
                                                  confirmed_at: null,
                                                  confirmed_value: null,
                                                },
                                              },
                                            }
                                          : row,
                                    ),
                                  })
                                }
                              >
                                {states.map(([state, label]) => (
                                  <option key={state} value={state}>
                                    {label}
                                  </option>
                                ))}
                              </select>
                              <label>
                                Gedruckte Textzeile
                                <Input
                                  value={line.text}
                                  onChange={(e) =>
                                    change({
                                      ...reference,
                                      lines: reference.lines!.map((l) =>
                                        l.id === line.id
                                          ? { ...l, text: e.target.value }
                                          : l,
                                      ),
                                      appointments: reference.appointments.map(
                                        (row) =>
                                          row.id === a.id
                                            ? {
                                                ...row,
                                                fields: {
                                                  ...row.fields,
                                                  [f]: {
                                                    ...assessment,
                                                    confirmed_at: null,
                                                    confirmed_value: null,
                                                  },
                                                },
                                              }
                                            : row,
                                      ),
                                    })
                                  }
                                />
                              </label>
                              <label>
                                Ursachen (mit Komma)
                                <Input
                                  value={line.error_causes.join(", ")}
                                  onChange={(e) =>
                                    change({
                                      ...reference,
                                      lines: reference.lines!.map((l) =>
                                        l.id === line.id
                                          ? {
                                              ...l,
                                              error_causes: e.target.value
                                                .split(",")
                                                .map((v) => v.trim())
                                                .filter(Boolean),
                                            }
                                          : l,
                                      ),
                                    })
                                  }
                                />
                              </label>
                              <Button
                                variant="ghost"
                                onClick={() =>
                                  change({
                                    ...reference,
                                    lines: reference.lines?.filter(
                                      (l) => l.id !== line.id,
                                    ),
                                    appointments: reference.appointments.map(
                                      (row) =>
                                        row.id === a.id
                                          ? {
                                              ...row,
                                              fields: {
                                                ...row.fields,
                                                [f]: {
                                                  ...assessment,
                                                  confirmed_at: null,
                                                  confirmed_value: null,
                                                },
                                              },
                                            }
                                          : row,
                                    ),
                                  })
                                }
                              >
                                Textzeile entfernen
                              </Button>
                            </div>
                          ))}
                        <Button
                          variant="outline"
                          onClick={() => {
                            const id = crypto.randomUUID();
                            setLineId(id);
                            setGeometryTarget("line");
                            setField(f);
                            change({
                              ...reference,
                              lines: [
                                ...(reference.lines ?? []),
                                {
                                  id,
                                  source_hash: source.source_hash,
                                  appointment_id: a.id,
                                  field: f,
                                  text: "",
                                  polygon: assessment.polygon,
                                  state: "unreviewed",
                                  error_causes: [],
                                },
                              ],
                              appointments: reference.appointments.map((row) =>
                                row.id === a.id
                                  ? {
                                      ...row,
                                      fields: {
                                        ...row.fields,
                                        [f]: {
                                          ...assessment,
                                          confirmed_at: null,
                                          confirmed_value: null,
                                        },
                                      },
                                    }
                                  : row,
                              ),
                            });
                          }}
                        >
                          Gedruckte Textzeile ergänzen
                        </Button>
                      </details>
                    </div>
                  );
                })}
              {a && (
                <Button
                  disabled={fields.some(
                    (f) => !a.fields?.[f] || a.fields[f].state === "unreviewed",
                  )}
                  onClick={() =>
                    editAppointment({
                      fields: Object.fromEntries(
                        Object.entries(a.fields ?? {}).map(([f, v]) => [
                          f,
                          {
                            ...v,
                            confirmed_at: Math.floor(Date.now() / 1000),
                            confirmed_value:
                              a[f as (typeof fields)[number]] ?? null,
                          },
                        ]),
                      ),
                    })
                  }
                >
                  Diese Zeile am Foto bestätigt
                </Button>
              )}
            </div>
          </div>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={reference.coverage_confirmed ?? false}
              onChange={(e) =>
                change({ ...reference, coverage_confirmed: e.target.checked })
              }
            />
            Alle gedruckten Termine, Datumsabschnitte und Hinweise erfasst
          </label>
          <label>
            Offene Fragen
            <Input
              value={reference.uncertainty_notes.join(" | ")}
              onChange={(e) =>
                change({
                  ...reference,
                  uncertainty_notes: e.target.value
                    .split("|")
                    .map((v) => v.trim())
                    .filter(Boolean),
                })
              }
            />
          </label>
          <div className="flex flex-wrap gap-2">
            <Button disabled={!!w.busy} onClick={() => save(false)}>
              Prüffortschritt speichern
            </Button>
            <Button
              disabled={
                !!w.busy ||
                !splitFrozen ||
                !reference.coverage_confirmed ||
                reviewed !== reference.appointments.length ||
                !!reference.uncertainty_notes.length
              }
              onClick={() => save(true)}
            >
              Referenz ausdrücklich für Training und Bewertung freigeben
            </Button>
            {!splitFrozen && (
              <p>Vor der Freigabe die bestätigten Seitengruppen einfrieren.</p>
            )}
          </div>
        </>
      )}
    </section>
  );
}
