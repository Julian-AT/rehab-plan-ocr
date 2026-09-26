"use client";

import { useEffect, useState } from "react";
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
import { JsonView } from "@/components/json-view";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
  FieldSet,
  FieldLegend,
} from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";

export function CalendarPanel({
  workbench: w,
  run,
}: {
  workbench: Workbench;
  run: Run;
}) {
  const [calendars, setCalendars] = useState<Calendar[]>([]);
  const [calendarId, setCalendarId] = useState("");
  const [dedicatedId, setDedicatedId] = useState<string | null>(null);
  const [previous, setPrevious] = useState("auto");
  const [pages, setPages] = useState<string[]>([]);
  const [proposal, setProposal] = useState<Proposal | null>(null);
  const [proposalInput, setProposalInput] = useState("");
  const [approveRemovals, setApproveRemovals] = useState(false);
  const [replacement, setReplacement] = useState(false);
  const [results, setResults] = useState<WriteResult[]>([]);
  const input = JSON.stringify([
    run,
    w.preferences,
    calendarId,
    previous,
    pages,
    replacement,
  ]);
  const current = proposalInput === input ? proposal : null;
  const eligible =
    w.native &&
    run.review_confirmed &&
    run.appointments.some((a) => a.included) &&
    !run.appointments.some((a) => problems(a).length);
  const schedules = [
    ...new Set(w.history.imports.map((record) => record.schedule_id)),
  ];
  useEffect(() => {
    if (!w.native) return;
    let disposed = false;
    void command<string[]>("page_group", { id: run.document.id })
      .then((ids) => {
        if (!disposed) setPages(ids.filter((id) => id !== run.document.id));
      })
      .catch(w.report);
    return () => {
      disposed = true;
    };
  }, [w.native, run.document.id, w.report]);

  async function connect() {
    await w.execute("Setting up Reha Calendar", async () => {
      const value = await command<CalendarConnection>("calendars", {
        dedicated: true,
      });
      setCalendars(value.calendars);
      setDedicatedId(value.dedicated_id ?? null);
      // Revisions must keep their recorded destination; new imports use the
      // dedicated calendar. A setup failure never falls back to the default.
      const scheduleId = w.history.scans.find(
        (scan) => scan.id === run.document.id,
      )?.schedule_id;
      const previousCalendar = scheduleId
        ? w.history.imports.find((record) => record.schedule_id === scheduleId)
            ?.calendar_id
        : undefined;
      setCalendarId(
        previousCalendar &&
          value.calendars.some((calendar) => calendar.id === previousCalendar)
          ? previousCalendar
          : (value.dedicated_id ?? ""),
      );
      if (value.setup_error) w.report(value.setup_error);
    });
  }
  async function prepare() {
    await w.execute("Comparing calendar snapshots", async () => {
      await w.flush();
      setProposal(
        await command<Proposal>("prepare_calendar", {
          id: run.document.id,
          calendarId,
          previous: previous === "auto" ? null : previous,
          timezone: w.preferences.timezone,
          reminder: w.preferences.reminder,
          replacement,
        }),
      );
      setProposalInput(input);
      setApproveRemovals(false);
      setResults([]);
    });
  }
  async function resolve(eventId: string, choice: string) {
    if (!current) return;
    await w.execute("Resolving operation", async () =>
      setProposal(
        await command<Proposal>("resolve_proposal", {
          token: current.token,
          eventId,
          choice,
        }),
      ),
    );
  }
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant="outline"
          disabled={!eligible || !!w.busy}
          onClick={() =>
            w.execute("Exporting iCalendar", async () => {
              await w.flush();
              const content = await command<string>("export_ics", {
                id: run.document.id,
                timezone: w.preferences.timezone,
                reminder: w.preferences.reminder,
              });
              await exportFile(
                content,
                `schedule-${run.appointments[0]?.date ?? run.id}.ics`,
                "text/calendar;charset=utf-8",
              );
            })
          }
        >
          Export .ics
        </Button>
        <Button
          variant="outline"
          disabled={w.runtime?.platform !== "ios" || !!w.busy}
          onClick={connect}
        >
          Set up Reha Calendar
        </Button>
        <p className="text-xs text-muted-foreground">
          {w.preferences.timezone} ·{" "}
          {run.review_confirmed ? "review confirmed" : "review required"}
        </p>
      </div>
      {w.runtime?.platform === "ios" && (
        <FieldDescription>
          New imports use a separate Reha Calendar. In Apple Calendar, open
          Calendars and select or deselect it to show or hide these
          appointments. Existing imports keep their recorded calendar.
        </FieldDescription>
      )}
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="calendar">Calendar</FieldLabel>
          <Select
            value={calendarId}
            onValueChange={setCalendarId}
            disabled={!calendars.length || !!w.busy}
          >
            <SelectTrigger id="calendar">
              <SelectValue
                placeholder={
                  calendars.length
                    ? "Select a destination calendar"
                    : "Set up calendar access"
                }
              />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                {calendars.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.title}
                    {c.source ? ` · ${c.source}` : ""}
                    {c.id === dedicatedId ? " (Reha imports)" : ""}
                    {c.is_default ? " (default)" : ""}
                  </SelectItem>
                ))}
              </SelectGroup>
            </SelectContent>
          </Select>
        </Field>
        <Field>
          <FieldLabel htmlFor="previous">Previous import</FieldLabel>
          <Select
            value={previous}
            onValueChange={setPrevious}
            disabled={!!w.busy}
          >
            <SelectTrigger id="previous">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                <SelectItem value="auto">Automatic matching</SelectItem>
                {schedules.map((id) => (
                  <SelectItem key={id} value={id}>
                    {id}
                  </SelectItem>
                ))}
              </SelectGroup>
            </SelectContent>
          </Select>
        </Field>
        {w.native && (
          <FieldSet>
            <FieldLegend>Page group</FieldLegend>
            <FieldDescription>
              Explicitly group reviewed pages from one day before comparing or
              exporting.
            </FieldDescription>
            <FieldGroup>
              {w.history.scans
                .filter((scan) => scan.retained && scan.id !== run.document.id)
                .map((scan) => (
                  <Field key={scan.id} orientation="horizontal">
                    <Checkbox
                      id={`page-${scan.id}`}
                      disabled={!!w.busy}
                      checked={pages.includes(scan.id)}
                      onCheckedChange={(value) =>
                        setPages(
                          value === true
                            ? [...pages, scan.id]
                            : pages.filter((id) => id !== scan.id),
                        )
                      }
                    />
                    <FieldLabel htmlFor={`page-${scan.id}`}>
                      {scan.id.slice(0, 8)} · {scan.item_count} items
                    </FieldLabel>
                  </Field>
                ))}
            </FieldGroup>
            <Button
              variant="outline"
              disabled={!eligible || !!w.busy}
              onClick={() =>
                w.execute("Saving page group", async () => {
                  await w.flush();
                  await command("set_page_group", {
                    id: run.document.id,
                    pageIds: pages,
                  });
                  setProposal(null);
                })
              }
            >
              Confirm page group
            </Button>
          </FieldSet>
        )}
      </FieldGroup>
      <Field orientation="horizontal">
        <Checkbox
          id="complete-replacement"
          checked={replacement}
          disabled={!run.complete_page_confirmed || !!w.busy}
          onCheckedChange={(v) => setReplacement(v === true)}
        />
        <FieldLabel htmlFor="complete-replacement">
          Complete replacement: propose removals for missing appointments
        </FieldLabel>
      </Field>
      <Button disabled={!eligible || !calendarId || !!w.busy} onClick={prepare}>
        Prepare calendar operations
      </Button>
      {current && (
        <>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Operation</TableHead>
                <TableHead>Event</TableHead>
                <TableHead>Resolution</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {current.operations.map((op) => (
                <TableRow key={op.id}>
                  <TableCell>
                    <Badge
                      variant={
                        op.requires_resolution ? "destructive" : "outline"
                      }
                    >
                      {op.kind}
                    </Badge>
                  </TableCell>
                  <TableCell className="whitespace-normal">
                    {(op.after ?? op.before)?.title}
                    <p className="text-xs text-muted-foreground">{op.reason}</p>
                  </TableCell>
                  <TableCell>
                    {op.requires_resolution && (
                      <div className="flex flex-wrap gap-2">
                        <Button
                          variant="outline"
                          disabled={!!w.busy}
                          onClick={() => resolve(op.id, "keep")}
                        >
                          Keep calendar
                        </Button>
                        {op.kind === "conflict" && op.before && op.after && (
                          <Button
                            variant="outline"
                            disabled={!!w.busy}
                            onClick={() => resolve(op.id, "paper")}
                          >
                            Use extraction
                          </Button>
                        )}
                        {op.kind === "ambiguous" && (
                          <>
                            <Button
                              variant="outline"
                              disabled={!!w.busy}
                              onClick={() => resolve(op.id, "new")}
                            >
                              Create separate event
                            </Button>
                            <Select
                              onValueChange={(id) =>
                                resolve(op.id, `match:${id}`)
                              }
                              disabled={!!w.busy}
                            >
                              <SelectTrigger aria-label={`Match ${op.id}`}>
                                <SelectValue placeholder="Match existing event" />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectGroup>
                                  {current.operations
                                    .filter(
                                      (o) =>
                                        o.kind === "keep" &&
                                        !o.after &&
                                        o.before &&
                                        o.external_id,
                                    )
                                    .map((o) => (
                                      <SelectItem key={o.id} value={o.id}>
                                        {o.before?.title} ·{" "}
                                        {o.before?.start_utc}
                                      </SelectItem>
                                    ))}
                                </SelectGroup>
                              </SelectContent>
                            </Select>
                          </>
                        )}
                      </div>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <JsonView
            value={current.operations.map((op) => ({
              id: op.id,
              before: op.before,
              after: op.after,
            }))}
          />
          {current.operations.some((o) => o.kind === "remove") && (
            <Field orientation="horizontal">
              <Checkbox
                id="approve-removals"
                checked={approveRemovals}
                onCheckedChange={(value) => setApproveRemovals(value === true)}
              />
              <FieldLabel htmlFor="approve-removals">
                Approve proposed removals
              </FieldLabel>
            </Field>
          )}
          <Button
            disabled={
              !!w.busy ||
              !eligible ||
              current.operations.some(
                (o) =>
                  o.requires_resolution ||
                  (o.kind === "remove" && !approveRemovals),
              )
            }
            onClick={() =>
              w.execute("Applying approved operations", async () => {
                await w.flush();
                setResults(
                  await command<WriteResult[]>("approve_calendar", {
                    token: current.token,
                    approveRemovals,
                  }),
                );
                setProposal(null);
                await w.refresh();
              })
            }
          >
            Approve and apply
          </Button>
        </>
      )}
      {!!results.length && <JsonView value={results} />}
    </div>
  );
}
