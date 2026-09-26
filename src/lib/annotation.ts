import { z } from "zod";
import type { Annotation } from "./contracts";

const nullableText = z.string().nullable();
const annotation = z.object({
  schema_version: z.literal(1),
  day_id: z.string(),
  document_hashes: z.array(z.string().regex(/^[a-f0-9]{64}$/)),
  verified: z.boolean(),
  reviewed_at: nullableText,
  split: z.enum(["development", "holdout"]),
  uncertainty_notes: z.array(z.string()),
  appointments: z.array(
    z.object({
      id: z.string(),
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
    }),
  ),
});

export function parseAnnotation(value: unknown): Annotation {
  return annotation.parse(value);
}

export async function readJson(file: File): Promise<unknown> {
  if (file.size > 20 * 1024 * 1024) throw new Error("JSON exceeds 20 MB.");
  return JSON.parse(await file.text());
}
