"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { command, encodeImage, isTauri } from "@/lib/native";
import {
  defaultConfig,
  defaultPreferences,
  type Config,
  type Appointment,
  type History,
  type Preferences,
  type Run,
} from "@/lib/contracts";
import { useNative } from "@/hooks/use-native";

const emptyHistory: History = { scans: [], imports: [], pending: 0 };
type ProcessingProgress = {
  id: string;
  stage: string;
  elapsed_ms: number;
  budget_ms: number;
  draft_available: boolean;
};
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
  const [progress, setProgress] = useState<ProcessingProgress | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [view, setView] = useState("run");
  const active = useRef<AbortController | null>(null);
  const saves = useRef<Promise<unknown>>(Promise.resolve());
  const saveError = useRef<unknown>(null);
  const revision = useRef(0);
  const storedRevisions = useRef(new Map<string, string>());
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
      setProgress(null);
      setError("");
      setNotice("");
      try {
        return await task(controller.signal);
      } catch (error) {
        report(error);
      } finally {
        active.current = null;
        setBusy("");
        setProgress(null);
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
        setPreferences({ ...defaultPreferences, ...preferences });
        setHistory(history);
        setRuntime(runtime);
        setConfig((value) => ({
          ...value,
          timezone: preferences.timezone,
          detailed_debug: false,
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

  useEffect(() => {
    if (!native) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/event")
      .then(({ listen }) =>
        listen<ProcessingProgress>("processing-progress", (event) => {
          if (!disposed) setProgress(event.payload);
        }),
      )
      .then((stop) => {
        if (disposed) stop();
        else unlisten = stop;
      })
      .catch(report);
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [native, report]);

  useEffect(() => {
    if (!busy) return;
    const timer = window.setInterval(
      () =>
        setProgress((p) =>
          p ? { ...p, elapsed_ms: Math.min(60000, p.elapsed_ms + 1000) } : p,
        ),
      1000,
    );
    return () => window.clearInterval(timer);
  }, [busy]);

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
    const version = ++revision.current;
    setRun(next);
    if (native) {
      saves.current = saves.current
        .catch(() => {})
        .then(async () => {
          try {
            const saved = await command<Run>("save_review", {
              id: next.document.id,
              expectedRevision: storedRevisions.current.get(next.document.id),
              appointments: next.appointments,
              complete: next.complete_page_confirmed,
              reviewed: next.review_confirmed,
            });
            if (saved.revision)
              storedRevisions.current.set(saved.document.id, saved.revision);
            if (revision.current === version) setRun(saved);
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
    if (run.revision)
      storedRevisions.current.set(run.document.id, run.revision);
    revision.current++;
    setRun(run);
    setConfig({ ...run.config, detailed_debug: false });
    setView("run");
  }

  async function importFiles(files: File[]) {
    await execute("Foto wird gelesen", async (signal) => {
      await flush();
      for (const [index, file] of files.entries()) {
        if (signal.aborted) break;
        setBusy(`Foto wird gelesen · ${index + 1}/${files.length}`);
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
    await execute("Plan wird geöffnet", async () => {
      await flush();
      acceptRun(await command<Run>("load_scan", { id }));
    });
  }

  async function recheckSaved(id: string, replacement?: File) {
    return execute("Gespeicherten Plan am Foto erneut prüfen", async () => {
      await flush();
      let image: ImageInput;
      let options = config;
      if (replacement) {
        image = {
          base64: await encodeImage(replacement),
          filename: replacement.name,
        };
      } else {
        const old = await command<Run>("load_scan", { id });
        options = { ...old.config, detailed_debug: false };
        image = {
          base64: await command<string>("source_bytes", { id }),
          filename: old.document.filename,
        };
      }
      const result = await processImage(image, options, true);
      await command("associate_recheck", {
        id: result.run.document.id,
        previous: id,
      });
      acceptRun(result.run);
      setNotice(
        "Erneut gelesen. Angaben am Foto prüfen; Kalenderänderungen werden erst in der Vorschau bestätigt.",
      );
      await refresh();
      return true;
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
    await execute("Foto wird übernommen", async () => {
      await flush();
      const image = await command<ImageInput>("capture", { source });
      acceptRun((await processImage(image)).run);
      await refresh();
    });
  }

  async function saveReview(
    appointments: Appointment[],
    selection: string[] = [],
  ) {
    if (!run) throw new Error("Kein Plan geöffnet.");
    await flush();
    const saved = native
      ? await command<Run>("save_review", {
          id: run.document.id,
          expectedRevision: storedRevisions.current.get(run.document.id),
          appointments,
          complete: run.complete_page_confirmed,
          reviewed: false,
          selection,
        })
      : {
          ...run,
          appointments: appointments.map((a) => ({
            ...a,
            approval: selection.includes(a.id)
              ? {
                  values_hash: "browser-preview",
                  approved_at: Date.now() / 1000,
                }
              : a.approval,
          })),
        };
    revision.current++;
    if (saved.revision)
      storedRevisions.current.set(saved.document.id, saved.revision);
    setRun(saved);
    await refresh();
    return saved;
  }
  async function retry() {
    if (!run) return;
    await execute("Foto wird erneut geprüft", async () => {
      await flush();
      const next = await command<Run>("retry_scan", { id: run.document.id });
      acceptRun(next);
      await refresh();
    });
  }

  async function savePreferences(value: Preferences) {
    return await execute("Einstellungen werden gespeichert", async () => {
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
      return true;
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
    progress,
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
    saveReview,
    retry,
    processImage,
    acceptRun,
    importFiles,
    sample,
    openScan,
    reprocess,
    recheckSaved,
    capture,
    savePreferences,
    removeScan,
    eraseAll,
  };
}

export type Workbench = ReturnType<typeof useWorkbench>;
