"use client";

import { useState } from "react";
import type { Workbench } from "./use-workbench";
import { exportFile } from "@/lib/native";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import { JsonView } from "@/components/json-view";

export function ConfigurationPanel({ workbench: w }: { workbench: Workbench }) {
  const [preferences, setPreferences] = useState(w.preferences);
  return (
    <div className="grid min-w-0 gap-8 lg:grid-cols-2">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void w.savePreferences(preferences);
        }}
      >
        <FieldGroup>
          <Field>
            <FieldLabel htmlFor="timezone">Timezone</FieldLabel>
            <Input
              id="timezone"
              required
              value={preferences.timezone}
              onChange={(e) =>
                setPreferences({ ...preferences, timezone: e.target.value })
              }
            />
          </Field>
          <Field>
            <FieldLabel htmlFor="reminder">
              Reminder (minutes before event)
            </FieldLabel>
            <Input
              id="reminder"
              type="number"
              min={0}
              max={10080}
              value={preferences.reminder ?? ""}
              onChange={(e) =>
                setPreferences({
                  ...preferences,
                  reminder: e.target.value ? Number(e.target.value) : null,
                })
              }
            />
            <FieldDescription>Empty disables reminders.</FieldDescription>
          </Field>
          <Field orientation="horizontal">
            <Checkbox
              id="detailed-debug"
              checked={preferences.detailed_debug}
              onCheckedChange={(value) =>
                setPreferences({
                  ...preferences,
                  detailed_debug: value === true,
                })
              }
            />
            <FieldLabel htmlFor="detailed-debug">
              Retain intermediate images
            </FieldLabel>
          </Field>
          <Button type="submit" disabled={!!w.busy}>
            Save defaults
          </Button>
          <FieldDescription>
            App scans and full traces expire after 30 days. Research datasets
            have separate retention.
          </FieldDescription>
        </FieldGroup>
      </form>
      <FieldGroup>
        {(
          [
            {
              key: "detector_side",
              label: "Detector maximum side",
              min: 320,
              max: 2560,
              step: 32,
            },
            {
              key: "detector_threshold",
              label: "Detector threshold",
              min: 0.05,
              max: 0.95,
              step: 0.05,
            },
            {
              key: "box_threshold",
              label: "Box threshold",
              min: 0.05,
              max: 0.95,
              step: 0.05,
            },
          ] as const
        ).map(({ key, label, ...range }) => (
          <Field key={key}>
            <FieldLabel htmlFor={key}>{label}</FieldLabel>
            <Input
              id={key}
              type="number"
              {...range}
              value={w.config[key]}
              onChange={(e) =>
                w.setConfig({ ...w.config, [key]: Number(e.target.value) })
              }
            />
          </Field>
        ))}
        <Button
          variant="outline"
          onClick={() =>
            w.execute("Exporting configuration", () =>
              exportFile(
                JSON.stringify(w.config, null, 2),
                "pipeline-config.json",
              ),
            )
          }
        >
          Export pipeline configuration
        </Button>
        <JsonView
          value={w.runtime ?? { platform: "browser", inference: "unavailable" }}
        />
      </FieldGroup>
    </div>
  );
}
