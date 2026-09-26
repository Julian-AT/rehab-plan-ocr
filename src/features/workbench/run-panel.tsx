"use client";

import { useState } from "react";
import { Download, RotateCw, Play } from "lucide-react";
import type { Workbench } from "./use-workbench";
import type { Point, Run } from "@/lib/contracts";
import { exportFile } from "@/lib/native";
import { problems } from "@/lib/validation";
import { SourceViewer } from "@/components/source-viewer";
import { AppointmentEditor } from "@/components/appointment-editor";
import { TracePanel } from "./trace-panel";
import { CalendarPanel } from "@/features/calendar/calendar-panel";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";

export function RunPanel({
  workbench: w,
  run,
}: {
  workbench: Workbench;
  run: Run;
}) {
  const [highlight, setHighlight] = useState<string[]>([]);
  const [crop, setCrop] = useState(false);
  const [corners, setCorners] = useState<Point[]>([]);
  const [date, setDate] = useState(run.appointments[0]?.date ?? "");
  const unresolved = run.appointments.some((a) => problems(a).length > 0);
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <h2 className="truncate text-sm font-medium">
            {run.document.filename}
          </h2>
          <Badge variant="outline">{run.engine}</Badge>
          <Badge variant="secondary">{run.total_ms} ms</Badge>
          <Badge variant="outline">{run.cache_used ? "warm" : "cold"}</Badge>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            disabled={!w.native || !!w.busy}
            onClick={() =>
              w.reprocess({
                ...w.config,
                quarter_turns: (run.config.quarter_turns + 1) % 4,
                page_corners: null,
              })
            }
          >
            <RotateCw data-icon="inline-start" />
            Rotate 90°
          </Button>
          <Button
            variant="outline"
            disabled={!w.native || !!w.busy || (crop && corners.length !== 4)}
            onClick={() =>
              w.reprocess({
                ...w.config,
                quarter_turns: run.config.quarter_turns,
                page_corners: crop
                  ? (corners as [Point, Point, Point, Point])
                  : run.config.page_corners,
              })
            }
          >
            <Play data-icon="inline-start" />
            Reprocess
          </Button>
          <Button
            variant="outline"
            disabled={!!w.busy}
            onClick={() =>
              w.execute("Exporting run", () =>
                exportFile(JSON.stringify(run, null, 2), `run-${run.id}.json`),
              )
            }
          >
            <Download data-icon="inline-start" />
            Run JSON
          </Button>
        </div>
      </div>
      <div className="grid min-w-0 items-start gap-5 xl:grid-cols-[minmax(280px,1fr)_minmax(0,2fr)]">
        <div className="flex min-w-0 flex-col gap-3 xl:sticky xl:top-4">
          <SourceViewer
            run={run}
            native={w.native}
            highlight={highlight}
            onRegion={(id) =>
              setHighlight(
                run.observations
                  .filter((o) => o.region_ids.includes(id))
                  .map((o) => o.id),
              )
            }
            corners={corners}
            onCorner={
              crop
                ? (point) =>
                    setCorners((value) =>
                      value.length < 4 ? [...value, point] : [point],
                    )
                : undefined
            }
          />
          <Field orientation="horizontal">
            <Checkbox
              id="crop"
              disabled={!w.native || !!w.busy}
              checked={crop}
              onCheckedChange={(value) => {
                setCrop(value === true);
                setCorners([]);
              }}
            />
            <FieldLabel htmlFor="crop">Manual page boundary</FieldLabel>
          </Field>
          {crop && (
            <FieldGroup>
              <FieldDescription>
                Select four corners clockwise, starting top left. Coordinates
                refer to the original image.
              </FieldDescription>
              {[0, 1, 2, 3].map((index) => (
                <Field key={index} orientation="horizontal">
                  <FieldLabel htmlFor={`corner-${index}-x`}>
                    Point {index + 1}
                  </FieldLabel>
                  {["x", "y"].map((axis) => (
                    <Input
                      key={axis}
                      id={`corner-${index}-${axis}`}
                      aria-label={`Point ${index + 1} ${axis}`}
                      type="number"
                      min={0}
                      max={
                        axis === "x" ? run.document.width : run.document.height
                      }
                      value={corners[index]?.[axis as "x" | "y"] ?? ""}
                      onChange={(e) =>
                        setCorners((points) =>
                          Array.from(
                            { length: Math.max(index + 1, points.length) },
                            (_, i) =>
                              i === index
                                ? {
                                    ...(points[i] ?? { x: 0, y: 0 }),
                                    [axis]: Number(e.target.value),
                                  }
                                : (points[i] ?? { x: 0, y: 0 }),
                          ),
                        )
                      }
                    />
                  ))}
                </Field>
              ))}
            </FieldGroup>
          )}
        </div>
        <Tabs defaultValue="appointments" className="min-w-0">
          <TabsList>
            <TabsTrigger value="appointments">Appointments</TabsTrigger>
            <TabsTrigger value="trace">Trace</TabsTrigger>
            <TabsTrigger value="calendar">Calendar</TabsTrigger>
          </TabsList>
          <TabsContent
            value="appointments"
            className="flex min-w-0 flex-col gap-5"
          >
            <FieldGroup>
              <Field orientation="responsive">
                <FieldLabel htmlFor="treatment-date">Treatment date</FieldLabel>
                <Input
                  id="treatment-date"
                  type="date"
                  value={date}
                  className="max-w-48"
                  onChange={(event) => setDate(event.target.value)}
                />
                <Button
                  variant="outline"
                  disabled={!date || !!w.busy}
                  onClick={() =>
                    w.updateRun({
                      appointments: run.appointments.map((a) => ({
                        ...a,
                        date,
                      })),
                    })
                  }
                >
                  Apply to all rows
                </Button>
              </Field>
            </FieldGroup>
            <AppointmentEditor
              appointments={run.appointments}
              onChange={(appointments) => w.updateRun({ appointments })}
              onHighlight={setHighlight}
              disabled={!!w.busy}
            />
            <FieldGroup>
              <Field orientation="horizontal">
                <Checkbox
                  id="complete-page"
                  disabled={!!w.busy}
                  checked={run.complete_page_confirmed}
                  onCheckedChange={(value) =>
                    w.updateRun({ complete_page_confirmed: value === true })
                  }
                />
                <FieldLabel htmlFor="complete-page">
                  Complete replacement page
                </FieldLabel>
              </Field>
              <Field orientation="horizontal">
                <Checkbox
                  id="review-confirmed"
                  disabled={
                    unresolved ||
                    !!w.busy ||
                    !run.appointments.some((a) => a.included)
                  }
                  checked={run.review_confirmed}
                  onCheckedChange={(value) =>
                    w.updateRun({ review_confirmed: value === true }, false)
                  }
                />
                <FieldLabel htmlFor="review-confirmed">
                  Review confirmed, including unassigned observations
                </FieldLabel>
              </Field>
            </FieldGroup>
          </TabsContent>
          <TabsContent value="trace">
            <TracePanel
              run={run}
              native={w.native}
              highlight={highlight}
              onHighlight={setHighlight}
            />
          </TabsContent>
          <TabsContent value="calendar">
            <CalendarPanel workbench={w} run={run} />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
}
