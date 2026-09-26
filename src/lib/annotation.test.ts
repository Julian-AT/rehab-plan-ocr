import { expect, test } from "vitest";
import { parseAnnotation } from "./annotation";
import { emptyAppointment } from "./validation";

const reference = () => ({
  schema_version: 1,
  day_id: "2026-04-30",
  document_hashes: ["a".repeat(64)],
  verified: false,
  reviewed_at: null,
  split: "development",
  uncertainty_notes: [],
  appointments: [emptyAppointment("2026-04-30")],
});

test("legacy annotations default the new therapist field", () => {
  const value = reference();
  const legacy: Partial<(typeof value.appointments)[number]> = {
    ...value.appointments[0],
  };
  delete legacy.therapist;
  expect(
    parseAnnotation({ ...value, appointments: [legacy] }).appointments[0]
      .therapist,
  ).toBe("");
});

test("malformed annotation fields fail before rendering the editor", () => {
  const value = reference();
  expect(() =>
    parseAnnotation({
      ...value,
      appointments: [{ ...value.appointments[0], title: {} }],
    }),
  ).toThrow();
  expect(() =>
    parseAnnotation({ ...value, document_hashes: ["../source"] }),
  ).toThrow();
});
