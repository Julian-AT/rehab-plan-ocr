import { expect, test } from "@playwright/test";

test("reference review retains progress and revokes approval after a field correction", async ({
  page,
}) => {
  // An invented reference and an in-memory native bridge exercise the editor;
  // native hash, source and grouping validation are covered separately.
  await page.addInitScript(() => {
    const polygon = [
      { x: 5, y: 5 },
      { x: 95, y: 5 },
      { x: 95, y: 30 },
      { x: 5, y: 30 },
    ];
    const values = {
      date: "2030-01-01",
      start: "08:00",
      end: "08:30",
      title: "Beispieltraining",
      location: "Raum 107",
      therapist: "Alex Beispiel",
      notes: "",
    };
    let reference = {
      schema_version: 2,
      day_id: "example",
      split: "development",
      document_hashes: ["a".repeat(64)],
      verified: false,
      reviewed_at: null,
      coverage_confirmed: false,
      uncertainty_notes: [],
      sources: [
        {
          source_hash: "a".repeat(64),
          original_hash: "a".repeat(64),
          logical_page: "example",
          capture_series: "example",
          treatment_days: ["2030-01-01"],
          width: 100,
          height: 100,
          table_polygon: polygon,
          relationships_confirmed: true,
        },
      ],
      appointments: [
        {
          ...values,
          id: "example-row",
          row_polygon: polygon,
          fields: Object.fromEntries(
            Object.entries(values).map(([field, value]) => [
              field,
              {
                state: value ? "legible" : "not_printed",
                polygon,
                frame: "original",
                reasons: [],
                confirmed_at: null,
                confirmed_value: null,
              },
            ]),
          ),
        },
      ],
      lines: [],
    };
    Object.assign(window, {
      isTauri: true,
      __TAURI_EVENT_PLUGIN_INTERNALS__: { unregisterListener() {} },
      __TAURI_INTERNALS__: {
        transformCallback: () => 1,
        invoke: async (
          name: string,
          args: { annotation?: typeof reference },
        ) => {
          if (name === "settings") return { timezone: "Europe/Vienna" };
          if (name === "history") return { scans: [], imports: [], pending: 0 };
          if (name === "engine_status")
            return {
              platform: "macos",
              portable_packaged: true,
              runtime: "test bridge",
            };
          if (name.startsWith("plugin:event|")) return 1;
          if (name === "maintenance") return null;
          if (name === "dataset")
            return {
              split_frozen: true,
              entries: [
                {
                  filename: "invented.png",
                  sha256: "a".repeat(64),
                  verified: reference.verified,
                  reviewed_rows: Object.values(
                    reference.appointments[0].fields,
                  ).every((f) => f.confirmed_at !== null)
                    ? 1
                    : 0,
                  reference_rows: 1,
                },
              ],
            };
          if (name === "dataset_image")
            return {
              base64:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aBt8AAAAASUVORK5CYII=",
            };
          if (name === "provisional_reference")
            return structuredClone(reference);
          if (name === "save_annotation" && args.annotation) {
            reference = structuredClone(args.annotation);
            return null;
          }
          throw new Error(`Unexpected test command: ${name}`);
        },
      },
    });
  });
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("tab", { name: "Dataset", exact: true }).click();
  await page
    .getByRole("tab", { name: "Annotations & evaluation", exact: true })
    .click();
  const editor = page.getByRole("region", {
    name: "Referenzen mit Originalfotos prüfen",
  });
  await editor
    .getByRole("button", { name: "20 Originale / Inventar öffnen" })
    .click();
  await editor
    .getByRole("combobox", { name: "Originalfoto", exact: true })
    .selectOption("a".repeat(64));
  await expect(
    editor.getByRole("img", {
      name: "Originalfoto mit markierter Terminzeile",
    }),
  ).toBeVisible();
  const approve = editor.getByRole("button", {
    name: "Referenz ausdrücklich für Training und Bewertung freigeben",
  });
  await expect(approve).toBeDisabled();
  await editor
    .getByRole("button", { name: "Diese Zeile am Foto bestätigt" })
    .click();
  await editor
    .getByRole("checkbox", {
      name: "Alle gedruckten Termine, Datumsabschnitte und Hinweise erfasst",
    })
    .check();
  await editor
    .getByRole("button", { name: "Prüffortschritt speichern" })
    .click();
  await expect(editor.getByRole("status")).toContainText(
    "1 / 1 Zeilen bestätigt · Gespeichert",
  );
  await expect(editor.locator("option:checked").first()).toContainText(
    "1/1 Zeilen geprüft",
  );
  await approve.click();
  await expect(editor.getByRole("status")).toContainText("· Freigegeben");
  await editor.getByLabel("Raum", { exact: true }).fill("Raum 108");
  await expect(editor.getByRole("status")).toContainText(
    "0 / 1 Zeilen bestätigt",
  );
  await expect(editor.getByRole("status")).toContainText(
    "Nicht für Training freigegeben",
  );
  await expect(approve).toBeDisabled();
  await editor
    .getByRole("button", { name: "Prüffortschritt speichern" })
    .click();
  await expect(editor.locator("option:checked").first()).toContainText(
    "0/1 Zeilen geprüft",
  );
  expect(errors).toEqual([]);
});
