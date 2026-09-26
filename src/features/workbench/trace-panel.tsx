"use client";

import Image from "next/image";
import { useState } from "react";
import type { Run } from "@/lib/contracts";
import { useScanImage } from "@/hooks/use-scan-image";
import { JsonView } from "@/components/json-view";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableHeader,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
} from "@/components/ui/table";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";

function Artifact({ run, name }: { run: Run; name: string }) {
  const { src, error } = useScanImage(run.document.id, name, true);
  return (
    <div className="flex flex-col gap-2">
      <code className="text-xs">{name}</code>
      {error ? (
        <p role="alert">{error}</p>
      ) : (
        src && (
          <Image
            src={src}
            alt={name}
            width={run.page_width}
            height={run.page_height}
            className="max-h-96 w-full object-contain"
          />
        )
      )}
    </div>
  );
}

export function TracePanel({
  run,
  native,
  highlight,
  onHighlight,
}: {
  run: Run;
  native: boolean;
  highlight: string[];
  onHighlight: (ids: string[]) => void;
}) {
  const [stageName, setStageName] = useState(run.stages[0]?.name ?? "");
  const [filter, setFilter] = useState("all");
  const [artifact, setArtifact] = useState("");
  const stage = run.stages.find((s) => s.name === stageName);
  const observations = run.observations.filter(
    (o) => filter !== "unassigned" || run.unassigned.includes(o.id),
  );
  return (
    <Tabs defaultValue="observations" className="min-w-0">
      <TabsList className="max-w-full overflow-x-auto">
        <TabsTrigger value="observations">Observations</TabsTrigger>
        <TabsTrigger value="stages">Stages</TabsTrigger>
        <TabsTrigger value="mapping">Mapping</TabsTrigger>
        <TabsTrigger value="validation">Validation</TabsTrigger>
        <TabsTrigger value="metadata">Metadata</TabsTrigger>
      </TabsList>
      <TabsContent value="observations" className="flex min-w-0 flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <ToggleGroup
            type="single"
            variant="outline"
            value={filter}
            onValueChange={(value) => {
              if (value) setFilter(value);
            }}
            aria-label="Observation filter"
          >
            <ToggleGroupItem value="all">
              All ({run.observations.length})
            </ToggleGroupItem>
            <ToggleGroupItem value="unassigned">
              Unassigned ({run.unassigned.length})
            </ToggleGroupItem>
          </ToggleGroup>
          <p className="text-xs text-muted-foreground">
            Engine scores are uncalibrated.
          </p>
        </div>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>Text</TableHead>
              <TableHead>Score</TableHead>
              <TableHead>Alternatives</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {observations.map((o) => (
              <TableRow
                key={o.id}
                data-state={highlight.includes(o.id) ? "selected" : undefined}
              >
                <TableCell>
                  <Button variant="link" onClick={() => onHighlight([o.id])}>
                    {o.id}
                  </Button>
                </TableCell>
                <TableCell className="min-w-48 whitespace-normal">
                  {o.text || "∅"}
                </TableCell>
                <TableCell>{o.score?.toFixed(3) ?? "unavailable"}</TableCell>
                <TableCell>{o.alternatives.join(" / ") || "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TabsContent>
      <TabsContent value="stages" className="flex flex-col gap-3">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Stage</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>ms</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {run.stages.map((s) => (
              <TableRow
                key={s.name}
                data-state={s.name === stageName ? "selected" : undefined}
              >
                <TableCell>
                  <Button
                    variant="link"
                    onClick={() => {
                      setStageName(s.name);
                      setArtifact("");
                    }}
                  >
                    {s.name}
                  </Button>
                </TableCell>
                <TableCell>
                  <Badge variant="outline">{s.status}</Badge>
                </TableCell>
                <TableCell>
                  {s.status === "unavailable" ? "—" : s.duration_ms}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {stage && (
          <>
            <p className="text-sm">{stage.detail}</p>
            <div className="flex flex-wrap gap-2">
              {stage.artifacts.map((name) => (
                <Button
                  key={name}
                  variant="outline"
                  disabled={!native || !name.endsWith(".png")}
                  onClick={() => setArtifact(name)}
                >
                  {name}
                </Button>
              ))}
            </div>
          </>
        )}
        {artifact && <Artifact key={artifact} run={run} name={artifact} />}
      </TabsContent>
      <TabsContent value="mapping">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Appointment</TableHead>
              <TableHead>Field</TableHead>
              <TableHead>Observations</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {run.appointments.flatMap((a) =>
              Object.entries(a.provenance).map(([field, ids]) => (
                <TableRow key={`${a.id}-${field}`}>
                  <TableCell>{a.title}</TableCell>
                  <TableCell>{field}</TableCell>
                  <TableCell>
                    <Button variant="link" onClick={() => onHighlight(ids)}>
                      {ids.length ? ids.join(", ") : "manual"}
                    </Button>
                  </TableCell>
                </TableRow>
              )),
            )}
          </TableBody>
        </Table>
      </TabsContent>
      <TabsContent value="validation">
        <JsonView
          value={{
            document: run.issues,
            appointments: run.appointments
              .filter((a) => a.issues.length)
              .map((a) => ({ id: a.id, issues: a.issues })),
            unassigned: run.unassigned,
          }}
        />
      </TabsContent>
      <TabsContent value="metadata">
        <JsonView
          value={{
            schema_version: run.schema_version,
            extraction_version: run.extraction_version ?? 1,
            id: run.id,
            document: run.document,
            config: run.config,
            engine: run.engine,
            model_manifest: run.model_manifest,
            total_ms: run.total_ms,
            cache_used: run.cache_used,
            peak_memory_bytes: run.peak_memory_bytes,
            original_to_page: run.original_to_page,
            page_to_original: run.page_to_original,
            regions: run.regions,
          }}
        />
      </TabsContent>
    </Tabs>
  );
}
