import { expect, test } from "@playwright/test";

test("debug table can resolve genuinely blank printed cells from the photo review", async ({
  page,
}) => {
  await page.route("**/sample-run.json", async (route) => {
    const response = await route.fetch();
    const run = await response.json();
    const a = run.appointments[0];
    a.fields = Object.fromEntries(
      ["location", "therapist"].map((field) => [
        field,
        {
          state: "unreviewed",
          polygon: a.row_polygon ?? [],
          frame: "page",
          reasons: [
            "Leer erkannt: am Foto bestätigen, ob nichts gedruckt ist.",
          ],
          confirmed_at: null,
          confirmed_value: null,
        },
      ]),
    );
    a.location = "";
    a.therapist = "";
    await route.fulfill({ response, json: run });
  });
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("button", { name: "Load fixture", exact: true }).click();
  await page
    .getByRole("button", { name: "Am Foto prüfen, Zeile 1", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Termin bearbeiten" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Termin bestätigen", exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Raum im Foto", exact: true }).click();
  await page
    .getByRole("button", { name: "Nicht gedruckt", exact: true })
    .nth(0)
    .click();
  await page
    .getByRole("button", { name: "Nicht gedruckt", exact: true })
    .nth(1)
    .click();
  await page
    .getByRole("button", { name: "Termin bestätigen", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Termin bearbeiten" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("list", { name: "Validation errors" }).getByText(/^Row 1:/),
  ).toHaveCount(0);
  await expect(
    page.getByText("Row 6: Missing end time or duration", { exact: true }),
  ).toBeVisible();
});

test("review preserves repeated items, provenance, and explicit approval", async ({
  page,
}, info) => {
  const errors: string[] = [];
  const requests: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (request) => requests.push(request.url()));
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Laßnitzhöhe · Diagnose" }),
  ).toBeVisible();
  await expect(page.getByLabel("Input images")).toBeDisabled();
  await page.getByRole("button", { name: "Load fixture" }).click();
  await expect(page.getByLabel("Title row 4", { exact: true })).toHaveValue(
    "Entspannung",
  );
  await expect(page.getByLabel("Title row 5", { exact: true })).toHaveValue(
    "Entspannung",
  );
  await expect(page.getByLabel("End row 6", { exact: true })).toHaveValue("");
  await expect(
    page.getByText("Row 6: Missing end time or duration", { exact: true }),
  ).toBeVisible();
  await page.getByLabel("Title row 2", { exact: true }).focus();
  await expect(
    page.locator('polygon[data-selected="true"]').first(),
  ).toBeVisible();
  await page.getByLabel("End row 6", { exact: true }).fill("11:45");
  await expect(
    page.getByRole("list", { name: "Validation errors" }),
  ).toHaveCount(0);
  await page
    .getByRole("checkbox", {
      name: "Review confirmed, including unassigned observations",
    })
    .check();
  await page
    .getByLabel("Therapeut row 2", { exact: true })
    .fill("Alex Beispiel MSc");
  await expect(
    page.getByRole("checkbox", {
      name: "Review confirmed, including unassigned observations",
    }),
  ).not.toBeChecked();
  await page.screenshot({
    path: `artifacts/private/${info.project.name}-workbench.png`,
    fullPage: true,
  });
  await page.getByRole("tab", { name: "Calendar", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Export .ics" }),
  ).toBeDisabled();
  expect(
    requests.every(
      (url) =>
        url.startsWith(new URL(page.url()).origin) || url.startsWith("data:"),
    ),
  ).toBeTruthy();
  expect(errors).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBeTruthy();
});

test("trace exposes actual observations and unavailable stages", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("button", { name: "Load fixture" }).click();
  await page.getByRole("tab", { name: "Trace", exact: true }).click();
  await expect(page.getByText("Engine scores are uncalibrated.")).toBeVisible();
  await page.getByRole("tab", { name: "Stages", exact: true }).click();
  await page
    .getByRole("button", { name: "selective_reread", exact: true })
    .click();
  await expect(
    page.getByText(
      "No retry adapter configured; difficult fields require review.",
      { exact: true },
    ),
  ).toBeVisible();
  await page.getByRole("tab", { name: "Mapping", exact: true }).click();
  await expect(
    page.getByRole("columnheader", { name: "Observations", exact: true }),
  ).toBeVisible();
});

test("offline edits and selection retain appointment multiplicity", async ({
  page,
  context,
}) => {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("button", { name: "Load fixture" }).click();
  await expect(
    page.getByText("8 selected / 8 extracted", { exact: true }),
  ).toBeVisible();
  await context.setOffline(true);
  await page
    .getByRole("checkbox", { name: "Select all appointments", exact: true })
    .uncheck();
  await expect(
    page.getByText("0 selected / 8 extracted", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("checkbox", { name: "Include row 4", exact: true })
    .check();
  await expect(
    page.getByText("1 selected / 8 extracted", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Add row", exact: true }).click();
  await expect(page.getByLabel("Title row 9", { exact: true })).toBeVisible();
  await context.setOffline(false);
});

test("annotation corrections invalidate verification", async ({ page }) => {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("button", { name: "Load fixture" }).click();
  await page.getByRole("tab", { name: "Dataset", exact: true }).click();
  await page
    .getByRole("tab", { name: "Annotations & evaluation", exact: true })
    .click();
  await page.getByRole("button", { name: "Draft from active run" }).click();
  await page
    .getByRole("checkbox", {
      name: "All reference items verified against source",
    })
    .check();
  await page.getByLabel("Therapeut row 2", { exact: true }).fill("Kim Muster");
  await expect(
    page.getByRole("checkbox", {
      name: "All reference items verified against source",
    }),
  ).not.toBeChecked();
  await expect(
    page.getByRole("button", { name: "Evaluate", exact: true }),
  ).toBeDisabled();
});
