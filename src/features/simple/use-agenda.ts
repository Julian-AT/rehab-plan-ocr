"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { command } from "@/lib/native";
import {
  emptyAgenda,
  eventIDFromURL,
  type AgendaResponse,
  type AgendaPresentation,
} from "@/lib/agenda";
import type { Workbench } from "@/features/workbench/use-workbench";

export function useAgenda(w: Workbench) {
  const [data, setData] = useState(emptyAgenda);
  const [now, setNow] = useState<Date | null>(null);
  const [opening, setOpening] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const inflight = useRef<Promise<AgendaResponse | undefined> | null>(null);
  const native = w.native && w.runtime?.platform === "ios";
  const refresh = useCallback((): Promise<AgendaResponse | undefined> => {
    if (!native) return Promise.resolve(undefined);
    if (inflight.current) return inflight.current;
    setLoading(true);
    inflight.current = command<AgendaResponse>("agenda")
      .then((value) => {
        setData(value);
        setError("");
        return value;
      })
      .catch((reason) => {
        setError(String(reason));
        return undefined;
      })
      .finally(() => {
        inflight.current = null;
        setLoading(false);
      });
    return inflight.current;
  }, [native]);
  useEffect(() => {
    const timer = window.setTimeout(() => {
      setNow(new Date());
      void refresh();
    }, 0);
    let disposed = false;
    const clock = window.setInterval(() => {
      setNow(new Date());
      if (native && document.visibilityState === "visible") {
        void command<AgendaPresentation>("agenda_presentation")
          .then((presentation) => {
            if (!disposed)
              setData((previous) => ({ ...previous, presentation }));
          })
          .catch((reason) => {
            if (!disposed) setError(String(reason));
          });
      }
    }, 15000);
    const sync = window.setInterval(() => {
      if (document.visibilityState === "visible") void refresh();
    }, 60000);
    return () => {
      disposed = true;
      clearTimeout(timer);
      clearInterval(clock);
      clearInterval(sync);
    };
  }, [native, refresh, w.history, w.preferences]);
  useEffect(() => {
    if (!native) return;
    let disposed = false;
    let stop: (() => void) | undefined;
    let reading = false;
    const receive = (urls: string[]) => {
      const id = urls.map(eventIDFromURL).find(Boolean);
      if (id && !disposed) {
        setOpening(id);
        void refresh();
      }
    };
    void import("@tauri-apps/plugin-deep-link")
      .then(async ({ getCurrent, onOpenUrl }) => {
        const unlisten = await onOpenUrl(receive);
        if (disposed) {
          unlisten();
          return;
        }
        stop = unlisten;
        const urls = await getCurrent();
        if (urls && !disposed) receive(urls);
      })
      .catch((reason) => {
        if (!disposed) setError(String(reason));
      });
    const pending = async () => {
      if (reading || disposed || document.visibilityState !== "visible") return;
      reading = true;
      try {
        const { id } = await command<{ id: string | null }>(
          "pending_event_open",
        );
        if (id && !disposed) {
          const result = await refresh();
          if (result && !disposed) {
            setOpening(id);
            await command("pending_event_open", { acknowledge: id });
          }
        }
      } catch (reason) {
        if (!disposed) setError(String(reason));
      } finally {
        reading = false;
      }
    };
    const resume = () => {
      if (document.visibilityState === "visible") {
        void refresh();
        void pending();
      }
    };
    void pending();
    const timer = window.setInterval(() => void pending(), 1500);
    document.addEventListener("visibilitychange", resume);
    window.addEventListener("focus", resume);
    return () => {
      disposed = true;
      stop?.();
      clearInterval(timer);
      document.removeEventListener("visibilitychange", resume);
      window.removeEventListener("focus", resume);
    };
  }, [native, refresh]);
  return {
    data,
    setData,
    now,
    opening,
    setOpening,
    error,
    loading,
    refresh,
    native,
  };
}
export type Agenda = ReturnType<typeof useAgenda>;
