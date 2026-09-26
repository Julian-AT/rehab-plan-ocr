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
import type { Agenda } from "./use-agenda";
import type { AgendaResponse } from "@/lib/agenda";
import { fieldLabels } from "./appointment-sheet";
export function SettingsSheet({
  w,
  close,
  developer,
  agenda,
}: {
  w: Workbench;
  close: () => void;
  developer: () => void;
  agenda: Agenda;
}) {
  const [testNotice, setTestNotice] = useState("");
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
            if (await w.savePreferences({ ...draft, detailed_debug: false })) {
              await agenda.refresh();
              close();
            }
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
        <section
          className="settings-section"
          aria-labelledby="reminders-heading"
        >
          <h2 id="reminders-heading">Erinnerungen</h2>
          <p>
            {agenda.data.reminders.authorization === "denied"
              ? "Mitteilungen sind nicht erlaubt. Aktiviere sie in den iPhone-Einstellungen. Kalenderalarme bleiben zuständig."
              : agenda.data.reminders.enabled
                ? `${agenda.data.reminders.scheduled} App-Erinnerungen eingeplant. Weitere Termine bleiben im Kalender abgesichert.`
                : "Eine ruhige Erinnerung vor deinem Termin. Bestehende Kalenderalarme bleiben bis zur Aktivierung erhalten."}
          </p>
          {select(
            "app-reminder",
            "Vorlauf",
            String(
              draft.app_reminder_minutes === null
                ? "none"
                : (draft.app_reminder_minutes ?? 10),
            ),
            [
              ["none", "Aus"],
              ["5", "5 Minuten vorher"],
              ["10", "10 Minuten vorher"],
              ["15", "15 Minuten vorher"],
              ["30", "30 Minuten vorher"],
              ["60", "60 Minuten vorher"],
            ],
            (value) =>
              setDraft({
                ...draft,
                app_reminder_minutes: value === "none" ? null : Number(value),
                reminder: value === "none" ? null : Number(value),
              }),
          )}
          <label className="settings-toggle">
            <input
              type="checkbox"
              checked={draft.reminder_sound ?? true}
              onChange={(e) =>
                setDraft({ ...draft, reminder_sound: e.target.checked })
              }
            />
            Mit Ton
          </label>
          <label className="settings-toggle">
            <input
              type="checkbox"
              checked={draft.reminder_preview ?? true}
              onChange={(e) =>
                setDraft({ ...draft, reminder_preview: e.target.checked })
              }
            />
            Behandlung und Raum anzeigen
          </label>
          {!agenda.data.reminders.enabled && (
            <Button
              disabled={!agenda.native || !!w.busy}
              onClick={async () => {
                if (!(await w.savePreferences(draft))) return;
                const result = await w.execute(
                  "Erinnerungen werden aktiviert",
                  () => command<AgendaResponse>("enable_reminders"),
                );
                if (result) {
                  agenda.setData(result);
                  if (
                    ["authorized", "provisional"].includes(
                      result.reminders.authorization,
                    )
                  ) {
                    const next = { ...draft, app_reminders_enabled: true };
                    setDraft(next);
                    await w.savePreferences(next);
                  }
                }
              }}
            >
              Erinnerungen aktivieren
            </Button>
          )}
          {!agenda.native && (
            <p>Erinnerungen sind in der installierten iPhone-App verfügbar.</p>
          )}
          {agenda.data.reminders.protected > 0 && (
            <p>
              {agenda.data.reminders.protected} Termine mit eigenen
              Kalenderalarmen bleiben im Kalender.
            </p>
          )}
          {agenda.data.reminders.error && (
            <p role="alert">{agenda.data.reminders.error}</p>
          )}
          <Button
            variant="outline"
            disabled={
              !agenda.native ||
              !!w.busy ||
              !["authorized", "provisional"].includes(
                agenda.data.reminders.authorization,
              )
            }
            onClick={() =>
              w.execute("Testmitteilung wird eingeplant", async () => {
                await command("test_reminder");
                setTestNotice(
                  "Testmitteilung in 15 Sekunden. Du kannst dein iPhone jetzt sperren.",
                );
              })
            }
          >
            Testmitteilung in 15 Sekunden
          </Button>
          {testNotice && <p role="status">{testNotice}</p>}
          <p>
            Fokus und deine iOS-Mitteilungseinstellungen bestimmen, wann
            Mitteilungen erscheinen.
          </p>
        </section>
        <section className="settings-section" aria-labelledby="widgets-heading">
          <h2 id="widgets-heading">Widgets</h2>
          <p>
            Halte den Home-Bildschirm gedrückt und wähle „Bearbeiten“ → „Widget
            hinzufügen“ → „Laßnitzhöhe“. Auf dem Sperrbildschirm findest du
            „Laßnitzhöhe“ unter „Anpassen“.
          </p>
          <p>
            Widgets zeigen deine gespeicherten Termine. iOS bestimmt die
            Aktualisierung; öffne die App nach Kalenderänderungen.
          </p>
          <Button
            variant="outline"
            disabled={!agenda.native || agenda.loading}
            onClick={() => void agenda.refresh()}
          >
            Widgets aktualisieren
          </Button>
        </section>
        <section
          className="settings-section"
          aria-label="Darstellung und Kalender"
        >
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
                onChange={(e) =>
                  setDraft({ ...draft, timezone: e.target.value })
                }
              />
            </Field>
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
        </section>
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
              Fotos, Entwürfe und Prüfnachweise bleiben erhalten, bis du sie löschst.
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
                  Kalendertermine bleiben bestehen. App-Erinnerungen werden
                  entfernt und verwaltete Kalenderalarme vorher
                  wiederhergestellt.
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
