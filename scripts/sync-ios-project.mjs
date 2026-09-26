// Reapply the tracked native extensions after `tauri ios init`. No signing
// identity/profile is changed here; the generated app target remains authoritative.
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import YAML from "yaml";
import { syncIosIcons } from "./sync-ios-icons.mjs";
const root = fileURLToPath(new URL("../", import.meta.url));
const project = process.env.TAURI_IOS_PROJECT_PATH
  ? resolve(process.env.TAURI_IOS_PROJECT_PATH)
  : join(root, "src-tauri/gen/apple");
const path = join(project, "project.yml");
if (existsSync(path)) {
  const original = readFileSync(path, "utf8");
  const spec = YAML.parse(original);
  const extensions = YAML.parse(
    readFileSync(join(root, "ios/extensions.yml"), "utf8"),
  );
  const config = JSON.parse(
    readFileSync(join(root, "src-tauri/tauri.conf.json"), "utf8"),
  );
  const app = spec.targets["reha-calendar_iOS"];
  if (!app || config.identifier !== "at.rehakalender.personal")
    throw new Error("Unexpected app target/identifier");
  const team =
    app.settings?.base?.DEVELOPMENT_TEAM ??
    spec.settingGroups?.app?.base?.DEVELOPMENT_TEAM;
  const group = {
    "com.apple.security.application-groups": ["group.at.rehakalender.personal"],
  };
  app.sources = app.sources.filter((source) => source.path !== "Externals");
  app.entitlements.properties = { ...app.entitlements.properties, ...group };
  app.info.properties = {
    ...app.info.properties,
    CFBundleShortVersionString: config.version,
    CFBundleVersion: config.version,
    CFBundleDisplayName: "Laßnitzhöhe",
    UIBackgroundModes: ["fetch"],
    BGTaskSchedulerPermittedIdentifiers: [
      "at.rehakalender.personal.agenda-refresh",
    ],
    CFBundleURLTypes: [
      {
        CFBundleURLName: config.identifier,
        CFBundleURLSchemes: ["reha-calendar"],
      },
    ],
    NSCameraUsageDescription:
      "Terminpläne fotografieren und auf diesem Gerät erkennen.",
    NSPhotoLibraryUsageDescription:
      "Terminpläne aus Fotos importieren und auf diesem Gerät erkennen.",
    NSCalendarsFullAccessUsageDescription:
      "Bestätigte Termine speichern und mit vorhandenen Kalendereinträgen abgleichen.",
  };
  for (const [name, extension] of Object.entries(extensions.targets)) {
    extension.settings.base.DEVELOPMENT_TEAM = team;
    extension.info.properties.CFBundleShortVersionString = config.version;
    extension.info.properties.CFBundleVersion = config.version;
    spec.targets[name] = extension;
    app.dependencies = (app.dependencies ?? []).filter(
      (entry) => entry.target !== name,
    );
    app.dependencies.push({ target: name, embed: true, codeSign: true });
  }
  const main = join(project, "Sources/reha-calendar/main.mm");
  const source = readFileSync(main, "utf8");
  if (!source.includes("reha_agenda_start")) {
    writeFileSync(
      main,
      source
        .replace(
          "int main(",
          'extern "C" void reha_agenda_start(void);\n\nint main(',
        )
        .replace(
          "\tffi::start_app();",
          "\treha_agenda_start();\n\tffi::start_app();",
        ),
    );
  }
  const updated = YAML.stringify(spec, { lineWidth: 0 });
  if (updated !== original || process.argv.includes("--force")) {
    writeFileSync(path, updated);
    execFileSync(
      "xcodegen",
      ["generate", "--spec", path, "--project", project],
      { stdio: "inherit" },
    );
  }
  syncIosIcons();
}
