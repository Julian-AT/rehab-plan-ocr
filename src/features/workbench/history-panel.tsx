"use client";

import { useState } from "react";
import type { Workbench } from "./use-workbench";
import { command } from "@/lib/native";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Empty, EmptyHeader, EmptyTitle } from "@/components/ui/empty";
import { JsonView } from "@/components/json-view";

type Confirmation = {
  label: string;
  description: string;
  task: () => Promise<unknown>;
};

export function HistoryPanel({ workbench: w }: { workbench: Workbench }) {
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          disabled={!w.native || !!w.busy}
          onClick={() => w.execute("Refreshing history", w.refresh)}
        >
          Refresh
        </Button>
        <Button
          variant="outline"
          disabled={!w.native || !!w.busy}
          onClick={() =>
            w.execute("Running retention cleanup", async () => {
              await command("maintenance");
              await w.refresh();
            })
          }
        >
          Run cleanup
        </Button>
        <Button
          variant="destructive"
          disabled={!w.native || !!w.busy}
          onClick={() =>
            setConfirmation({
              label: "Delete all app data",
              description:
                "Deletes local scans, settings, and import ledger. Existing calendar events and research datasets remain. Duplicate prevention for previous imports will be lost.",
              task: w.eraseAll,
            })
          }
        >
          Delete all app data
        </Button>
      </div>
      {w.history.scans.length ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Scan</TableHead>
              <TableHead>Imported (UTC)</TableHead>
              <TableHead>Items</TableHead>
              <TableHead>Artifacts</TableHead>
              <TableHead>Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {w.history.scans.map((scan) => (
              <TableRow key={scan.id}>
                <TableCell className="font-mono">
                  {scan.id.slice(0, 8)}
                </TableCell>
                <TableCell>
                  {new Date(scan.imported_at * 1000)
                    .toISOString()
                    .slice(0, 16)
                    .replace("T", " ")}
                </TableCell>
                <TableCell>{scan.item_count}</TableCell>
                <TableCell>
                  <Badge variant="outline">
                    {scan.retained ? "retained" : "expired"}
                  </Badge>
                </TableCell>
                <TableCell>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      disabled={!scan.retained || !!w.busy}
                      onClick={() => w.openScan(scan.id)}
                    >
                      Open
                    </Button>
                    <Button
                      variant="ghost"
                      disabled={!scan.retained || !!w.busy}
                      onClick={() =>
                        setConfirmation({
                          label: "Delete scan artifacts",
                          description: `Delete retained source and trace for ${scan.id.slice(0, 8)}. Import identities remain for reconciliation.`,
                          task: () => w.removeScan(scan.id),
                        })
                      }
                    >
                      Delete
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>No retained scans</EmptyTitle>
          </EmptyHeader>
        </Empty>
      )}
      {!!w.history.pending && (
        <div className="flex flex-col gap-3">
          <h2 className="text-sm font-medium">
            Uncertain writes ({w.history.pending})
          </h2>
          <Button
            variant="outline"
            disabled={!!w.busy}
            onClick={() =>
              w.execute("Reconciling EventKit writes", async () => {
                await command("reconcile_calendar");
                await w.refresh();
              })
            }
          >
            Reconcile with calendar
          </Button>
          {w.history.pending_details?.map(([id, op]) => (
            <div key={id} className="flex flex-col gap-2">
              <JsonView value={{ operation_id: id, ...op }} />
              <div className="flex flex-wrap gap-2">
                {[
                  "not_applied",
                  ...(op.kind === "remove" ? ["removal_applied"] : []),
                ].map((resolution) => (
                  <Button
                    key={resolution}
                    variant="outline"
                    disabled={!!w.busy}
                    onClick={() =>
                      setConfirmation({
                        label: `Confirm ${resolution}`,
                        description:
                          "Only confirm after inspecting the actual calendar event. Incorrect resolution can cause duplicates or stale ledger records.",
                        task: async () => {
                          await command("resolve_pending_write", {
                            operationId: id,
                            resolution,
                          });
                          await w.refresh();
                        },
                      })
                    }
                  >
                    {resolution}
                  </Button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
      {!!w.history.failures?.length && (
        <>
          <h2 className="text-sm font-medium">Failed runs</h2>
          <JsonView value={w.history.failures} />
        </>
      )}
      {!!w.history.imports.length && (
        <>
          <h2 className="text-sm font-medium">Import ledger</h2>
          <JsonView value={w.history.imports} />
        </>
      )}
      <Dialog
        open={!!confirmation}
        onOpenChange={(open) => {
          if (!open) setConfirmation(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{confirmation?.label}</DialogTitle>
            <DialogDescription>{confirmation?.description}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmation(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              disabled={!!w.busy}
              onClick={async () => {
                if (confirmation) {
                  await w.execute(confirmation.label, confirmation.task);
                  setConfirmation(null);
                }
              }}
            >
              Confirm
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
