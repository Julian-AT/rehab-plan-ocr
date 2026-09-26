import { invoke, isTauri } from "@tauri-apps/api/core";

export { isTauri };

export function command<T>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  if (!isTauri())
    return Promise.reject(
      new Error("Native runtime required. Start with npm run tauri dev."),
    );
  return invoke<T>(name, args);
}

export function encodeImage(file: Blob): Promise<string> {
  if (file.size > 40 * 1024 * 1024)
    return Promise.reject(new Error("Image exceeds 40 MB."));
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("Image could not be read."));
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.readAsDataURL(file);
  });
}

export async function exportFile(
  content: string,
  filename: string,
  type = "application/json",
) {
  if (isTauri() && /iPhone|iPad/.test(navigator.userAgent)) {
    await command("share_export", { content, filename });
    return;
  }
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
