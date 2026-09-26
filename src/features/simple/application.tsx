"use client";
import { lazy, Suspense, useEffect, useState } from "react";
import { useWorkbench } from "@/features/workbench/use-workbench";
import { SimpleApp } from "./simple-app";
const Workbench = lazy(() =>
  import("@/features/workbench/workbench").then((m) => ({
    default: m.Workbench,
  })),
);
export function Application() {
  const w = useWorkbench();
  const [developer, setDeveloper] = useState(false);
  useEffect(() => {
    const q = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark =
        w.preferences.appearance === "dark" ||
        ((!w.preferences.appearance || w.preferences.appearance === "system") &&
          q.matches);
      document.documentElement.classList.toggle("dark", dark);
      document.documentElement.style.colorScheme = dark ? "dark" : "light";
    };
    apply();
    q.addEventListener("change", apply);
    return () => q.removeEventListener("change", apply);
  }, [w.preferences.appearance]);
  return developer ? (
    <Suspense
      fallback={
        <p className="p-6" role="status">
          Entwickleransicht wird geladen
        </p>
      }
    >
      <Workbench workbench={w} onClose={() => setDeveloper(false)} />
    </Suspense>
  ) : (
    <SimpleApp w={w} developer={() => setDeveloper(true)} />
  );
}
