"use client";

import { useState } from "react";
import { Plus, Settings2, Trash2 } from "lucide-react";
import type { Appointment } from "@/lib/contracts";
import { emptyAppointment, problems } from "@/lib/validation";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";

const columns = [
  { key: "date", label: "Date", type: "date", width: "w-36" },
  { key: "start", label: "Start", type: "time", width: "w-28" },
  { key: "end", label: "End", type: "time", width: "w-28" },
  { key: "title", label: "Title", type: "text", width: "w-52" },
  { key: "location", label: "Room", type: "text", width: "w-36" },
  { key: "therapist", label: "Therapeut", type: "text", width: "w-52" },
] as const;

export function AppointmentEditor({
  appointments,
  onChange,
  onHighlight,
  onReview,
  disabled = false,
}: {
  appointments: Appointment[];
  onChange: (value: Appointment[]) => void;
  onHighlight?: (ids: string[]) => void;
  onReview?: (appointment: Appointment) => void;
  disabled?: boolean;
}) {
  const [details, setDetails] = useState<string | null>(null);
  const active = appointments.find((a) => a.id === details);
  const selected = appointments.filter((a) => a.included);
  function edit(id: string, patch: Partial<Appointment>) {
    onChange(appointments.map((a) => (a.id === id ? { ...a, ...patch } : a)));
  }
  function focus(a: Appointment, field: string) {
    onHighlight?.(a.provenance[field] ?? []);
  }
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm" role="status">
          {selected.length} selected / {appointments.length} extracted
        </p>
        <Button
          variant="outline"
          disabled={disabled}
          onClick={() =>
            onChange([
              ...appointments,
              emptyAppointment(appointments[0]?.date ?? null),
            ])
          }
        >
          <Plus data-icon="inline-start" />
          Add row
        </Button>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>
              <Checkbox
                aria-label="Select all appointments"
                disabled={disabled || !appointments.length}
                checked={
                  selected.length === appointments.length &&
                  !!appointments.length
                    ? true
                    : selected.length
                      ? "indeterminate"
                      : false
                }
                onCheckedChange={(value) =>
                  onChange(
                    appointments.map((a) => ({
                      ...a,
                      included: value === true,
                    })),
                  )
                }
              />
            </TableHead>
            {columns.map((column) => (
              <TableHead key={column.key}>{column.label}</TableHead>
            ))}
            <TableHead>Status</TableHead>
            <TableHead>
              <span className="sr-only">Details</span>
            </TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {appointments.map((a, index) => {
            const errors = problems(a);
            return (
              <TableRow
                key={a.id}
                data-state={a.included ? "selected" : undefined}
              >
                <TableCell>
                  <Checkbox
                    aria-label={`Include row ${index + 1}`}
                    disabled={disabled}
                    checked={a.included}
                    onCheckedChange={(value) =>
                      edit(a.id, { included: value === true })
                    }
                  />
                </TableCell>
                {columns.map(({ key, label, type, width }) => (
                  <TableCell key={key}>
                    <Field
                      data-invalid={
                        a.included &&
                        !a[key] &&
                        ["date", "start", "title"].includes(key)
                      }
                    >
                      <FieldLabel
                        htmlFor={`${a.id}-${key}`}
                        className="sr-only"
                      >
                        {label} row {index + 1}
                      </FieldLabel>
                      <Input
                        id={`${a.id}-${key}`}
                        className={width}
                        type={type}
                        disabled={disabled}
                        value={a[key] ?? ""}
                        aria-invalid={
                          a.included &&
                          !a[key] &&
                          ["date", "start", "title"].includes(key)
                        }
                        onFocus={() => focus(a, key)}
                        onChange={(event) =>
                          edit(a.id, {
                            [key]:
                              event.target.value ||
                              (type === "text" ? "" : null),
                          })
                        }
                      />
                    </Field>
                  </TableCell>
                ))}
                <TableCell>
                  <Badge variant={errors.length ? "destructive" : "secondary"}>
                    {errors.length
                      ? `${errors.length} unresolved`
                      : a.included
                        ? "valid"
                        : "excluded"}
                  </Badge>
                </TableCell>
                <TableCell>
                  {onReview && (
                    <Button
                      variant="outline"
                      disabled={disabled}
                      aria-label={`Am Foto prüfen, Zeile ${index + 1}`}
                      onClick={() => onReview(a)}
                    >
                      Am Foto prüfen
                    </Button>
                  )}
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Details row ${index + 1}`}
                    onClick={() => setDetails(a.id)}
                  >
                    <Settings2 />
                  </Button>
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
      {appointments.some((a) => problems(a).length) && (
        <ul
          aria-label="Validation errors"
          className="flex flex-col gap-1 text-sm text-destructive"
        >
          {appointments.flatMap((a, index) =>
            problems(a).map((message) => (
              <li key={`${a.id}-${message}`}>
                Row {index + 1}: {message}
              </li>
            )),
          )}
        </ul>
      )}
      <Dialog
        open={!!active}
        onOpenChange={(open) => {
          if (!open) setDetails(null);
        }}
      >
        <DialogContent
          className="max-h-[85vh] overflow-y-auto sm:max-w-lg"
          aria-describedby={undefined}
        >
          <DialogHeader>
            <DialogTitle>Appointment details</DialogTitle>
          </DialogHeader>
          {active && (
            <FieldGroup>
              <Field>
                <FieldLabel htmlFor="end-date">End date</FieldLabel>
                <Input
                  id="end-date"
                  type="date"
                  disabled={disabled}
                  value={active.end_date ?? ""}
                  onFocus={() => focus(active, "end_date")}
                  onChange={(e) =>
                    edit(active.id, { end_date: e.target.value || null })
                  }
                />
                <FieldDescription>
                  Required for overnight appointments.
                </FieldDescription>
              </Field>
              <Field>
                <FieldLabel htmlFor="duration">Duration (minutes)</FieldLabel>
                <Input
                  id="duration"
                  type="number"
                  min={1}
                  max={1440}
                  disabled={disabled}
                  value={active.duration_minutes ?? ""}
                  onFocus={() => focus(active, "duration_minutes")}
                  onChange={(e) =>
                    edit(active.id, {
                      duration_minutes: e.target.value
                        ? Number(e.target.value)
                        : null,
                    })
                  }
                />
              </Field>
              <Field>
                <FieldLabel htmlFor="notes">Notes</FieldLabel>
                <Textarea
                  id="notes"
                  disabled={disabled}
                  value={active.notes}
                  onFocus={() => focus(active, "notes")}
                  onChange={(e) => edit(active.id, { notes: e.target.value })}
                />
              </Field>
              {active.issues
                .filter(
                  (i) =>
                    ![
                      "missing_date",
                      "missing_start",
                      "missing_end",
                      "invalid_end",
                      "overnight_confirmation",
                      "missing_title",
                    ].includes(i.code),
                )
                .map((issue, index) => (
                  <Field key={`${issue.code}-${index}`}>
                    <FieldDescription>
                      {issue.code}: {issue.message}
                    </FieldDescription>
                    <Button
                      variant="outline"
                      disabled={disabled}
                      onClick={() =>
                        edit(active.id, {
                          issues: active.issues.filter(
                            (value) => value !== issue,
                          ),
                        })
                      }
                    >
                      Mark checked
                    </Button>
                  </Field>
                ))}
              <Button
                variant="destructive"
                disabled={disabled}
                onClick={() => {
                  onChange(appointments.filter((a) => a.id !== active.id));
                  setDetails(null);
                }}
              >
                <Trash2 data-icon="inline-start" />
                Remove row
              </Button>
            </FieldGroup>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
