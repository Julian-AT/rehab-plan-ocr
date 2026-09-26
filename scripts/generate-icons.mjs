// Deterministic platform packaging of the reviewed artwork using Tauri's CLI.
import {
  copyFileSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { syncIosIcons } from "./sync-ios-icons.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const temporary = mkdtempSync(join(tmpdir(), "reha-icons-"));
const cli = join(root, "node_modules/@tauri-apps/cli/tauri.js");
const icons = join(root, "src-tauri/icons");
try {
  const artwork = join(root, "assets/icon-artwork/ios.png");
  const macos = join(temporary, "macos.svg");
  writeFileSync(
    macos,
    readFileSync(
      join(root, "assets/icon-artwork/macos-template.svg"),
      "utf8",
    ).replace(
      "{{ARTWORK}}",
      `data:image/png;base64,${readFileSync(artwork).toString("base64")}`,
    ),
  );
  // Use temporary output directories so the CLI cannot accidentally write the
  // rounded desktop artwork into an existing generated iOS catalog.
  for (const platform of ["ios", "macos"]) {
    const output = join(temporary, platform);
    const input = platform === "ios" ? artwork : macos;
    execFileSync(
      process.execPath,
      [cli, "icon", input, "--output", output, "--ios-color", "#ffffff"],
      { cwd: root, stdio: "pipe" },
    );
    if (platform === "ios") {
      mkdirSync(join(icons, "ios"), { recursive: true });
      for (const file of readdirSync(join(output, "ios")).filter((name) =>
        name.endsWith(".png"),
      )) {
        copyFileSync(join(output, "ios", file), join(icons, "ios", file));
      }
    } else {
      for (const file of [
        "32x32.png",
        "64x64.png",
        "128x128.png",
        "128x128@2x.png",
        "icon.png",
        "icon.icns",
        "icon.ico",
      ]) {
        copyFileSync(join(output, file), join(icons, file));
      }
      execFileSync(
        process.execPath,
        [
          cli,
          "icon",
          input,
          "--output",
          join(output, "master"),
          "--png",
          "1024",
        ],
        { cwd: root, stdio: "pipe" },
      );
      copyFileSync(
        join(output, "master/1024x1024.png"),
        join(root, "assets/icon-artwork/macos.png"),
      );
    }
  }
  syncIosIcons();
  console.log("macOS icon and iOS asset catalog generated and synchronized.");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
