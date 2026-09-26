"use client";

import Image from "next/image";
import { useState } from "react";
import { Maximize2, ZoomIn, ZoomOut } from "lucide-react";
import { cn } from "cn";
import type { Point, Run } from "@/lib/contracts";
import { mapPoint } from "@/lib/validation";
import { useScanImage } from "@/hooks/use-scan-image";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Field, FieldLabel } from "@/components/ui/field";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription } from "@/components/ui/alert";

export function SourceViewer({
  run,
  native,
  simple = false,
  highlight = [],
  onRegion,
  onCorner,
  corners = [],
}: {
  run: Run;
  native: boolean;
  simple?: boolean;
  highlight?: string[];
  onRegion?: (id: string) => void;
  onCorner?: (point: Point) => void;
  corners?: Point[];
}) {
  const [zoom, setZoom] = useState(1);
  const [overlay, setOverlay] = useState(false);
  const { src, error } = useScanImage(run.document.id, "original.png", native);
  const selectedRegions = new Set(
    run.observations
      .filter((o) => highlight.includes(o.id))
      .flatMap((o) => o.region_ids),
  );
  return (
    <section
      aria-label={simple ? "Quellfoto" : "Source image"}
      className="flex min-w-0 flex-col gap-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        {!simple && (
          <Field orientation="horizontal" className="w-auto">
            <Checkbox
              id="regions-visible"
              checked={overlay}
              onCheckedChange={(value) => setOverlay(value === true)}
            />
            <FieldLabel htmlFor="regions-visible">Regions</FieldLabel>
          </Field>
        )}
        <div className="flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon"
            aria-label={simple ? "Verkleinern" : "Zoom out"}
            disabled={zoom <= 1}
            onClick={() => setZoom(Math.max(1, zoom - 0.25))}
          >
            <ZoomOut />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            aria-label={simple ? "Vergrößern" : "Zoom in"}
            disabled={zoom >= 3}
            onClick={() => setZoom(Math.min(3, zoom + 0.25))}
          >
            <ZoomIn />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            aria-label={simple ? "Zoom zurücksetzen" : "Reset zoom"}
            onClick={() => setZoom(1)}
          >
            <Maximize2 />
          </Button>
        </div>
      </div>
      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="max-h-[65vh] overflow-auto rounded-md border bg-muted/30">
        <div className="relative" style={{ width: `${zoom * 100}%` }}>
          {src ? (
            <Image
              src={src}
              alt={
                simple ? "Originalfoto des Terminplans" : "Original schedule"
              }
              width={run.document.width}
              height={run.document.height}
              className="h-auto w-full"
              loading="eager"
            />
          ) : (
            <Skeleton className="h-96 w-full" />
          )}
          <svg
            viewBox={`0 0 ${run.document.width} ${run.document.height}`}
            className={cn(
              "absolute inset-0 size-full",
              onCorner && "cursor-crosshair",
            )}
            aria-label={simple ? "Markierte Textstellen" : "Source coordinates"}
            onClick={(event) => {
              if (!onCorner) return;
              const rect = event.currentTarget.getBoundingClientRect();
              onCorner({
                x:
                  ((event.clientX - rect.left) / rect.width) *
                  run.document.width,
                y:
                  ((event.clientY - rect.top) / rect.height) *
                  run.document.height,
              });
            }}
          >
            {run.regions
              .filter(
                (r) =>
                  r.kind === "text" && (overlay || selectedRegions.has(r.id)),
              )
              .map((region) => (
                <polygon
                  key={region.id}
                  points={region.polygon
                    .map((p) =>
                      region.frame === "original"
                        ? p
                        : mapPoint(run.page_to_original, p),
                    )
                    .map((p) => `${p.x},${p.y}`)
                    .join(" ")}
                  data-selected={selectedRegions.has(region.id)}
                  className="source-region"
                  role={onRegion ? "button" : undefined}
                  tabIndex={onRegion ? 0 : undefined}
                  aria-label={`Region ${region.id}`}
                  onClick={(event) => {
                    if (!onCorner) {
                      event.stopPropagation();
                      onRegion?.(region.id);
                    }
                  }}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      event.preventDefault();
                      onRegion?.(region.id);
                    }
                  }}
                />
              ))}
            {corners.map((p, index) => (
              <g key={index}>
                <circle
                  cx={p.x}
                  cy={p.y}
                  r={run.document.width / 90}
                  className="fill-primary"
                />
                <text
                  x={p.x}
                  y={p.y}
                  dy=".35em"
                  textAnchor="middle"
                  fontSize={run.document.width / 75}
                  className="fill-primary-foreground"
                >
                  {index + 1}
                </text>
              </g>
            ))}
          </svg>
        </div>
      </div>
      {!simple && (
        <p className="break-all font-mono text-xs text-muted-foreground">
          {run.document.width} × {run.document.height} ·{" "}
          {run.document.source_hash.slice(0, 16)}
        </p>
      )}
    </section>
  );
}
