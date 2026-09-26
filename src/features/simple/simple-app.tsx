"use client";
import { useRef, useState } from "react";
import {
  ArrowLeft,
  Camera,
  ChevronRight,
  ImagePlus,
  Plus,
  RotateCcw,
  Settings,
} from "lucide-react";
import type { Appointment, Run } from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { emptyAppointment, problems } from "@/lib/validation";
import { Button } from "@/components/ui/button";
import {
  Item,
  ItemGroup,
  ItemContent,
  ItemTitle,
  ItemDescription,
  ItemActions,
} from "@/components/ui/item";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldLabel } from "@/components/ui/field";
import { Badge } from "@/components/ui/badge";
import { Panel } from "./panel";
import { SourceViewer } from "@/components/source-viewer";
import { AppointmentSheet } from "./appointment-sheet";
import { CalendarSheet } from "./calendar-sheet";
import { SettingsSheet } from "./settings-sheet";

type ActivePanel =
  | { kind: "appointment"; appointment: Appointment }
  | { kind: "settings" | "calendar" | "source" }
  | null;
export function appointmentStatus(a: Appointment) {
  if (!a.included) return "Ausgeschlossen";
  if (!a.date) return "Datum fehlt";
  if (!a.start) return "Beginn fehlt";
  if (!a.end && !a.duration_minutes) return "Dauer fehlt";
  if (problems(a).length) return "Angaben prüfen";
  if (a.suggestions?.some((s) => s.status === "pending"))
    return "Vorschlag prüfen";
  if (
    a.calendar_saved_hash &&
    a.approval?.values_hash === a.calendar_saved_hash
  )
    return "Gespeichert";
  if (a.ics_exported_hash && a.approval?.values_hash === a.ics_exported_hash)
    return "ICS exportiert";
  if (a.approval) return "Bereit";
  return "Prüfen";
}
export function germanDate(value: string) {
  const date = new Date(`${value}T12:00:00`);
  return Number.isNaN(date.valueOf())
    ? "Datum offen"
    : date.toLocaleDateString("de-AT", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
      });
}
export function SimpleApp({
  w,
  developer,
}: {
  w: Workbench;
  developer: () => void;
}) {
  const [review, setReview] = useState(!!w.run);
  const [panel, setPanel] = useState<ActivePanel>(null);
  const [openOnly, setOpenOnly] = useState(false);
  const files = useRef<HTMLInputElement>(null);
  const run = review ? w.run : null;
  const close = () => setPanel(null);
  const ordered = [...(run?.appointments ?? [])].sort(
    (a, b) =>
      (a.date ?? "9999").localeCompare(b.date ?? "9999") ||
      (a.start ?? "99:99").localeCompare(b.start ?? "99:99"),
  );
  const groups = new Map<string, Appointment[]>();
  for (const a of ordered) {
    if (
      openOnly &&
      (!a.included ||
        (a.approval &&
          !problems(a).length &&
          !a.suggestions?.some((s) => s.status === "pending")))
    )
      continue;
    const date = a.date ?? "offen";
    groups.set(date, [...(groups.get(date) ?? []), a]);
  }
  const retained = w.history.scans.filter((s) => s.retained);
  const recent = retained.length
    ? retained
    : w.run
      ? [
          {
            id: w.run.document.id,
            imported_at: w.run.document.imported_at,
            retained: true,
            item_count: w.run.appointments.length,
            pending_count: w.run.appointments.filter(
              (a) => a.included && !a.approval,
            ).length,
            dates: [
              ...new Set(
                w.run.appointments
                  .map((a) => a.date)
                  .filter((d): d is string => !!d),
              ),
            ],
            schedule_id: null,
          },
        ]
      : [];
  return (
    <main className="simple-interface mx-auto flex min-h-dvh max-w-3xl flex-col gap-6 px-4 pt-[max(1rem,env(safe-area-inset-top))] pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:px-6">
      <header className="flex items-center justify-between gap-3">
        {run ? (
          <Button
            id="review-focus"
            variant="ghost"
            onClick={() => setReview(false)}
          >
            <ArrowLeft data-icon="inline-start" />
            Übersicht
          </Button>
        ) : (
          <span />
        )}
        <Button
          id={!run ? "review-focus" : undefined}
          variant="ghost"
          size="icon"
          aria-label="Einstellungen"
          onClick={() => setPanel({ kind: "settings" })}
        >
          <Settings />
        </Button>
      </header>
      {w.error && (
        <Alert variant="destructive">
          <AlertDescription role="alert">
            {w.error}
            <Button variant="ghost" onClick={() => w.setError("")}>
              Schließen
            </Button>
          </AlertDescription>
        </Alert>
      )}
      {w.busy && (
        <Alert>
          <AlertDescription>
            <p role="status">{w.busy}</p>
            <Button variant="outline" onClick={w.cancel}>
              Abbrechen
            </Button>
          </AlertDescription>
        </Alert>
      )}
      {!run ? (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <Button
              size="lg"
              disabled={!!w.busy}
              onClick={() => {
                if (w.runtime?.platform === "ios") {
                  setReview(true);
                  void w.capture("camera");
                } else
                  w.report(
                    "Die Kamera ist in der installierten iPhone-App verfügbar.",
                  );
              }}
            >
              <Camera data-icon="inline-start" />
              Foto aufnehmen
            </Button>
            <Button
              size="lg"
              variant="outline"
              disabled={!!w.busy}
              onClick={() => {
                if (w.runtime?.platform === "ios") {
                  setReview(true);
                  void w.capture("photos");
                } else files.current?.click();
              }}
            >
              <ImagePlus data-icon="inline-start" />
              Importieren
            </Button>
            <input
              ref={files}
              hidden
              aria-hidden="true"
              tabIndex={-1}
              type="file"
              aria-label="Plan importieren"
              accept="image/jpeg,image/png,image/heic,image/heif"
              multiple
              onChange={(e) => {
                const selected = Array.from(e.target.files ?? []);
                e.target.value = "";
                if (selected.length) {
                  setReview(true);
                  void w.importFiles(selected);
                }
              }}
            />
          </div>
          <section aria-labelledby="recent-plans">
            <h1 id="recent-plans" className="mb-3 text-base font-medium">
              Letzte Pläne
            </h1>
            {!recent.length && (
              <p className="text-sm text-muted-foreground">
                Hier erscheinen deine importierten Pläne.
              </p>
            )}
            <ItemGroup>
              {recent.map((s) => (
                <Item key={s.id} variant="outline">
                  <ItemContent>
                    <ItemTitle>
                      {s.dates?.[0]
                        ? germanDate(s.dates[0])
                        : new Date(s.imported_at * 1000).toLocaleDateString(
                            "de-AT",
                          )}
                      {(s.dates?.length ?? 0) > 1
                        ? ` · ${s.dates!.length} Tage`
                        : ""}
                    </ItemTitle>
                    <ItemDescription>
                      {s.item_count} Termine
                      {s.pending_count
                        ? ` · ${s.pending_count} noch zu prüfen`
                        : ""}
                    </ItemDescription>
                  </ItemContent>
                  <ItemActions>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Plan öffnen"
                      disabled={!!w.busy}
                      onClick={() => {
                        setReview(true);
                        if (w.run?.document.id !== s.id) void w.openScan(s.id);
                      }}
                    >
                      <ChevronRight />
                    </Button>
                  </ItemActions>
                </Item>
              ))}
            </ItemGroup>
          </section>
        </>
      ) : (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-lg font-medium">Plan prüfen</h1>
            <Button
              variant="outline"
              onClick={() => setPanel({ kind: "source" })}
            >
              Foto ansehen
            </Button>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <Field orientation="horizontal" className="w-auto">
              <Checkbox
                id="open-only"
                checked={openOnly}
                onCheckedChange={(v) => setOpenOnly(v === true)}
              />
              <FieldLabel htmlFor="open-only">Offene Angaben</FieldLabel>
            </Field>
            <Button
              variant="ghost"
              disabled={!w.native || !!w.busy}
              onClick={w.retry}
            >
              <RotateCcw data-icon="inline-start" />
              Erneut prüfen
            </Button>
          </div>
          {run.stages.some((s) =>
            ["partial", "budget_exhausted", "cancelled", "failed"].includes(
              s.status,
            ),
          ) && (
            <Alert>
              <AlertDescription>
                Die Prüfung ist noch nicht vollständig. Vorhandene Angaben
                bleiben erhalten. „Erneut prüfen“ startet eine weitere Prüfung
                von höchstens 60 Sekunden.
              </AlertDescription>
            </Alert>
          )}
          {!ordered.length && (
            <p className="text-sm text-muted-foreground">
              Noch keine Termine erkannt. Foto erneut prüfen oder einen Termin
              ergänzen.
            </p>
          )}
          {[...groups].map(([date, appointments]) => (
            <section
              key={date}
              aria-label={date === "offen" ? "Datum offen" : germanDate(date)}
            >
              <h2 className="mb-2 text-sm font-medium">
                {date === "offen" ? "Datum offen" : germanDate(date)}
              </h2>
              <ItemGroup>
                {appointments.map((a) => (
                  <Item key={a.id} variant="outline">
                    <ItemContent>
                      <ItemTitle>
                        {a.start ?? "–:–"}
                        {a.end ? `–${a.end}` : ""} ·{" "}
                        {a.title || "Behandlung fehlt"}
                      </ItemTitle>
                      <ItemDescription>
                        {a.location || "Raum offen"}
                      </ItemDescription>
                      <Badge variant="secondary" className="mt-1 self-start">
                        {appointmentStatus(a)}
                      </Badge>
                    </ItemContent>
                    <ItemActions>
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={`${a.start ?? "Zeit offen"} ${a.title || "Termin"} bearbeiten`}
                        disabled={!!w.busy}
                        onClick={() =>
                          setPanel({ kind: "appointment", appointment: a })
                        }
                      >
                        <ChevronRight />
                      </Button>
                    </ItemActions>
                  </Item>
                ))}
              </ItemGroup>
            </section>
          ))}
          <Button
            variant="outline"
            className="self-start"
            disabled={!!w.busy}
            onClick={() =>
              setPanel({
                kind: "appointment",
                appointment: emptyAppointment(null),
              })
            }
          >
            <Plus data-icon="inline-start" />
            Termin ergänzen
          </Button>
          <div className="sticky bottom-0 mt-auto bg-background py-3 pb-[max(.75rem,env(safe-area-inset-bottom))]">
            <Button
              className="w-full"
              disabled={
                !!w.busy ||
                !ordered.some((a) => a.included && !problems(a).length)
              }
              onClick={() => setPanel({ kind: "calendar" })}
            >
              In Kalender übernehmen
            </Button>
          </div>
        </>
      )}
      {panel?.kind === "settings" && (
        <SettingsSheet w={w} close={close} developer={developer} />
      )}
      {panel?.kind === "appointment" && run && (
        <AppointmentSheet
          key={panel.appointment.id}
          appointment={panel.appointment}
          run={run}
          w={w}
          close={close}
        />
      )}
      {panel?.kind === "calendar" && run && (
        <CalendarSheet run={run} w={w} close={close} />
      )}
      {panel?.kind === "source" && run && (
        <SourceSheet run={run} w={w} close={close} />
      )}
    </main>
  );
}
function SourceSheet({
  run,
  w,
  close,
}: {
  run: Run;
  w: Workbench;
  close: () => void;
}) {
  return (
    <Panel
      title="Quellfoto"
      description="Das importierte Foto bleibt lokal gespeichert."
      onClose={close}
    >
      <SourceViewer simple run={run} native={w.native} />
      <details className="mt-4">
        <summary>Dokumentdetails</summary>
        <p className="my-3 text-sm text-muted-foreground">
          Quelltext einschließlich Verwaltungsangaben. Diese Angaben werden
          nicht automatisch in den Kalender übernommen.
        </p>
        {run.observations
          .filter((o) => !o.id.startsWith("reread-"))
          .map((o) => (
            <p key={o.id} className="text-sm">
              {o.text}
            </p>
          ))}
      </details>
    </Panel>
  );
}
