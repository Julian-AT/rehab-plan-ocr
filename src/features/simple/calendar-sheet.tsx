"use client";
import { useState } from "react";
import type {
  Calendar,
  CalendarConnection,
  Proposal,
  Run,
  WriteResult,
} from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { command, exportFile } from "@/lib/native";
import { problems } from "@/lib/validation";
import { Panel } from "./panel";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
export function CalendarSheet({
  run,
  w,
  close,
}: {
  run: Run;
  w: Workbench;
  close: () => void;
}) {
  const ready = run.appointments.filter(
    (a) => a.included && !problems(a).length,
  );
  const [selected, setSelected] = useState(ready.map((a) => a.id));
  const [calendars, setCalendars] = useState<Calendar[]>([]);
  const [calendarId, setCalendarId] = useState("");
  const [proposal, setProposal] = useState<Proposal | null>(null);
  const [result, setResult] = useState("");
  const pending = run.appointments.filter(
    (a) => a.included && problems(a).length,
  ).length;
  const args = {
    id: run.document.id,
    selection: selected,
    timezone: w.preferences.timezone,
    reminder: w.preferences.reminder,
  };
  async function connect() {
    await w.execute("Kalender wird verbunden", async () => {
      const value = await command<CalendarConnection>("calendars", {
        dedicated: true,
      });
      setCalendars(value.calendars);
      const bound = w.history.scans.find(
        (s) => s.id === run.document.id,
      )?.schedule_id;
      const previous = w.history.imports.find(
        (i) => i.schedule_id === bound,
      )?.calendar_id;
      setCalendarId(
        previous ?? (w.preferences.calendar_id || value.dedicated_id || ""),
      );
      if (value.setup_error) w.report(value.setup_error);
    });
  }
  async function prepare() {
    await w.execute("Ausgewählte Termine werden geprüft", async () => {
      await w.saveReview(run.appointments, selected);
      setProposal(
        await command<Proposal>("prepare_calendar", {
          ...args,
          calendarId,
          previous: null,
          replacement: false,
        }),
      );
    });
  }
  async function apply() {
    if (!proposal) return;
    await w.execute("Termine werden gespeichert", async () => {
      const results = await command<WriteResult[]>("approve_calendar", {
        token: proposal.token,
        approveRemovals: false,
      });
      const failed = results.filter((r) => r.status !== "saved");
      setResult(
        failed.length
          ? `${failed.length} Schreibvorgänge offen. ${failed
              .map((r) => r.error)
              .filter(Boolean)
              .join(" ")}`
          : "Termine im Kalender gespeichert.",
      );
      setProposal(null);
      w.acceptRun(await command<Run>("load_scan", { id: run.document.id }));
      await w.refresh();
    });
  }
  async function ics() {
    await w.execute("Kalenderdatei wird erstellt", async () => {
      await w.saveReview(run.appointments, selected);
      const content = await command<string>("export_ics", args);
      await exportFile(content, "termine.ics", "text/calendar;charset=utf-8");
      w.acceptRun(await command<Run>("load_scan", { id: run.document.id }));
      setResult(
        "ICS exportiert. Die Datei kann in einen Kalender importiert werden.",
      );
    });
  }
  return (
    <Panel
      title="In Kalender übernehmen"
      description={`${selected.length} ausgewählt · ${pending} mit offenen Angaben`}
      onClose={() => {
        if (!w.busy) close();
      }}
      actions={
        <>
          {proposal ? (
            <Button
              disabled={
                !!w.busy ||
                proposal.operations.some(
                  (o) => o.requires_resolution || o.kind === "remove",
                )
              }
              onClick={apply}
            >
              {w.busy || "Im Kalender speichern"}
            </Button>
          ) : (
            <Button
              disabled={
                !w.native || !!w.busy || !selected.length || !calendarId
              }
              onClick={prepare}
            >
              {w.busy || "Auswahl geprüft – weiter"}
            </Button>
          )}
          <Button
            variant="outline"
            disabled={!w.native || !!w.busy || !selected.length}
            onClick={ics}
          >
            Auswahl als ICS exportieren
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-5">
        {w.error && (
          <Alert variant="destructive">
            <AlertDescription>{w.error}</AlertDescription>
          </Alert>
        )}
        {result && (
          <Alert>
            <AlertDescription role="status">{result}</AlertDescription>
          </Alert>
        )}
        <FieldGroup>
          {ready.map((a) => (
            <Field key={a.id} orientation="horizontal">
              <Checkbox
                id={`save-${a.id}`}
                checked={selected.includes(a.id)}
                disabled={!!w.busy}
                onCheckedChange={(checked) => {
                  setSelected((s) =>
                    checked === true
                      ? [...s, a.id]
                      : s.filter((id) => id !== a.id),
                  );
                  setProposal(null);
                }}
              />
              <FieldLabel htmlFor={`save-${a.id}`}>
                {a.date} · {a.start} · {a.title}
              </FieldLabel>
            </Field>
          ))}
        </FieldGroup>
        {!!pending && (
          <p className="text-sm text-muted-foreground">
            Offene Termine bleiben für eine spätere Ergänzung erhalten.
          </p>
        )}
        {w.runtime?.platform === "ios" && (
          <Button variant="outline" disabled={!!w.busy} onClick={connect}>
            Kalender verbinden
          </Button>
        )}
        <Field>
          <FieldLabel htmlFor="destination">Zielkalender</FieldLabel>
          <Select
            value={calendarId}
            disabled={!calendars.length || !!w.busy}
            onValueChange={(value) => {
              setCalendarId(value);
              setProposal(null);
            }}
          >
            <SelectTrigger id="destination">
              <SelectValue placeholder="Kalender verbinden" />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                {calendars.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.title}
                    {c.source ? ` · ${c.source}` : ""}
                  </SelectItem>
                ))}
              </SelectGroup>
            </SelectContent>
          </Select>
        </Field>
        {proposal?.operations
          .filter((o) => o.requires_resolution)
          .map((op) => (
            <Alert key={op.id}>
              <AlertDescription>
                {op.after?.title ?? op.before?.title}: {op.reason}
                <div className="flex flex-wrap gap-2">
                  {[
                    "keep",
                    ...(op.kind === "conflict" && op.before ? ["paper"] : []),
                    ...(op.kind === "ambiguous" ? ["new"] : []),
                  ].map((choice) => (
                    <Button
                      key={choice}
                      variant="outline"
                      disabled={!!w.busy}
                      onClick={() =>
                        w.execute(
                          "Kalenderänderung wird abgeglichen",
                          async () =>
                            setProposal(
                              await command<Proposal>("resolve_proposal", {
                                token: proposal.token,
                                eventId: op.id,
                                choice,
                              }),
                            ),
                        )
                      }
                    >
                      {choice === "keep"
                        ? "Kalender behalten"
                        : choice === "paper"
                          ? "Geprüfte Angaben verwenden"
                          : "Als zusätzlichen Termin anlegen"}
                    </Button>
                  ))}
                </div>
              </AlertDescription>
            </Alert>
          ))}
        {proposal && (
          <p className="text-sm">
            {proposal.operations.filter((o) => o.kind === "create").length} neue
            Termine ·{" "}
            {proposal.operations.filter((o) => o.kind === "update").length}{" "}
            Änderungen
          </p>
        )}
        {w.history.pending > 0 && (
          <Button
            variant="outline"
            disabled={!!w.busy}
            onClick={() =>
              w.execute("Schreibstatus wird abgeglichen", async () => {
                const results =
                  await command<WriteResult[]>("reconcile_calendar");
                await w.refresh();
                setResult(
                  results.every((r) => r.status === "saved")
                    ? "Schreibstatus abgeglichen."
                    : "Einige Vorgänge brauchen eine Prüfung im Kalender. Details stehen in der Entwickleransicht.",
                );
              })
            }
          >
            Unklare Schreibvorgänge abgleichen
          </Button>
        )}
      </div>
    </Panel>
  );
}
