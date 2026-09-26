import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";

test("failed retained capture requires explicit source deletion and never calls calendar writes", async ({
  page,
}) => {
  await page.addInitScript(() => {
    let deleted = false;
    const calls: string[] = [];
    Object.assign(window, {
      isTauri: true,
      __testCalls: calls,
      __TAURI_EVENT_PLUGIN_INTERNALS__: { unregisterListener() {} },
      __TAURI_INTERNALS__: {
        transformCallback: () => 1,
        invoke: async (name: string) => {
          calls.push(name);
          if (name === "settings") return { timezone: "Europe/Vienna" };
          if (name === "history")
            return {
              scans: [],
              imports: [],
              pending: 0,
              intakes: deleted
                ? []
                : [
                    {
                      id: "retained-failure",
                      filename: "broken.jpg",
                      imported_at: 1,
                      status: "failed",
                      error: "Foto konnte nicht gelesen werden",
                    },
                  ],
            };
          if (name === "engine_status")
            return {
              platform: "macos",
              portable_packaged: true,
              runtime: "test bridge",
            };
          if (name.startsWith("plugin:event|")) return 1;
          if (name === "maintenance") return null;
          if (name === "delete_scan") {
            deleted = true;
            return null;
          }
          throw new Error(`Unexpected test command: ${name}`);
        },
      },
    });
  });
  await page.goto("/");
  await page.getByRole("button", { name: "Archiv", exact: true }).click();
  await expect(
    page.getByText("Foto konnte nicht gelesen werden"),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Aufnahme löschen", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toContainText(
    "Gespeicherte Kalendertermine bleiben erhalten.",
  );
  expect(
    await page.evaluate(() =>
      (window as unknown as { __testCalls: string[] }).__testCalls.filter(
        (v) => v === "delete_scan",
      ),
    ),
  ).toHaveLength(0);
  await page
    .getByRole("button", { name: "Aufnahme endgültig löschen" })
    .click();
  await expect(page.getByText("Foto konnte nicht gelesen werden")).toHaveCount(
    0,
  );
  const writes = await page.evaluate(() =>
    (window as unknown as { __testCalls: string[] }).__testCalls.filter(
      (v) =>
        v === "delete_scan" || v === "approve_calendar" || v === "prepare_undo",
    ),
  );
  expect(writes).toEqual(["delete_scan"]);
});

test("HEIC file without MIME type reaches native import unchanged and opens review", async ({
  page,
}) => {
  const fixture = JSON.parse(readFileSync("tests/fixtures/sample-run.json", "utf8"));
  // This checks file selection, byte transfer and review. Actual HEIC decoding,
  // orientation and original retention are covered by the native Rust tests.
  await page.addInitScript((run) => {
    const imports: { filename: string; base64: string }[] = [];
    Object.assign(window, {
      isTauri: true,
      __testImports: imports,
      __TAURI_EVENT_PLUGIN_INTERNALS__: { unregisterListener() {} },
      __TAURI_INTERNALS__: {
        transformCallback: () => 1,
        invoke: async (
          name: string,
          args: { request?: { filename: string; base64: string } },
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
          if (name === "import_image" && args.request) {
            imports.push(args.request);
            return {
              run: {
                ...run,
                document: { ...run.document, filename: args.request.filename },
              },
              duplicate: false,
            };
          }
          throw new Error(`Unexpected test command: ${name}`);
        },
      },
    });
  }, fixture);
  await page.goto("/");
  const input = page.getByLabel("Plan importieren", { exact: true });
  await expect(input).toHaveAttribute("accept", /\.heic,\.heif/);
  const buffer = readFileSync("tests/fixtures/heic/orientation-6.heic");
  await input.setInputFiles({ name: "Terminplan.HEIC", mimeType: "", buffer });
  await expect(
    page.getByRole("button", { name: "Foto ansehen", exact: true }),
  ).toBeVisible();
  const imports = await page.evaluate(
    () =>
      (
        window as unknown as {
          __testImports: { filename: string; base64: string }[];
        }
      ).__testImports,
  );
  expect(imports).toHaveLength(1);
  expect(imports[0].filename).toBe("Terminplan.HEIC");
  expect(imports[0].base64).toBe(buffer.toString("base64"));
});
