"use client";

import { useState } from "react";
import type { Annotation } from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { parseAnnotation, readJson } from "@/lib/annotation";
import { command, exportFile } from "@/lib/native";
import { AppointmentEditor } from "@/components/appointment-editor";
import { JsonView } from "@/components/json-view";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";

export function AnnotationPanel({ workbench: w }: { workbench: Workbench }) {
  const [reference, setReference] = useState<Annotation | null>(null);
  const [comparison, setComparison] = useState<unknown>(null);
  const [report, setReport] = useState<unknown>(null);
  const [saved, setSaved] = useState(false);
  function edit(patch: Partial<Annotation>) {
    if (reference)
      setReference({
        ...reference,
        ...patch,
        verified: false,
        reviewed_at: null,
      });
    setSaved(false);
    setReport(null);
  }
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <FieldGroup className="sm:flex-row sm:items-end">
        <Field>
          <FieldLabel htmlFor="reference-file">Reference JSON</FieldLabel>
          <Input
            id="reference-file"
            type="file"
            accept="application/json"
            disabled={!!w.busy}
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              if (file)
                void w.execute("Loading reference", async () => {
                  setReference(parseAnnotation(await readJson(file)));
                  setSaved(false);
                  setReport(null);
                });
            }}
          />
        </Field>
        <Field>
          <FieldLabel htmlFor="comparison-file">
            Comparison run JSON (optional)
          </FieldLabel>
          <Input
            id="comparison-file"
            type="file"
            accept="application/json"
            disabled={!!w.busy}
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              if (file)
                void w.execute("Loading comparison", async () => {
                  setComparison(await readJson(file));
                  setReport(null);
                });
            }}
          />
        </Field>
        <Button
          variant="outline"
          disabled={!w.run || !!w.busy}
          onClick={() => {
            if (w.run) {
              setReference({
                schema_version: 1,
                day_id: w.run.appointments[0]?.date ?? "",
                document_hashes: [w.run.document.source_hash],
                verified: false,
                reviewed_at: null,
                split: "development",
                appointments: structuredClone(w.run.appointments),
                uncertainty_notes: [],
              });
              setSaved(false);
              setReport(null);
            }
          }}
        >
          Draft from active run
        </Button>
      </FieldGroup>
      <Button
        variant="outline"
        disabled={!w.native || !w.run || !!w.busy}
        onClick={() =>
          w.execute("Loading provisional reference", async () => {
            const value = await command<Annotation>("provisional_reference", {
              hash: w.run!.document.source_hash,
            });
            setReference(value);
            setSaved(false);
            setReport(null);
          })
        }
      >
        Load provisional reference for active image
      </Button>
      {reference && (
        <>
          <FieldGroup className="sm:flex-row">
            <Field>
              <FieldLabel htmlFor="day-id">Day ID</FieldLabel>
              <Input
                id="day-id"
                value={reference.day_id}
                onChange={(e) => edit({ day_id: e.target.value })}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor="split">Split</FieldLabel>
              <Select
                value={reference.split}
                onValueChange={(split) => edit({ split })}
              >
                <SelectTrigger id="split">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectGroup>
                    <SelectItem value="development">development</SelectItem>
                    <SelectItem value="holdout">holdout</SelectItem>
                  </SelectGroup>
                </SelectContent>
              </Select>
            </Field>
          </FieldGroup>
          <AppointmentEditor
            appointments={reference.appointments}
            onChange={(appointments) => edit({ appointments })}
            disabled={!!w.busy}
          />
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="uncertainty">
                Unresolved annotation questions
              </FieldLabel>
              <Textarea
                id="uncertainty"
                value={reference.uncertainty_notes.join("\n")}
                onChange={(e) =>
                  edit({
                    uncertainty_notes: e.target.value
                      .split("\n")
                      .filter(Boolean),
                  })
                }
              />
            </Field>
            <Field orientation="horizontal">
              <Checkbox
                id="verified"
                checked={reference.verified}
                disabled={
                  !!reference.uncertainty_notes.length ||
                  !reference.appointments.length
                }
                onCheckedChange={(value) => {
                  setReference({
                    ...reference,
                    verified: value === true,
                    reviewed_at:
                      value === true ? new Date().toISOString() : null,
                  });
                  setSaved(false);
                  setReport(null);
                }}
              />
              <FieldLabel htmlFor="verified">
                All reference items verified against source
              </FieldLabel>
            </Field>
            <FieldDescription>
              Predictions are provisional annotations. Final holdout is locked
              in interactive evaluation.
            </FieldDescription>
          </FieldGroup>
          <div className="flex flex-wrap items-center gap-2">
            <Button
              disabled={!!w.busy || !reference.day_id.trim()}
              onClick={() =>
                w.execute("Saving reference", async () => {
                  const value = parseAnnotation(reference);
                  if (w.native)
                    await command("save_annotation", { annotation: value });
                  else
                    await exportFile(
                      JSON.stringify(value, null, 2),
                      `reference-${value.day_id}.json`,
                    );
                  setSaved(true);
                })
              }
            >
              {w.native ? "Save reference" : "Export reference"}
            </Button>
            <Button
              variant="outline"
              disabled={
                !w.native ||
                !!w.busy ||
                !reference.verified ||
                reference.split === "holdout" ||
                (!w.run && !comparison)
              }
              onClick={() =>
                w.execute("Evaluating reference", async () =>
                  setReport(
                    await command("evaluate_annotation", {
                      annotation: reference,
                      run: comparison ?? w.run,
                    }),
                  ),
                )
              }
            >
              Evaluate
            </Button>
            {comparison !== null && (
              <Button
                variant="ghost"
                onClick={() => {
                  setComparison(null);
                  setReport(null);
                }}
              >
                Use active run
              </Button>
            )}
            {saved && <Badge variant="secondary">saved</Badge>}
          </div>
        </>
      )}
      {report !== null && (
        <>
          <JsonView value={report} />
          <Button
            variant="outline"
            onClick={() =>
              w.execute("Exporting report", () =>
                exportFile(JSON.stringify(report, null, 2), "evaluation.json"),
              )
            }
          >
            Export report
          </Button>
        </>
      )}
      {comparison !== null && (
        <div className="grid min-w-0 gap-4 lg:grid-cols-2">
          <div>
            <h3 className="mb-2 text-sm font-medium">Active extraction</h3>
            <JsonView value={w.run?.appointments ?? []} />
          </div>
          <div>
            <h3 className="mb-2 text-sm font-medium">Comparison run</h3>
            <JsonView value={comparison} />
          </div>
        </div>
      )}
    </div>
  );
}
