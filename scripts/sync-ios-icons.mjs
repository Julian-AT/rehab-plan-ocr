// Xcode projects are generated/ignored; the canonical icon catalog stays tracked.
import { existsSync, mkdirSync, readFileSync, copyFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const source = join(root, "src-tauri/icons/ios");
const project = process.env.TAURI_IOS_PROJECT_PATH
  ? resolve(process.env.TAURI_IOS_PROJECT_PATH)
  : join(root, "src-tauri/gen/apple");

export function syncIosIcons() {
  if (!existsSync(project)) return;
  const destination = join(project, "Assets.xcassets/AppIcon.appiconset");
  const catalog = JSON.parse(
    readFileSync(join(source, "Contents.json"), "utf8"),
  );
  const files = [
    "Contents.json",
    ...new Set(catalog.images.map((image) => image.filename)),
  ];
  for (const file of files) {
    if (!file || basename(file) !== file)
      throw new Error("Invalid icon catalog filename");
    if (!existsSync(join(source, file)))
      throw new Error(`Missing iOS icon: ${file}. Run npm run icons.`);
  }
  mkdirSync(destination, { recursive: true });
  for (const file of files) {
    const from = join(source, file);
    const to = join(destination, file);
    if (!existsSync(to) || !readFileSync(from).equals(readFileSync(to)))
      copyFileSync(from, to);
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  syncIosIcons();
