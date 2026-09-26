"use client";
import { useRef, useState } from "react";
import {
  ArrowLeft,
  Camera,
  ChevronRight,
  ImagePlus,
  Plus,
  RotateCcw,
  Bell,
  CalendarDays,
  Layers,
  Settings,
} from "lucide-react";
import type { Appointment, Run, Point } from "@/lib/contracts";
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

import { useAgenda } from "./use-agenda";
import { Today } from "./today";
import { eventTime } from "@/lib/agenda";
import { ImportHistory } from "./import-history";
import { SavedReview } from "./saved-review";
import { command } from "@/lib/native";

type ActivePanel =
  | { kind: "appointment"; appointment: Appointment }
  | {
      kind: "settings" | "calendar" | "source" | "saved" | "import" | "history";
    }
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
  const agenda = useAgenda(w);
  const [tab, setTab] = useState<"today" | "plans" | "more">("today");
  const [review, setReview] = useState(!!w.run);
  const [panel, setPanel] = useState<ActivePanel>(null);
  const [openOnly, setOpenOnly] = useState(false);
  const [deleteIntake, setDeleteIntake] = useState<string | null>(null);
  const files = useRef<HTMLInputElement>(null);
  const run = review ? w.run : null;
  const close = () => setPanel(null);
  const importPhoto = (source: "camera" | "photos") => {
    close();
    if (w.runtime?.platform === "ios") {
      setReview(true);
      void w.capture(source);
    } else if (source === "photos") files.current?.click();
    else w.report("Die Kamera ist in der installierten iPhone-App verfügbar.");
  };
  const openedEvent = agenda.data.snapshot.events.find(
    (event) => event.id === agenda.opening,
  );
  const closeEvent = () => {
    agenda.setOpening(null);
    setReview(false);
    setTab("today");
  };
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
    <main className="simple-interface agenda-app">
      <header className="agenda-header">
        <div>
          {run ? (
            <Button
              id="review-focus"
              variant="ghost"
              onClick={() => {
                setReview(false);
                setTab("plans");
              }}
            >
              <ArrowLeft size={18} /> Übersicht
            </Button>
          ) : (
            <>
              <p className="header-date">
                {agenda.now?.toLocaleDateString("de-AT", {
                  weekday: "long",
                  day: "numeric",
                  month: "long",
                }) ?? "Dein persönlicher Kalender"}
              </p>
              <h1>
                {tab === "today"
                  ? "Termine"
                  : tab === "plans"
                    ? "Archiv"
                    : "Mehr"}
                <span className="title-period">.</span>
              </h1>
            </>
          )}
        </div>
        <Button
          id={!run ? "review-focus" : undefined}
          className="reminder-bell"
          variant="ghost"
          size="icon"
          aria-label="Erinnerungen"
          onClick={() => setPanel({ kind: "settings" })}
        >
          <Bell size={21} strokeWidth={1.6} />
        </Button>
      </header>
      <input
        ref={files}
        hidden
        aria-hidden="true"
        tabIndex={-1}
        type="file"
        aria-label="Plan importieren"
        accept=".jpg,.jpeg,.png,.heic,.heif,image/jpeg,image/png,image/heic,image/heif"
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
            <p role="status">{w.progress?.stage ?? w.busy}</p>
            {w.progress && (
              <p>
                {Math.floor(w.progress.elapsed_ms / 1000)} von höchstens 60
                Sekunden ·{" "}
                {w.progress.draft_available
                  ? "Letzter Entwurf gesichert"
                  : "Laden und Bildaufbereitung eingeschlossen"}
              </p>
            )}
            <Button variant="outline" onClick={w.cancel}>
              Abbrechen
            </Button>
          </AlertDescription>
        </Alert>
      )}
      {!run ? (
        tab === "more" ? (
          <div className="plans-content">
            <Button onClick={() => setPanel({ kind: "settings" })}>
              Einstellungen
            </Button>
            <h2>Über Laßnitzhöhe</h2>
            <p>
              Deine Rehabilitationspläne. Erkennung auf diesem Gerät. Fotos
              bleiben erhalten, bis du sie löschst.
            </p>
          </div>
        ) : tab === "today" ? (
          <Today
            agenda={agenda}
            importPlan={() => setPanel({ kind: "import" })}
            open={agenda.setOpening}
          />
        ) : (
          <div className="plans-content">
            <Button
              variant="outline"
              onClick={() => setPanel({ kind: "history" })}
            >
              Importverlauf und Rücknahme
            </Button>
            {w.history.intakes
              ?.filter(
                (i) =>
                  i.status !== "deleted" &&
                  !w.history.scans.some((s) => s.id === i.id && s.retained),
              )
              .map((intake) => (
                <article className="rounded border p-3" key={intake.id}>
                  <p>
                    Gesicherte Aufnahme ·{" "}
                    {new Date(intake.imported_at * 1000).toLocaleString(
                      "de-AT",
                    )}
                  </p>
                  <p>
                    {intake.error ??
                      "Original gespeichert · Erkennung ausstehend"}
                  </p>
                  <Button
                    disabled={!!w.busy}
                    onClick={() =>
                      void w.execute("Erkennung erneut versuchen", async () => {
                        const run = await command<Run>("retry_scan", {
                          id: intake.id,
                        });
                        w.acceptRun(run);
                        setReview(true);
                        await w.refresh();
                      })
                    }
                  >
                    Erneut versuchen
                  </Button>
                  <Button
                    variant="ghost"
                    disabled={!!w.busy}
                    onClick={() => setDeleteIntake(intake.id)}
                  >
                    Aufnahme löschen
                  </Button>
                </article>
              ))}
            <div className="section-heading">
              <h2>Importierte Pläne</h2>
              <span>
                {recent.length} {recent.length === 1 ? "Plan" : "Pläne"}
              </span>
            </div>
            {!recent.length && (
              <div className="plan-empty">
                <Layers size={36} strokeWidth={1.3} />
                <h2>Dein Plan beginnt hier.</h2>
                <p>
                  Ein Foto genügt. Prüfe die erkannten Angaben und übernimm
                  deine Termine.
                </p>
                <Button onClick={() => setPanel({ kind: "import" })}>
                  Plan importieren
                </Button>
              </div>
            )}
            {recent.map((s) => (
              <button
                className="plan-card"
                key={s.id}
                disabled={!!w.busy}
                aria-label="Plan öffnen"
                onClick={() => {
                  setReview(true);
                  if (w.run?.document.id !== s.id) void w.openScan(s.id);
                }}
              >
                <div className="plan-icon">
                  <CalendarDays size={24} strokeWidth={1.5} />
                </div>
                <div>
                  <h3>
                    {s.dates?.[0]
                      ? new Date(`${s.dates[0]}T12:00:00`).toLocaleDateString(
                          "de-AT",
                          { day: "numeric", month: "long" },
                        )
                      : new Date(s.imported_at * 1000).toLocaleDateString(
                          "de-AT",
                        )}
                    {(s.dates?.length ?? 0) > 1
                      ? ` – ${new Date(`${s.dates![s.dates!.length - 1]}T12:00:00`).toLocaleDateString("de-AT", { day: "numeric", month: "long" })}`
                      : ""}
                  </h3>
                  <p>{s.item_count} Termine</p>
                  <span className="plan-status">
                    {s.pending_count
                      ? `${s.pending_count} noch zu prüfen`
                      : s.schedule_id
                        ? "Im Kalender gespeichert"
                        : "Geprüft · zur Übernahme bereit"}
                  </span>
                </div>
                <ChevronRight size={20} />
              </button>
            ))}
            <Button
              variant="outline"
              disabled={!w.native || !!w.busy}
              onClick={() => setPanel({ kind: "saved" })}
            >
              Gespeicherte Termine prüfen
            </Button>
          </div>
        )
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
                        {a.location ||
                          (a.fields?.location?.state === "not_printed"
                            ? "Kein Raum gedruckt"
                            : "Raum offen")}{" "}
                        ·{" "}
                        {a.therapist ||
                          (a.fields?.therapist?.state === "not_printed"
                            ? "Kein Therapeut gedruckt"
                            : "Therapeut offen")}
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
          <div className="calendar-action">
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
      <div className="floating-navigation">
        <nav aria-label="Hauptnavigation">
          <button
            aria-label="Termine"
            aria-current={
              !run && tab === "today" && panel?.kind !== "settings"
                ? "page"
                : undefined
            }
            onClick={() => {
              setReview(false);
              setTab("today");
            }}
          >
            <CalendarDays size={20} />
            <span>Termine</span>
          </button>
          <button
            aria-label="Archiv"
            aria-current={
              (tab === "plans" || run) && panel?.kind !== "settings"
                ? "page"
                : undefined
            }
            onClick={() => {
              setReview(false);
              setTab("plans");
            }}
          >
            <Layers size={20} />
            <span>Archiv</span>
          </button>
          <button
            aria-label="Mehr"
            aria-current={tab === "more" ? "page" : undefined}
            onClick={() => {
              setReview(false);
              setTab("more");
            }}
          >
            <Settings size={20} />
            <span>Mehr</span>
          </button>
        </nav>
        <button
          className="floating-import"
          aria-label="Importieren"
          disabled={!!w.busy}
          onClick={() => setPanel({ kind: "import" })}
        >
          <Plus size={28} strokeWidth={1.6} />
        </button>
      </div>
      {deleteIntake && (
        <Panel
          title="Aufnahme löschen?"
          description="Original und Prüfdaten werden gelöscht. Gespeicherte Kalendertermine bleiben erhalten."
          onClose={() => setDeleteIntake(null)}
        >
          <Button
            variant="destructive"
            disabled={!!w.busy}
            onClick={() =>
              void w.execute("Aufnahme löschen", async () => {
                await w.removeScan(deleteIntake);
                setDeleteIntake(null);
              })
            }
          >
            Aufnahme endgültig löschen
          </Button>
        </Panel>
      )}
      {panel?.kind === "import" && (
        <Panel
          title="Deinen Plan importieren"
          description="Fotografiere den vollständigen Plan bei gutem Licht."
          onClose={close}
        >
          <div className="import-options">
            <Button
              size="lg"
              disabled={!!w.busy}
              onClick={() => importPhoto("camera")}
            >
              <Camera size={22} />
              Foto aufnehmen
            </Button>
            <Button
              size="lg"
              variant="outline"
              disabled={!!w.busy}
              onClick={() => importPhoto("photos")}
            >
              <ImagePlus size={22} />
              Foto importieren
            </Button>
            <p>
              Die Erkennung erfolgt auf deinem iPhone. Anschließend prüfst du
              deine Termine.
            </p>
          </div>
        </Panel>
      )}
      {agenda.opening && (
        <Panel
          title={openedEvent ? "Dein Termin" : "Termin öffnen"}
          onClose={closeEvent}
        >
          {openedEvent ? (
            <div className="event-detail">
              <p className="eyebrow">
                {new Date(openedEvent.start * 1000).toLocaleDateString(
                  "de-AT",
                  {
                    weekday: "long",
                    day: "numeric",
                    month: "long",
                    timeZone: openedEvent.timezone,
                  },
                )}
              </p>
              <div className="hero-time">{eventTime(openedEvent)}</div>
              <h2>{openedEvent.title}</h2>
              <p>{openedEvent.room || "Raum nicht angegeben"}</p>
              <p className="secondary-copy">
                Bis{" "}
                {new Date(openedEvent.end * 1000).toLocaleTimeString("de-AT", {
                  hour: "2-digit",
                  minute: "2-digit",
                  timeZone: openedEvent.timezone,
                })}{" "}
                · {openedEvent.timezone}
              </p>
              <Button
                variant="outline"
                onClick={() => {
                  agenda.setOpening(null);
                  setPanel({ kind: "saved" });
                }}
              >
                Gespeicherten Plan prüfen
              </Button>
            </div>
          ) : (
            <div className="plan-empty">
              <CalendarDays size={36} />
              <p role="status">
                {agenda.opening === "test"
                  ? "Das war eine Testmitteilung mit einem erfundenen Termin."
                  : agenda.loading
                    ? "Termin wird abgeglichen …"
                    : agenda.data.snapshot.access === "unavailable" ||
                        agenda.error
                      ? "Kalender gerade nicht zugänglich. Bitte Zugriff prüfen und erneut abgleichen."
                      : "Dieser Termin ist nicht mehr vorhanden."}
              </p>
              <Button onClick={closeEvent}>Zur Tagesübersicht</Button>
            </div>
          )}
        </Panel>
      )}
      {panel?.kind === "saved" && (
        <SavedReview
          w={w}
          close={close}
          opened={() => {
            setReview(true);
            close();
          }}
        />
      )}
      {panel?.kind === "history" && <ImportHistory w={w} close={close} />}
      {panel?.kind === "settings" && (
        <SettingsSheet
          w={w}
          close={close}
          developer={developer}
          agenda={agenda}
        />
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
  const [turns, setTurns] = useState(run.config.quarter_turns);
  const [mirrored, setMirrored] = useState(run.config.mirrored ?? false);
  const [corners, setCorners] = useState<Point[]>(
    run.config.page_corners ?? [],
  );
  const [drawing, setDrawing] = useState(false);
  return (
    <Panel
      title="Quellfoto"
      description="Das importierte Foto bleibt lokal gespeichert."
      onClose={close}
    >
      <SourceViewer
        simple
        run={run}
        native={w.native}
        corners={corners}
        onCorner={
          drawing
            ? (p) => setCorners((v) => (v.length < 4 ? [...v, p] : v))
            : undefined
        }
      />
      <div className="my-4 flex flex-wrap gap-3">
        <label>
          Drehung
          <select
            className="ml-2 rounded border p-2"
            value={turns}
            onChange={(e) => setTurns(Number(e.target.value))}
          >
            {[0, 1, 2, 3].map((t) => (
              <option value={t} key={t}>
                {t * 90}°
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={mirrored}
            onChange={(e) => setMirrored(e.target.checked)}
          />
          Spiegelung korrigieren
        </label>
        <Button
          variant="outline"
          onClick={() => {
            setCorners([]);
            setDrawing(true);
          }}
        >
          Vier Tabellenecken markieren
        </Button>
        <Button
          variant="ghost"
          onClick={() => {
            setCorners([]);
            setDrawing(false);
          }}
        >
          Ausschnitt zurücksetzen
        </Button>
        <Button
          disabled={
            !w.native ||
            !!w.busy ||
            (corners.length > 0 && corners.length !== 4)
          }
          onClick={async () => {
            await w.reprocess({
              ...run.config,
              quarter_turns: turns,
              mirrored,
              page_corners:
                corners.length === 4
                  ? (corners as [Point, Point, Point, Point])
                  : null,
            });
            close();
          }}
        >
          Ausschnitt und Drehung neu lesen
        </Button>
      </div>
      {drawing && (
        <p className="text-sm">
          {corners.length}/4 Ecken: oben links, oben rechts, unten rechts, unten
          links im Original. Datum und Spaltenüberschriften einschließen.
        </p>
      )}
      {run.issues.map((warning, i) => (
        <p className="my-2 text-sm" key={i}>
          {warning.message}
        </p>
      ))}
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
