import { expect, test } from "vitest";
import { emptyAppointment, mapPoint, problems } from "./validation";
test("missing end is unresolved even when another appointment follows", () => {
  const a = emptyAppointment("2026-09-10");
  a.title = "Übung";
  a.start = "08:00";
  expect(problems(a)).toContain("Missing end time or duration");
});
test("excluded unresolved items do not prevent selected-item export", () => {
  const a = emptyAppointment(null);
  a.included = false;
  expect(problems(a)).toEqual([]);
});
test("impossible dates are rejected", () => {
  const a = emptyAppointment("2026-02-30");
  a.title = "Pause";
  a.start = "12:00";
  a.end = "12:30";
  expect(problems(a)).toContain("Missing or invalid date");
});
test("overnight end requires a later explicitly entered date", () => {
  const a = emptyAppointment("2026-09-10");
  a.title = "Pause";
  a.start = "23:45";
  a.end = "00:15";
  expect(problems(a)).toContain("Confirm end date for overnight interval");
  a.end_date = "2026-09-11";
  expect(problems(a)).toEqual([]);
});
test("edited essential fields clear stale missing-field warnings but not cancellation issues", () => {
  const a = emptyAppointment("2026-09-10");
  a.title = "Übung";
  a.start = "08:00";
  a.end = "08:30";
  a.issues = [
    { code: "missing_end", message: "missing", field: "end", blocking: true },
    {
      code: "possible_cancellation",
      message: "Cancellation must be reviewed",
      field: null,
      blocking: true,
    },
  ];
  expect(problems(a)).toEqual(["Cancellation must be reviewed"]);
});
test("projective overlays divide by homogeneous coordinate", () => {
  expect(mapPoint([2, 0, 10, 0, 3, 20, 0, 0, 2], { x: 10, y: 20 })).toEqual({
    x: 15,
    y: 40,
  });
});
