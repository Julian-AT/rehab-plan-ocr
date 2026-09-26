"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { command, encodeImage, isTauri } from "@/lib/native";
import {
  defaultConfig,
  defaultPreferences,
  type Config,
  type History,
  type Preferences,
  type Run,
} from "@/lib/contracts";
import { useNative } from "@/hooks/use-native";

const emptyHistory: History = { scans: [], imports: [], pending: 0 };
type Runtime = {
  platform: string;
  portable_packaged: boolean;
  runtime: string;
};
export type ImageInput = { base64: string; filename: string };

export function useWorkbench() {
  const native = useNative();
  const [run, setRun] = useState<Run | null>(null);
  const [config, setConfig] = useState(defaultConfig);
  const [preferences, setPreferences] = useState(defaultPreferences);
  const [history, setHistory] = useState(emptyHistory);
  const [runtime, setRuntime] = useState<Runtime | null>(null);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [view, setView] = useState("run");
  const active = useRef<AbortController | null>(null);
  const saves = useRef<Promise<unknown>>(Promise.resolve());
  const saveError = useRef<unknown>(null);
  const report = useCallback(
    (error: unknown) =>
      setError(error instanceof Error ? error.message : String(error)),
    [],
  );

  const refresh = useCallback(async () => {
    if (isTauri()) setHistory(await command<History>("history"));
  }, []);

  const flush = useCallback(async () => {
    await saves.current;
    if (saveError.current) throw saveError.current;
  }, []);

  const execute = useCallback(
    async <T>(
      label: string,
      task: (signal: AbortSignal) => Promise<T>,
    ): Promise<T | undefined> => {
      if (active.current) return;
      const controller = new AbortController();
      active.current = controller;
      setBusy(label);
      setError("");
      setNotice("");
      try {
        return await task(controller.signal);
      } catch (error) {
        report(error);
      } finally {
        active.current = null;
        setBusy("");
      }
    },
    [report],
  );

  const cancel = useCallback(async () => {
    active.current?.abort();
    if (isTauri()) await command("cancel_processing").catch(report);
  }, [report]);

  useEffect(() => {
    if (!native) return;
    let disposed = false;
    void Promise.all([
      command<Preferences>("settings"),
      command<History>("history"),
      command<Runtime>("engine_status"),
    ])
      .then(([preferences, history, runtime]) => {
        if (disposed) return;
        setPreferences(preferences);
        setHistory(history);
        setRuntime(runtime);
        setConfig((value) => ({
          ...value,
          timezone: preferences.timezone,
          detailed_debug: preferences.detailed_debug,
        }));
      })
      .catch(report);
    const lifecycle = () => {
      if (document.visibilityState === "hidden") void cancel();
      else void command("maintenance").then(refresh).catch(report);
    };
    document.addEventListener("visibilitychange", lifecycle);
    return () => {
      disposed = true;
      document.removeEventListener("visibilitychange", lifecycle);
    };
  }, [native, report, cancel, refresh]);

  // Serialize snapshots in edit order. Explicit export/approval waits for this queue.
  function updateRun(patch: Partial<Run>, invalidate = true) {
    if (!run) return;
    const next = {
      ...run,
      ...patch,
      review_confirmed: invalidate
        ? false
        : (patch.review_confirmed ?? run.review_confirmed),
    };
    setRun(next);
    if (native) {
      saves.current = saves.current
        .catch(() => {})
        .then(async () => {
          try {
            await command("save_review", {
              id: next.document.id,
              appointments: next.appointments,
              complete: next.complete_page_confirmed,
              reviewed: next.review_confirmed,
            });
            saveError.current = null;
          } catch (error) {
            saveError.current = error;
            report(error);
          }
        });
    }
  }

  async function processImage(
    image: ImageInput,
    options = config,
    force = false,
  ) {
    const result = await command<{ run: Run; duplicate: boolean }>(
      "import_image",
      {
        request: { id: crypto.randomUUID(), ...image, config: options, force },
      },
    );
    return result;
  }

  function acceptRun(run: Run) {
    setRun(run);
    setConfig(run.config);
    setView("run");
  }

  async function importFiles(files: File[]) {
    await execute("Running OCR", async (signal) => {
      await flush();
      for (const [index, file] of files.entries()) {
        if (signal.aborted) break;
        setBusy(`Running OCR · ${index + 1}/${files.length}`);
        const result = await processImage({
          base64: await encodeImage(file),
          filename: file.name,
        });
        acceptRun(result.run);
        if (result.duplicate)
          setNotice(
            "Cached scan loaded. Use Reprocess to run extraction again.",
          );
      }
      await refresh();
    });
  }

  async function sample() {
    await execute("Loading synthetic fixture", async () => {
      await flush();
      if (native) {
        const response = await fetch("/synthetic-day.png");
        if (!response.ok) throw new Error("Synthetic image unavailable.");
        acceptRun(
          (
            await processImage({
              base64: await encodeImage(await response.blob()),
              filename: "synthetic-day.png",
            })
          ).run,
        );
        await refresh();
      } else {
        const response = await fetch("/sample-run.json");
        if (!response.ok) throw new Error("Recorded fixture unavailable.");
        acceptRun(await response.json());
      }
      setNotice(
        native
          ? "Synthetic fixture processed locally."
          : "Recorded synthetic run. Browser edits are temporary; OCR and calendar commands require Tauri.",
      );
    });
  }

  async function openScan(id: string) {
    await execute("Loading scan", async () => {
      await flush();
      acceptRun(await command<Run>("load_scan", { id }));
    });
  }

  async function reprocess(options: Config) {
    if (!run) return;
    await execute("Reprocessing", async () => {
      await flush();
      const source = await command<string>("source_bytes", {
        id: run.document.id,
      });
      acceptRun(
        (
          await processImage(
            { base64: source, filename: run.document.filename },
            options,
            true,
          )
        ).run,
      );
      await refresh();
    });
  }

  async function capture(source: "camera" | "photos") {
    await execute("Capturing image", async () => {
      await flush();
      const image = await command<ImageInput>("capture", { source });
      acceptRun((await processImage(image)).run);
      await refresh();
    });
  }

  async function savePreferences(value: Preferences) {
    await execute("Saving configuration", async () => {
      if (native) await command("settings", { value });
      setPreferences(value);
      setConfig((config) => ({
        ...config,
        timezone: value.timezone,
        detailed_debug: value.detailed_debug,
      }));
      setNotice(
        native
          ? "Configuration saved."
          : "Configuration applied to browser session.",
      );
    });
  }

  async function removeScan(id: string) {
    await flush();
    await command("delete_scan", { id });
    if (run?.document.id === id) setRun(null);
    await refresh();
  }

  async function eraseAll() {
    await flush();
    await command("erase_all");
    setRun(null);
    setPreferences(defaultPreferences);
    setConfig(defaultConfig);
    await refresh();
  }

  return {
    native,
    run,
    config,
    setConfig,
    preferences,
    history,
    runtime,
    busy,
    error,
    notice,
    view,
    setView,
    setError,
    report,
    execute,
    cancel,
    flush,
    refresh,
    updateRun,
    processImage,
    acceptRun,
    importFiles,
    sample,
    openScan,
    reprocess,
    capture,
    savePreferences,
    removeScan,
    eraseAll,
  };
}

export type Workbench = ReturnType<typeof useWorkbench>;
