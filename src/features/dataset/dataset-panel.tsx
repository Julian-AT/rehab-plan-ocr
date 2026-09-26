"use client";

import { useState } from "react";
import type { Workbench, ImageInput } from "@/features/workbench/use-workbench";
import type { Run } from "@/lib/contracts";
import { command, exportFile } from "@/lib/native";
import { AnnotationPanel } from "./annotation-panel";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldDescription,
} from "@/components/ui/field";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyHeader,
  EmptyTitle,
  EmptyDescription,
} from "@/components/ui/empty";

type Entry = {
  filename: string;
  sha256: string;
  bytes: number;
  day_id: string | null;
  split: string | null;
};
type Dataset = { root: string; entries: Entry[]; split_frozen: boolean };
type BatchRun = { run: Run; path: string };

export function DatasetPanel({ workbench: w }: { workbench: Workbench }) {
  const [dataset, setDataset] = useState<Dataset | null>(null);
  const [path, setPath] = useState("");
  const [selected, setSelected] = useState<string[]>([]);
  const [engines, setEngines] = useState(["portable-small"]);
  const [runs, setRuns] = useState<BatchRun[]>([]);

  async function load() {
    await w.execute("Loading inventory", async () => {
      const result = await command<Dataset>("dataset", {
        path: path.trim() || null,
      });
      setDataset(result);
      setPath(result.root);
      setSelected([]);
    });
  }
  async function batch() {
    await w.execute("Running experiment", async (signal) => {
      await w.flush();
      setRuns([]);
      const batch = crypto.randomUUID();
      for (const hash of selected) {
        const image = await command<ImageInput>("dataset_image", { hash });
        for (const engine of engines) {
          if (signal.aborted) return;
          const { run } = await w.processImage(
            image,
            { ...w.config, engine, detailed_debug: true },
            true,
          );
          const path = await command<string>("save_lab_run", {
            batch,
            id: run.document.id,
          });
          setRuns((runs) => [...runs, { run, path }]);
        }
      }
      await w.refresh();
    });
  }
  return (
    <Tabs defaultValue="inventory" className="min-w-0">
      <TabsList>
        <TabsTrigger value="inventory">Inventory</TabsTrigger>
        <TabsTrigger value="annotation">Annotations & evaluation</TabsTrigger>
      </TabsList>
      <TabsContent value="inventory" className="flex min-w-0 flex-col gap-5">
        <FieldGroup className="sm:flex-row sm:items-end">
          <Field>
            <FieldLabel htmlFor="dataset-root">Dataset root</FieldLabel>
            <Input
              id="dataset-root"
              placeholder="data/private"
              value={path}
              onChange={(e) => setPath(e.target.value)}
            />
            <FieldDescription>
              Directory containing inventory.json, raw/, labels/, and
              split.json.
            </FieldDescription>
          </Field>
          <Button
            variant="outline"
            disabled={!w.native || !!w.busy}
            onClick={load}
          >
            Load inventory
          </Button>
        </FieldGroup>
        {dataset?.entries.length ? (
          <>
            <p className="text-sm text-muted-foreground">
              {dataset.entries.length} images · split{" "}
              {dataset.split_frozen ? "frozen" : "not frozen"}
            </p>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Select</TableHead>
                  <TableHead>Image</TableHead>
                  <TableHead>Day</TableHead>
                  <TableHead>Split</TableHead>
                  <TableHead>Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {dataset.entries.map((entry) => (
                  <TableRow key={entry.filename}>
                    <TableCell>
                      <Checkbox
                        aria-label={`Select ${entry.filename}`}
                        checked={selected.includes(entry.sha256)}
                        disabled={entry.split !== "development" || !!w.busy}
                        onCheckedChange={(value) =>
                          setSelected(
                            value === true
                              ? [...new Set([...selected, entry.sha256])]
                              : selected.filter(
                                  (hash) => hash !== entry.sha256,
                                ),
                          )
                        }
                      />
                    </TableCell>
                    <TableCell>{entry.filename}</TableCell>
                    <TableCell>{entry.day_id ?? "unassigned"}</TableCell>
                    <TableCell>
                      <Badge variant="outline">
                        {entry.split ?? "unassigned"}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Button
                        variant="outline"
                        disabled={entry.split === "holdout" || !!w.busy}
                        onClick={() =>
                          w.execute("Opening dataset image", async () => {
                            await w.flush();
                            const image = await command<ImageInput>(
                              "dataset_image",
                              { hash: entry.sha256 },
                            );
                            w.acceptRun((await w.processImage(image)).run);
                            await w.refresh();
                          })
                        }
                      >
                        Run & inspect
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </>
        ) : (
          <Empty>
            <EmptyHeader>
              <EmptyTitle>No inventory loaded</EmptyTitle>
              <EmptyDescription>
                Use scripts/dataset.py to inventory local images and freeze day
                groups.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        )}
        <FieldGroup>
          <Field>
            <FieldLabel>Batch engines</FieldLabel>
            <ToggleGroup
              type="multiple"
              value={engines}
              onValueChange={setEngines}
              variant="outline"
              disabled={!!w.busy}
              aria-label="Batch engines"
            >
              <ToggleGroupItem value="portable-small">small</ToggleGroupItem>
              <ToggleGroupItem value="portable-tiny">tiny</ToggleGroupItem>
              <ToggleGroupItem value="portable-medium">medium</ToggleGroupItem>
            </ToggleGroup>
          </Field>
        </FieldGroup>
        <div className="flex flex-wrap gap-2">
          <Button
            disabled={
              !w.native || !!w.busy || !selected.length || !engines.length
            }
            onClick={batch}
          >
            Run batch ({selected.length * engines.length})
          </Button>
          {!!runs.length && (
            <Button
              variant="outline"
              onClick={() =>
                w.execute("Exporting experiment index", () =>
                  exportFile(
                    JSON.stringify(
                      runs.map(({ run, path }) => ({
                        id: run.id,
                        source_hash: run.document.source_hash,
                        config: run.config,
                        model_manifest: run.model_manifest,
                        total_ms: run.total_ms,
                        path,
                      })),
                      null,
                      2,
                    ),
                    "experiment-index.json",
                  ),
                )
              }
            >
              Export experiment index
            </Button>
          )}
        </div>
        {!!runs.length && (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Source</TableHead>
                <TableHead>Engine</TableHead>
                <TableHead>ms</TableHead>
                <TableHead>Items</TableHead>
                <TableHead>Inspect</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {runs.map(({ run, path }) => (
                <TableRow key={run.id}>
                  <TableCell>{run.document.filename}</TableCell>
                  <TableCell>{run.engine}</TableCell>
                  <TableCell>{run.total_ms}</TableCell>
                  <TableCell>{run.appointments.length}</TableCell>
                  <TableCell>
                    <Button
                      variant="link"
                      disabled={!!w.busy}
                      title={path}
                      onClick={() => w.acceptRun(run)}
                    >
                      Open
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </TabsContent>
      <TabsContent value="annotation">
        <AnnotationPanel workbench={w} />
      </TabsContent>
    </Tabs>
  );
}
