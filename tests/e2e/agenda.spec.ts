import { expect, test, type Page } from "@playwright/test";
import { emptyAgenda, type AgendaEvent } from "../../src/lib/agenda";
const id = "aabbccdd-1111-2222-3333-123456789012";
const secondID = "aabbccdd-1111-2222-3333-123456789013";
const now = Date.parse("2026-09-11T07:20:00Z");
const events: AgendaEvent[] = [
  {
    id,
    start: now / 1000 + 600,
    end: now / 1000 + 2400,
    title: "Physiotherapie",
    room: "Raum 204",
    timezone: "Europe/Vienna",
    status: "current",
  },
  {
    id: secondID,
    start: now / 1000 + 3600,
    end: now / 1000 + 5400,
    title: "Bewegung & Balance",
    room: "Turnsaal",
    timezone: "Europe/Vienna",
    status: "current",
  },
  {
    id: "aabbccdd-1111-2222-3333-123456789014",
    start: now / 1000 + 7200,
    end: now / 1000 + 9000,
    title: "Entspannung",
    room: "",
    timezone: "Europe/Vienna",
    status: "current",
  },
];
async function native(
  page: Page,
  initial: AgendaEvent[] = events,
  launch: string | null = null,
) {
  await page.clock.install({ time: new Date(now) });
  await page.addInitScript(
    ({ snapshot, initial, launch }) => {
      const callbacks = new Map<number, (payload: unknown) => void>();
      let callbackID = 0;
      const state = {
        response: {
          ...snapshot,
          snapshot: {
            ...snapshot.snapshot,
            updatedAt: Date.now() / 1000,
            access: initial.length ? "available" : "empty",
            events: initial,
          },
        },
        preferences: {
          timezone: "Europe/Vienna",
          reminder: 10,
          app_reminder_minutes: 10,
          appearance: "system",
        },
        pending: launch,
        commands: [] as string[],
      };
      Object.assign(window, {
        isTauri: true,
        __agendaTest: state,
        __TAURI_EVENT_PLUGIN_INTERNALS__: { unregisterListener() {} },
        __TAURI_INTERNALS__: {
          transformCallback: (callback: (payload: unknown) => void) => {
            callbacks.set(++callbackID, callback);
            return callbackID;
          },
          invoke: async (
            name: string,
            args?: {
              value?: typeof state.preferences;
              acknowledge?: string;
              event?: string;
              handler?: number;
            },
          ) => {
            state.commands.push(name);
            // Fake the native projection returned by AppleServices. This fixture
            // exercises rendering/transport; Swift policy tests own date rules.
            const dayStart = new Date();
            dayStart.setHours(0, 0, 0, 0);
            const dayEnd = new Date(dayStart);
            dayEnd.setDate(dayEnd.getDate() + 1);
            const presentation = {
              next: state.response.snapshot.events.find(
                (event) => event.end > Date.now() / 1000,
              ),
              today: state.response.snapshot.events.filter(
                (event) =>
                  event.start < +dayEnd / 1000 && event.end > +dayStart / 1000,
              ),
              stale:
                Date.now() / 1000 - state.response.snapshot.updatedAt > 86400,
            };
            if (name === "agenda_presentation") return presentation;
            if (name === "settings") {
              if (args?.value) state.preferences = args.value;
              return state.preferences;
            }
            if (name === "history")
              return { scans: [], imports: [], pending: 0 };
            if (name === "engine_status")
              return {
                platform: "ios",
                portable_packaged: true,
                runtime: "test",
              };
            if (name === "agenda" || name === "reminder_status")
              return { ...state.response, presentation };
            if (name === "pending_event_open") {
              if (args?.acknowledge === state.pending) state.pending = null;
              return { id: state.pending };
            }
            if (name === "plugin:deep-link|get_current")
              return launch ? [`reha-calendar://event/${launch}`] : null;
            if (name === "enable_reminders") {
              state.response.reminders.authorization = "authorized";
              state.response.reminders.enabled = true;
              state.response.reminders.scheduled = initial.length;
              return state.response;
            }
            if (name.startsWith("plugin:event|")) return 1;
            if (name === "maintenance" || name === "test_reminder") return null;
            throw new Error(`Unexpected command: ${name}`);
          },
        },
      });
    },
    { snapshot: emptyAgenda, initial, launch },
  );
  await page.goto("/");
}
test("today renders saved appointments, pill navigation and import actions", async ({
  page,
}, info) => {
  await native(page);
  await expect(page.getByRole("heading", { name: "Termine." })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "09:30 Physiotherapie öffnen" }),
  ).toBeVisible();
  await expect(page.getByText("In 10 Minuten", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Hauptnavigation" }),
  ).toBeVisible();
  await page.screenshot({
    path: `artifacts/private/030-today-${info.project.name}.png`,
    fullPage: true,
  });
  await page.getByRole("button", { name: "Importieren", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Foto aufnehmen", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Foto importieren", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: `artifacts/private/030-import-${info.project.name}.png`,
  });
});
test("running appointment changes to the next one at its end", async ({
  page,
}) => {
  await native(page);
  await page.clock.fastForward(10 * 60 * 1000);
  await expect(
    page.locator(".next-appointment").getByText("Jetzt", { exact: true }),
  ).toBeVisible();
  await page.clock.fastForward(30 * 60 * 1000);
  await expect(
    page
      .locator(".next-appointment")
      .getByRole("heading", { name: "Bewegung & Balance" }),
  ).toBeVisible();
});
test("notification opens current calendar values on cold and warm launch", async ({
  page,
}) => {
  await native(page, events, id);
  await expect(
    page.getByRole("dialog").getByRole("heading", { name: "Physiotherapie" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Schließen", exact: true }).click();
  await page.evaluate((secondID) => {
    const state = (
      window as unknown as {
        __agendaTest: {
          pending: string;
          response: { snapshot: { events: AgendaEvent[] } };
        };
      }
    ).__agendaTest;
    state.pending = secondID;
    state.response.snapshot.events[1].room = "Raum 303";
  }, secondID);
  await page.clock.fastForward(2000);
  await expect(
    page.getByRole("dialog").getByText("Raum 303", { exact: true }),
  ).toBeVisible();
});
test("deleted links and unavailable calendar data give different states", async ({
  page,
}) => {
  await native(page, [], id);
  await expect(
    page.getByText("Dieser Termin ist nicht mehr vorhanden.", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Zur Tagesübersicht", exact: true })
    .click();
  await page.evaluate((id) => {
    const state = (
      window as unknown as {
        __agendaTest: {
          pending: string;
          response: { snapshot: { access: string } };
        };
      }
    ).__agendaTest;
    state.response.snapshot.access = "unavailable";
    state.pending = id;
  }, id);
  await page.clock.fastForward(2000);
  await expect(
    page.getByText(
      "Kalender gerade nicht zugänglich. Bitte Zugriff prüfen und erneut abgleichen.",
      { exact: true },
    ),
  ).toBeVisible();
});
test("reminders activate explicitly and preferences do not rewrite reviewed appointments", async ({
  page,
}, info) => {
  await native(page);
  await page
    .getByRole("button", { name: "Erinnerungen", exact: true })
    .click();
  await expect(page.getByLabel("Vorlauf")).toHaveText("10 Minuten vorher");
  await page
    .getByRole("button", { name: "Erinnerungen aktivieren", exact: true })
    .click();
  await expect(
    page.getByText("3 App-Erinnerungen eingeplant.", { exact: false }),
  ).toBeVisible();
  await page.getByLabel("Mit Ton", { exact: true }).uncheck();
  await page.screenshot({
    path: `artifacts/private/030-settings-${info.project.name}.png`,
  });
  await page
    .getByRole("button", { name: "Einstellungen speichern", exact: true })
    .click();
  const commands = await page.evaluate(
    () =>
      (window as unknown as { __agendaTest: { commands: string[] } })
        .__agendaTest.commands,
  );
  expect(commands).not.toContain("save_review");
  expect(commands).not.toContain("approve_calendar");
});
test("long names, dark mode and enlarged text remain readable on a small screen", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 320, height: 740 });
  await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await native(page, [
    {
      ...events[0],
      title:
        "Physiotherapeutische Bewegungstherapie und Gleichgewichtstraining im Bewegungsbad",
      room: "",
    },
  ]);
  await page.evaluate(() => {
    document.documentElement.style.fontSize = "22px";
  });
  await expect(page.locator(".next-appointment")).toContainText(
    "Raum nicht angegeben",
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  for (const button of await page
    .locator(".floating-navigation button")
    .all()) {
    const box = await button.boundingBox();
    expect(box!.width).toBeGreaterThanOrEqual(44);
    expect(box!.height).toBeGreaterThanOrEqual(44);
  }
  await page.screenshot({
    path: `artifacts/private/030-large-dark-${info.project.name}.png`,
    fullPage: true,
  });
});
