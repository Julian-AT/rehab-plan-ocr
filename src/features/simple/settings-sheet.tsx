"use client";
import { useState } from "react";
import type {
  Calendar,
  CalendarConnection,
  CompletionDefault,
} from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { command } from "@/lib/native";
import { Panel } from "./panel";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { fieldLabels } from "./appointment-sheet";
export function SettingsSheet({
  w,
  close,
  developer,
}: {
  w: Workbench;
  close: () => void;
  developer: () => void;
}) {
  const [draft, setDraft] = useState(w.preferences);
  const [calendars, setCalendars] = useState<Calendar[]>([]);
  const [discard, setDiscard] = useState(false);
  const [erase, setErase] = useState(false);
  const dirty = JSON.stringify(draft) !== JSON.stringify(w.preferences);
  const defaults = draft.completion_defaults ?? [];
  const [completion, setCompletion] = useState<CompletionDefault>({
    id: "",
    clinic: "",
    treatment: "",
    field: "duration_minutes",
    value: 30,
  });
  const [editing, setEditing] = useState<string | null>(null);
  const select = (
    id: string,
    label: string,
    value: string,
    values: [string, string][],
    change: (value: string) => void,
  ) => (
    <Field>
      <FieldLabel htmlFor={id}>{label}</FieldLabel>
      <Select value={value} onValueChange={change} disabled={!!w.busy}>
        <SelectTrigger id={id}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectGroup>
            {values.map(([v, label]) => (
              <SelectItem key={v} value={v}>
                {label}
              </SelectItem>
            ))}
          </SelectGroup>
        </SelectContent>
      </Select>
    </Field>
  );
  return (
    <Panel
      title="Einstellungen"
      onClose={() => {
        if (!w.busy) {
          if (dirty) setDiscard(true);
          else close();
        }
      }}
      actions={
        <Button
          disabled={!!w.busy}
          onClick={async () => {
            if (await w.savePreferences({ ...draft, detailed_debug: false }))
              close();
          }}
        >
          {w.busy || "Einstellungen speichern"}
        </Button>
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
              Ungespeicherte Einstellungen verwerfen?
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
          {select(
            "appearance",
            "Darstellung",
            draft.appearance ?? "system",
            [
              ["system", "Wie das System"],
              ["light", "Hell"],
              ["dark", "Dunkel"],
            ],
            (appearance) =>
              setDraft({
                ...draft,
                appearance: appearance as "system" | "light" | "dark",
              }),
          )}
          <Field>
            <FieldLabel htmlFor="timezone">Zeitzone</FieldLabel>
            <Input
              id="timezone"
              value={draft.timezone}
              disabled={!!w.busy}
              onChange={(e) => setDraft({ ...draft, timezone: e.target.value })}
            />
          </Field>
          {select(
            "reminder",
            "Erinnerung",
            String(draft.reminder ?? "none"),
            [
              ["none", "Keine"],
              ["5", "5 Minuten vorher"],
              ["15", "15 Minuten vorher"],
              ["30", "30 Minuten vorher"],
              ["60", "1 Stunde vorher"],
            ],
            (value) =>
              setDraft({
                ...draft,
                reminder: value === "none" ? null : Number(value),
              }),
          )}
          {w.runtime?.platform === "ios" && (
            <Button
              variant="outline"
              disabled={!!w.busy}
              onClick={() =>
                w.execute("Kalender werden geladen", async () => {
                  const result = await command<CalendarConnection>(
                    "calendars",
                    { dedicated: true },
                  );
                  setCalendars(result.calendars);
                  setDraft((d) => ({
                    ...d,
                    calendar_id: d.calendar_id || result.dedicated_id || "",
                  }));
                  if (result.setup_error) w.report(result.setup_error);
                })
              }
            >
              Kalender auswählen
            </Button>
          )}
          {!!calendars.length &&
            select(
              "default-calendar",
              "Kalender für neue Pläne",
              draft.calendar_id ?? "",
              calendars.map((c) => [
                c.id,
                `${c.title}${c.source ? ` · ${c.source}` : ""}`,
              ]),
              (calendar_id) => setDraft({ ...draft, calendar_id }),
            )}
        </FieldGroup>
        <details>
          <summary>Ergänzungsvorgaben</summary>
          <div className="mt-4 flex flex-col gap-4">
            <p className="text-sm text-muted-foreground">
              Vorgaben gelten nur für dieselbe Klinik und Behandlung. Jeder
              Vorschlag muss beim Termin bestätigt werden.
            </p>
            {defaults.map((d) => (
              <div key={d.id} className="flex flex-wrap items-center gap-2">
                <p className="flex-1 text-sm">
                  {d.clinic} · {d.treatment} · {fieldLabels[d.field]}:{" "}
                  {String(d.value)}
                </p>
                <Button
                  variant="outline"
                  onClick={() => {
                    setCompletion(d);
                    setEditing(d.id);
                  }}
                >
                  Bearbeiten
                </Button>
                <Button
                  variant="ghost"
                  onClick={() =>
                    setDraft({
                      ...draft,
                      completion_defaults: defaults.filter(
                        (v) => v.id !== d.id,
                      ),
                    })
                  }
                >
                  Entfernen
                </Button>
              </div>
            ))}
            <FieldGroup>
              {[
                ["clinic", "Klinik"],
                ["treatment", "Behandlung"],
              ].map(([field, label]) => (
                <Field key={field}>
                  <FieldLabel htmlFor={`default-${field}`}>{label}</FieldLabel>
                  <Input
                    id={`default-${field}`}
                    value={completion[field as "clinic" | "treatment"]}
                    onChange={(e) =>
                      setCompletion({ ...completion, [field]: e.target.value })
                    }
                  />
                </Field>
              ))}
              {select(
                "default-field",
                "Ergänzungsfeld",
                completion.field,
                [
                  "duration_minutes",
                  "location",
                  "therapist",
                  "preparation",
                ].map((f) => [f, fieldLabels[f]]),
                (field) =>
                  setCompletion({
                    ...completion,
                    field,
                    value: field === "duration_minutes" ? 30 : "",
                  }),
              )}
              <Field>
                <FieldLabel htmlFor="default-value">Wert</FieldLabel>
                <Input
                  id="default-value"
                  type={
                    completion.field === "duration_minutes" ? "number" : "text"
                  }
                  min={1}
                  max={1440}
                  value={completion.value}
                  onChange={(e) =>
                    setCompletion({
                      ...completion,
                      value:
                        completion.field === "duration_minutes"
                          ? Number(e.target.value)
                          : e.target.value,
                    })
                  }
                />
              </Field>
              <Button
                variant="outline"
                disabled={
                  !completion.clinic.trim() ||
                  !completion.treatment.trim() ||
                  !completion.value
                }
                onClick={() => {
                  setDraft({
                    ...draft,
                    completion_defaults: [
                      ...defaults.filter((d) => d.id !== editing),
                      { ...completion, id: editing ?? crypto.randomUUID() },
                    ],
                  });
                  setEditing(null);
                  setCompletion({ ...completion, id: "", treatment: "" });
                }}
              >
                Vorgabe übernehmen
              </Button>
            </FieldGroup>
          </div>
        </details>
        <details>
          <summary>Speicher</summary>
          <FieldGroup className="mt-4">
            <FieldDescription>
              Fotos, Entwürfe und Prüfnachweise werden nach 30 Tagen entfernt.
              Bestätigte Kalenderzuordnungen und eigene Vorgaben bleiben
              erhalten.
            </FieldDescription>
            <Button
              variant="outline"
              disabled={!w.native || !!w.busy}
              onClick={() =>
                w.execute("Speicher wird bereinigt", async () => {
                  await command("maintenance");
                  await w.refresh();
                })
              }
            >
              Abgelaufene Fotos bereinigen
            </Button>
            {w.run && (
              <Button
                variant="outline"
                disabled={!w.native || !!w.busy}
                onClick={() =>
                  w.execute("Foto wird gelöscht", async () => {
                    await w.removeScan(w.run!.document.id);
                    close();
                  })
                }
              >
                Aktuelles Foto und Entwurf löschen
              </Button>
            )}
            <Button
              variant="destructive"
              disabled={!w.native || !!w.busy}
              onClick={() => setErase(true)}
            >
              Alle App-Daten löschen
            </Button>
            {erase && (
              <Alert>
                <AlertDescription>
                  Fotos, Entwürfe, Vorgaben und Kalenderzuordnungen löschen?
                  Kalendertermine bleiben bestehen.
                  <Button
                    variant="destructive"
                    disabled={!!w.busy}
                    onClick={() =>
                      w.execute("App-Daten werden gelöscht", async () => {
                        await w.eraseAll();
                        close();
                      })
                    }
                  >
                    App-Daten endgültig löschen
                  </Button>
                </AlertDescription>
              </Alert>
            )}
          </FieldGroup>
        </details>
        <Button variant="outline" disabled={dirty} onClick={developer}>
          Entwickleransicht öffnen
        </Button>
        {dirty && (
          <p className="text-sm text-muted-foreground">
            Einstellungen zuerst speichern oder schließen.
          </p>
        )}
      </div>
    </Panel>
  );
}
