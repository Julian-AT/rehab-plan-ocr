"use client";

import { useEffect, useState } from "react";
import { command } from "@/lib/native";

export function useScanImage(id: string, artifact: string, native: boolean) {
  const key = `${id}/${artifact}`;
  const [result, setResult] = useState({ key: "", src: "", error: "" });
  useEffect(() => {
    let disposed = false;
    const source = native
      ? command<string>("scan_image", { id, artifact })
      : Promise.resolve(
          artifact === "original.png" ? "/synthetic-day.png" : "",
        );
    void source
      .then((src) => {
        if (!disposed) setResult({ key, src, error: "" });
      })
      .catch((error) => {
        if (!disposed) setResult({ key, src: "", error: String(error) });
      });
    return () => {
      disposed = true;
    };
  }, [id, artifact, native, key]);
  return result.key === key ? result : { key, src: "", error: "" };
}
