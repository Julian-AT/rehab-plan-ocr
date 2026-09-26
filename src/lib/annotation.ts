import { z } from "zod";
import type { Annotation } from "./contracts";

const nullableText = z.string().nullable();
const point = z.object({ x: z.number().finite(), y: z.number().finite() });
const polygon = z.array(point).max(64);
const printedState = z.enum([
  "unreviewed",
  "legible",
  "not_printed",
  "illegible",
  "cropped",
  "contradictory",
]);
const assessment = z.object({
  state: printedState,
  polygon,
  frame: z.enum(["page", "original"]),
  reasons: z.array(z.string()),
  confirmed_value: z.union([z.string(), z.number(), z.null()]),
  confirmed_at: z.number().int().nullable(),
});
const source = z.object({
  source_hash: z.string().length(64),
  original_hash: z.string().length(64),
  logical_page: z.string(),
  capture_series: z.string(),
  treatment_days: z.array(z.string()),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
  table_polygon: polygon,
  relationships_confirmed: z.boolean(),
});
const line = z.object({
  id: z.string(),
  source_hash: z.string().length(64),
  appointment_id: z.string(),
  field: z.string(),
  text: z.string(),
  polygon,
  state: printedState,
  error_causes: z.array(z.string()),
});
const annotation = z
  .object({
    input_class: z
      .enum(["rehabilitation_plan", "non_plan", "unusable"])
      .optional(),
    schema_version: z.union([z.literal(1), z.literal(2)]),
    day_id: z.string(),
    document_hashes: z.array(z.string().regex(/^[a-f0-9]{64}$/)),
    verified: z.boolean(),
    reviewed_at: nullableText,
    split: z.enum(["development", "holdout"]),
    uncertainty_notes: z.array(z.string()),
    sources: z.array(source).optional(),
    lines: z.array(line).optional(),
    coverage_confirmed: z.boolean().optional(),
    content_hash: nullableText.optional(),
    approval_hash: nullableText.optional(),
    appointments: z.array(
      z
        .object({
          id: z.string(),
          fields: z.record(z.string(), assessment).optional(),
          row_polygon: polygon.optional(),
          date: nullableText,
          start: nullableText,
          end: nullableText,
          end_date: nullableText,
          duration_minutes: z.number().int().nullable(),
          title: z.string(),
          location: z.string(),
          therapist: z.string().default(""),
          notes: z.string(),
          included: z.boolean(),
          provenance: z.record(z.string(), z.array(z.string())),
          issues: z.array(
            z.object({
              code: z.string(),
              message: z.string(),
              field: nullableText,
              blocking: z.boolean(),
            }),
          ),
        })
        .passthrough(),
    ),
  })
  .passthrough();

export function parseAnnotation(value: unknown): Annotation {
  return annotation.parse(value) as Annotation;
}

export async function readJson(file: File): Promise<unknown> {
  if (file.size > 20 * 1024 * 1024) throw new Error("JSON exceeds 20 MB.");
  return JSON.parse(await file.text());
}
