"use client";
import { useEffect, useState } from "react";
import type { Appointment, CompletionSuggestion, Run } from "@/lib/contracts";
import { emptyMetadata } from "@/lib/contracts";
import { fieldConfirmed, problems } from "@/lib/validation";
import type { Workbench } from "@/features/workbench/use-workbench";
import { Panel } from "./panel";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Item,
  ItemGroup,
  ItemContent,
  ItemTitle,
  ItemDescription,
  ItemActions,
} from "@/components/ui/item";
import { SourceViewer } from "@/components/source-viewer";

export const fieldLabels: Record<string, string> = {
  date: "Datum",
  start: "Beginn",
  end: "Ende",
  end_date: "Enddatum",
  duration_minutes: "Dauer (Minuten)",
  title: "Behandlung",
  location: "Raum",
  therapist: "Therapeut/in",
  notes: "Gedruckte Hinweise",
  clinic: "Klinik",
  department: "Abteilung",
  address: "Adresse",
  contact: "Kontakt",
  treatment_code: "Behandlungscode",
  preparation: "Vorbereitung laut Plan",
  document_reference: "Relevanter Dokumentverweis",
  appointment_notes: "Eigene Terminnotiz",
};
export function AppointmentSheet({
  appointment,
  run,
  w,
  close,
}: {
  appointment: Appointment;
  run: Run;
  w: Workbench;
  close: () => void;
}) {
  const [draft, setDraft] = useState(appointment);
  const [discard, setDiscard] = useState(false);
  const [source, setSource] = useState(false);
  const [sourceField, setSourceField] = useState<string | null>(null);
  const dirty = JSON.stringify(appointment) !== JSON.stringify(draft);
  useEffect(() => {
    const leave = (event: BeforeUnloadEvent) => {
      if (dirty) event.preventDefault();
    };
    window.addEventListener("beforeunload", leave);
    return () => window.removeEventListener("beforeunload", leave);
  }, [dirty]);
  const edit = (field: string, value: string | number | null) =>
    setDraft((a) => ({
      ...a,
      approval: null,
      fields: a.fields?.[field]
        ? {
            ...a.fields,
            [field]: {
              ...a.fields[field],
              confirmed_at: null,
              confirmed_value: null,
            },
          }
        : a.fields,
      ...(field in emptyMetadata
        ? { metadata: { ...emptyMetadata, ...a.metadata, [field]: value } }
        : { [field]: value }),
    }));
  function suggestion(s: CompletionSuggestion, accepted: boolean) {
    setDraft((a) => ({
      ...a,
      approval: null,
      ...(accepted
        ? s.field in emptyMetadata
          ? {
              metadata: { ...emptyMetadata, ...a.metadata, [s.field]: s.value },
            }
          : { [s.field]: s.value }
        : {}),
      suggestions: a.suggestions?.map((v) =>
        v.id === s.id
          ? { ...v, status: accepted ? "accepted" : "rejected" }
          : v,
      ),
    }));
  }
  async function save(approve: boolean) {
    await w.execute("Angaben werden gespeichert", async () => {
      await w.saveReview(
        run.appointments.some((a) => a.id === draft.id)
          ? run.appointments.map((a) => (a.id === draft.id ? draft : a))
          : [...run.appointments, draft],
        approve ? [draft.id] : [],
      );
      close();
    });
  }
  const input = (field: string, type = "text") => {
    const value =
      field in emptyMetadata
        ? (draft.metadata ?? emptyMetadata)[field as keyof typeof emptyMetadata]
        : draft[field as keyof Appointment];
    const invalid = ["date", "start", "title"].includes(field) && !value;
    return (
      <Field key={field} data-invalid={invalid}>
        <FieldLabel htmlFor={`edit-${field}`}>{fieldLabels[field]}</FieldLabel>
        <Input
          id={`edit-${field}`}
          type={type}
          min={type === "number" ? 1 : undefined}
          max={type === "number" ? 1440 : undefined}
          disabled={!!w.busy}
          aria-invalid={invalid}
          value={
            typeof value === "string" || typeof value === "number" ? value : ""
          }
          onChange={(e) =>
            edit(
              field,
              type === "number"
                ? e.target.value
                  ? Number(e.target.value)
                  : null
                : e.target.value ||
                    (type === "date" || type === "time" ? null : ""),
            )
          }
        />
        {draft.origins?.[field] && (
          <FieldDescription>{draft.origins[field].source}</FieldDescription>
        )}
        {draft.fields?.[field] && (
          <div className="flex flex-col gap-2 text-sm">
            {!fieldConfirmed(draft, field) &&
              draft.fields[field].reasons.map((reason) => (
                <p key={reason}>{reason}</p>
              ))}
            <div className="flex flex-wrap gap-2">
              <Button
                variant="outline"
                disabled={!!w.busy}
                onClick={() => {
                  setSourceField(field);
                  setSource(true);
                }}
              >
                {fieldLabels[field]} im Foto
              </Button>
              <Button
                variant="outline"
                disabled={!!w.busy || !value}
                onClick={() =>
                  setDraft((a) => ({
                    ...a,
                    approval: null,
                    fields: {
                      ...a.fields,
                      [field]: {
                        ...a.fields![field],
                        state: "legible",
                        confirmed_value: value as string | number,
                        confirmed_at: Math.floor(Date.now() / 1000),
                      },
                    },
                  }))
                }
              >
                Angabe am Foto bestätigt
              </Button>
              {["location", "therapist"].includes(field) && (
                <Button
                  variant="outline"
                  disabled={!!w.busy}
                  onClick={() =>
                    setDraft((a) => ({
                      ...a,
                      [field]: "",
                      approval: null,
                      fields: {
                        ...a.fields,
                        [field]: {
                          ...a.fields![field],
                          state: "not_printed",
                          confirmed_value: "",
                          confirmed_at: Math.floor(Date.now() / 1000),
                        },
                      },
                    }))
                  }
                >
                  Nicht gedruckt
                </Button>
              )}
            </div>
            {run.refinement_readings
              ?.filter(
                (r) => r.appointment_id === draft.id && r.field === field,
              )
              .filter(
                (r, i, all) =>
                  all.findIndex((other) => other.value === r.value) === i,
              )
              .map((r) => (
                <Button
                  key={`${r.attempt}-${field}`}
                  variant="outline"
                  disabled={!!w.busy}
                  onClick={() => edit(field, r.value)}
                >
                  Lesart: {String(r.value)}
                </Button>
              ))}
            {fieldConfirmed(draft, field) && <p>Am Foto bestätigt.</p>}
          </div>
        )}
      </Field>
    );
  };
  const specialIssues = draft.issues.filter(
    (i) =>
      i.blocking &&
      !(i.field && draft.fields?.[i.field]) &&
      ![
        "missing_date",
        "missing_start",
        "missing_end",
        "invalid_end",
        "overnight_confirmation",
        "missing_title",
      ].includes(i.code),
  );
  return (
    <Panel
      title="Termin bearbeiten"
      description="Angaben mit dem Foto vergleichen."
      onClose={() => {
        if (!w.busy) {
          if (dirty) setDiscard(true);
          else close();
        }
      }}
      actions={
        <>
          <Button
            disabled={!!w.busy}
            onClick={() => save(draft.included && problems(draft).length === 0)}
          >
            {w.busy ||
              (draft.included && !problems(draft).length
                ? "Termin bestätigen"
                : "Angaben speichern")}
          </Button>
          {!discard && (
            <Button
              variant="outline"
              disabled={!!w.busy}
              onClick={() => (dirty ? setDiscard(true) : close())}
            >
              Zurück
            </Button>
          )}
        </>
      }
    >
      <div className="flex flex-col gap-5">
        {w.error && (
          <Alert variant="destructive">
            <AlertDescription>{w.error}</AlertDescription>
          </Alert>
        )}
        {discard && (
          <Alert>
            <AlertDescription>
              Ungespeicherte Änderungen verwerfen?
              <div className="flex flex-wrap gap-2">
                <Button variant="destructive" onClick={close}>
                  Verwerfen
                </Button>
                <Button variant="outline" onClick={() => setDiscard(false)}>
                  Weiter bearbeiten
                </Button>
              </div>
            </AlertDescription>
          </Alert>
        )}
        <FieldGroup>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {input("date", "date")}
            {input("start", "time")}
            {input("end", "time")}
            {input("duration_minutes", "number")}
          </div>
          {input("title")}
          {input("location")}
          {input("therapist")}
        </FieldGroup>
        {!!draft.suggestions?.some((s) => s.status === "pending") && (
          <section aria-label="Ergänzungsvorschläge">
            <h2 className="mb-2 text-sm font-medium">Vorschläge prüfen</h2>
            <ItemGroup>
              {draft.suggestions
                .filter((s) => s.status === "pending")
                .map((s) => (
                  <Item key={s.id} variant="outline">
                    <ItemContent>
                      <ItemTitle>
                        {fieldLabels[s.field]}: {String(s.value)}
                      </ItemTitle>
                      <ItemDescription>{s.source}</ItemDescription>
                    </ItemContent>
                    <ItemActions className="flex-wrap">
                      <Button
                        variant="outline"
                        disabled={!!w.busy}
                        onClick={() => suggestion(s, true)}
                      >
                        Übernehmen
                      </Button>
                      <Button
                        variant="ghost"
                        disabled={!!w.busy}
                        onClick={() => suggestion(s, false)}
                      >
                        Ablehnen
                      </Button>
                    </ItemActions>
                  </Item>
                ))}
            </ItemGroup>
          </section>
        )}
        {specialIssues.map((issue, index) => (
          <Alert key={`${issue.code}-${index}`}>
            <AlertDescription>
              {issue.message}
              {run.refinement_readings
                ?.filter(
                  (r) =>
                    r.appointment_id === draft.id && r.field === issue.field,
                )
                .map((r) => (
                  <p key={`${r.attempt}-${r.field}`}>
                    {fieldLabels[r.field]}: {String(r.value)}
                  </p>
                ))}
              <Button
                variant="outline"
                disabled={!!w.busy}
                onClick={() =>
                  setDraft({
                    ...draft,
                    issues: draft.issues.filter((v) => v !== issue),
                  })
                }
              >
                Mit Foto geprüft
              </Button>
            </AlertDescription>
          </Alert>
        ))}
        <details>
          <summary>Weitere Angaben</summary>
          <FieldGroup className="mt-4">
            {input("end_date", "date")}
            {Object.keys(emptyMetadata).map((field) => input(field))}
            <Field>
              <FieldLabel htmlFor="edit-notes">Gedruckte Hinweise</FieldLabel>
              <Textarea
                id="edit-notes"
                disabled={!!w.busy}
                value={draft.notes}
                onChange={(e) => edit("notes", e.target.value)}
              />
            </Field>
            <FieldDescription>
              Patientennummern und Verwaltungsangaben bleiben beim Dokument. Nur
              terminrelevante Angaben werden in Kalendernotizen übernommen.
            </FieldDescription>
            <Button
              variant="outline"
              disabled={!!w.busy}
              onClick={() =>
                setDraft({
                  ...draft,
                  included: !draft.included,
                  approval: null,
                })
              }
            >
              {draft.included
                ? "Termin ausschließen"
                : "Termin wieder aufnehmen"}
            </Button>
          </FieldGroup>
        </details>
        <Button variant="outline" onClick={() => setSource(!source)}>
          {source ? "Foto ausblenden" : "Foto ansehen"}
        </Button>
        {source && (
          <SourceViewer
            key={sourceField}
            simple
            run={run}
            native={w.native}
            highlight={
              sourceField
                ? (draft.provenance[sourceField] ?? [])
                : Object.values(draft.provenance).flat()
            }
            focusPolygon={
              sourceField
                ? draft.fields?.[sourceField]?.polygon
                : draft.row_polygon
            }
            focusFrame={
              sourceField ? draft.fields?.[sourceField]?.frame : "page"
            }
          />
        )}
        <details>
          <summary>Quelltext und Herkunft</summary>
          <div className="mt-3 flex flex-col gap-2">
            {run.observations
              .filter((o) =>
                Object.values(draft.provenance).flat().includes(o.id),
              )
              .map((o) => (
                <p className="text-sm" key={o.id}>
                  {o.text}
                </p>
              ))}
            {draft.suggestions
              ?.filter((s) => s.status !== "pending")
              .map((s) => (
                <p className="text-sm text-muted-foreground" key={s.id}>
                  {fieldLabels[s.field]}: {String(s.value)} ·{" "}
                  {s.status === "accepted" ? "Übernommen" : "Abgelehnt"} ·{" "}
                  {s.source}
                </p>
              ))}
          </div>
        </details>
      </div>
    </Panel>
  );
}
