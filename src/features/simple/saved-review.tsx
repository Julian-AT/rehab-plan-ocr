"use client";
import { useRef, useState } from "react";
import type { Workbench } from "@/features/workbench/use-workbench";
import { Button } from "@/components/ui/button";
import { Panel } from "./panel";

export function SavedReview({
  w,
  close,
  opened,
}: {
  w: Workbench;
  close: () => void;
  opened: () => void;
}) {
  const [replacement, setReplacement] = useState<string | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const scans = w.history.scans.filter((s) => s.schedule_id);
  return (
    <Panel
      title="Gespeicherte Termine prüfen"
      description="Erneut mit dem Quellfoto vergleichen und Änderungen vor dem Speichern prüfen."
      onClose={close}
    >
      <p className="mb-4 text-sm">
        Teilprüfungen entfernen keine Kalendereinträge. Manuelle
        Kalenderänderungen erscheinen als Konflikte; Wiederholungen bleiben
        geschützt.
      </p>
      {!scans.length && <p>Noch keine Kalenderimporte vorhanden.</p>}
      <div className="flex flex-col gap-3">
        {scans.map((s) => (
          <div className="rounded border p-3" key={s.id}>
            <p>
              {s.dates?.join(", ") ||
                new Date(s.imported_at * 1000).toLocaleDateString("de-AT")}{" "}
              · {s.item_count} Termine
            </p>
            {s.retained ? (
              <Button
                className="mt-2"
                disabled={!!w.busy}
                onClick={async () => {
                  if (await w.recheckSaved(s.id)) opened();
                }}
              >
                Mit Originalfoto prüfen
              </Button>
            ) : (
              <p className="my-2 text-sm">
                Das Original wurde gelöscht. Ordne
                diesem Import erneut ein Foto zu.
              </p>
            )}
            <Button
              className="mt-2"
              variant="outline"
              disabled={!!w.busy}
              onClick={() => {
                setReplacement(s.id);
                file.current?.click();
              }}
            >
              Foto diesem Import zuordnen
            </Button>
          </div>
        ))}
      </div>
      <input
        ref={file}
        type="file"
        hidden
        accept=".jpg,.jpeg,.png,.heic,.heif,image/jpeg,image/png,image/heic,image/heif"
        aria-label="Foto für bestehenden Kalenderimport"
        onChange={async (e) => {
          const image = e.target.files?.[0];
          e.target.value = "";
          if (
            image &&
            replacement &&
            (await w.recheckSaved(replacement, image))
          )
            opened();
        }}
      />
      {w.error && (
        <p className="mt-3 text-destructive" role="alert">
          {w.error}
        </p>
      )}
    </Panel>
  );
}
