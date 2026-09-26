import { expect, test, type Page } from "@playwright/test";
async function sample(page: Page) {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Einstellungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page.getByRole("button", { name: "Load fixture", exact: true }).click();
  await expect(page.getByLabel("Title row 4", { exact: true })).toHaveValue(
    "Entspannung",
  );
  await page
    .getByRole("button", { name: "Zurück zu Terminen", exact: true })
    .click();
}
test("cold launch is simple, German, accessible and does not load development controls", async ({
  page,
}) => {
  const requests: string[] = [];
  page.on("request", (r) => requests.push(r.url()));
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Foto aufnehmen", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Importieren", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("Reha Calendar Lab", { exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Load fixture", exact: true }),
  ).toHaveCount(0);
  await expect(page.getByRole("tab")).toHaveCount(0);
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  for (const button of await page.getByRole("button").all()) {
    const rect = await button.boundingBox();
    expect(rect!.height).toBeGreaterThanOrEqual(44);
    expect(rect!.width).toBeGreaterThanOrEqual(44);
  }
  expect(
    requests.every((r) => r.startsWith("http://127.0.0.1:1420")),
  ).toBeTruthy();
});
test("review shares edits with workbench, protects unsaved changes and returns to simple on reload", async ({
  page,
}) => {
  await sample(page);
  await expect(page.getByText("Dauer fehlt", { exact: true })).toHaveCount(1);
  await page
    .getByRole("button", {
      name: "11:15 Übungen im Wasser bearbeiten",
      exact: true,
    })
    .click();
  await page.getByLabel("Dauer (Minuten)", { exact: true }).fill("20");
  await page.getByRole("button", { name: "Schließen", exact: true }).click();
  await expect(
    page
      .getByRole("alert")
      .filter({ hasText: "Ungespeicherte Änderungen verwerfen?" }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Weiter bearbeiten", exact: true })
    .click();
  await expect(page.getByLabel("Dauer (Minuten)", { exact: true })).toHaveValue(
    "20",
  );
  await page
    .getByRole("button", { name: "Termin bestätigen", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByText("Dauer fehlt", { exact: true })).toHaveCount(0);
  await page
    .getByRole("button", { name: "Einstellungen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Entwickleransicht öffnen", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Details row 6", exact: true })
    .click();
  await expect(
    page.getByLabel("Duration (minutes)", { exact: true }),
  ).toHaveValue("20");
  await page.reload();
  await expect(
    page.getByRole("button", { name: "Foto aufnehmen", exact: true }),
  ).toBeVisible();
});
test("sheets adapt to mobile, dark mode, keyboard navigation and large text", async ({
  page,
}, info) => {
  await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await sample(page);
  await expect(page.locator("html")).toHaveClass("dark");
  await page.evaluate(() => {
    document.documentElement.style.fontSize = "22px";
  });
  await page
    .getByRole("button", {
      name: "08:15 Bewegungstherapie Bitte feste Schuhe mitbringen bearbeiten",
      exact: true,
    })
    .click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toHaveAttribute(
    "data-side",
    info.project.name === "mobile-webkit" ? "bottom" : "right",
  );
  await expect(
    page.getByRole("button", { name: "Termin bestätigen", exact: true }),
  ).toBeInViewport();
  await page.getByLabel("Behandlung", { exact: true }).focus();
  await expect(page.getByLabel("Behandlung", { exact: true })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBeTruthy();
  await page.screenshot({
    path: `artifacts/private/simple-${info.project.name}.png`,
    fullPage: true,
  });
});
test("calendar selection keeps missing appointments pending and source remains accessible", async ({
  page,
}) => {
  await sample(page);
  await page.getByRole("button", { name: "Foto ansehen", exact: true }).click();
  await expect(
    page.getByRole("img", { name: "Originalfoto des Terminplans" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Schließen", exact: true }).click();
  await page
    .getByRole("button", { name: "In Kalender übernehmen", exact: true })
    .click();
  await expect(
    page.getByText("7 ausgewählt · 1 mit offenen Angaben", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("checkbox")).toHaveCount(7);
  await page.getByRole("button", { name: "Schließen", exact: true }).click();
  await expect(page.getByText("Dauer fehlt", { exact: true })).toHaveCount(1);
});
