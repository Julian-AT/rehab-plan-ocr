"use client";
import { useState } from "react";
import { command } from "@/lib/native";
import type { Proposal, WriteResult } from "@/lib/contracts";
import type { Workbench } from "@/features/workbench/use-workbench";
import { Button } from "@/components/ui/button";
import { Panel } from "./panel";

export function ImportHistory({
  w,
  close,
}: {
  w: Workbench;
  close: () => void;
}) {
  const [proposal, setProposal] = useState<Proposal | null>(null);
  const [removals, setRemovals] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [results, setResults] = useState<WriteResult[]>([]);
  async function act(work: () => Promise<void>) {
    setBusy(true);
    setError("");
    try {
      await work();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel
      title="Importverlauf und Rücknahme"
      description="Originale löschen und Kalenderimporte rückgängig machen sind getrennte Aktionen."
      onClose={close}
    >
      {error && <p role="alert">{error}</p>}
      {busy && <p role="status">Kalender wird abgeglichen …</p>}
      {!w.history.batches?.length && (
        <p>Für ältere Importe ist keine eindeutige Rücknahme gespeichert.</p>
      )}
      <div className="flex flex-col gap-4">
        {w.history.batches?.map((batch) => (
          <article key={batch.id} className="rounded border p-3">
            <p>
              {batch.undo_of ? "Rücknahme" : "Kalenderimport"} ·{" "}
              {new Date(batch.created_at * 1000).toLocaleString("de-AT")}
            </p>
            <p>
              {batch.operations.filter((o) => o.status === "saved").length}{" "}
              Änderungen gespeichert ·{" "}
              {batch.operations.filter((o) => o.status !== "saved").length}{" "}
              offen oder fehlgeschlagen
            </p>
            {!batch.undo_of &&
              (!batch.undone_by || w.history.batches?.some(b => b.id === batch.undone_by && b.operations.some(o => ["failed", "conflict"].includes(o.status)))) &&
              batch.operations.some((o) => o.status === "saved") && (
                <Button
                  disabled={busy}
                  onClick={() =>
                    void act(async () => {
                      setProposal(null);
                      setRemovals(false);
                      setResults([]);
                      setProposal(
                        await command<Proposal>("prepare_undo", {
                          batchId: batch.id,
                        }),
                      );
                    })
                  }
                >
                  Import rückgängig machen
                </Button>
              )}
          </article>
        ))}
        {proposal && (
          <section
            aria-label="Rücknahmevorschau"
            className="flex flex-col gap-3"
          >
            {proposal.operations.map((op) => (
              <div key={op.id} className="rounded border p-3">
                <p>{op.after?.title ?? op.before?.title ?? "Termin"}</p>
                <p>{op.reason}</p>
                {op.requires_resolution && (
                  <Button
                    disabled={busy}
                    onClick={() =>
                      void act(async () => {
                        setProposal(
                          await command<Proposal>("resolve_proposal", {
                            token: proposal.token,
                            eventId: op.id,
                            choice: "keep",
                          }),
                        );
                      })
                    }
                  >
                    Aktuellen Kalenderstand behalten
                  </Button>
                )}
              </div>
            ))}
            {proposal.operations.some((o) => o.kind === "remove") && (
              <label className="flex gap-2">
                <input
                  type="checkbox"
                  checked={removals}
                  onChange={(e) => setRemovals(e.target.checked)}
                />
                Entfernen der angezeigten Termine bestätigen
              </label>
            )}
            <Button
              disabled={
                busy ||
                proposal.operations.some((o) => o.requires_resolution) ||
                (proposal.operations.some((o) => o.kind === "remove") &&
                  !removals)
              }
              onClick={() =>
                void act(async () => {
                  setResults(
                    await command<WriteResult[]>("approve_calendar", {
                      token: proposal.token,
                      approveRemovals: removals,
                    }),
                  );
                  setProposal(null);
                  await w.refresh();
                })
              }
            >
              Rücknahme ausführen
            </Button>
          </section>
        )}
        {!!results.length && (
          <p role="status">
            {results.filter((r) => r.status === "saved").length} Änderungen
            rückgängig gemacht ·{" "}
            {results.filter((r) => r.status !== "saved").length} offen oder
            fehlgeschlagen
          </p>
        )}
      </div>
    </Panel>
  );
}
