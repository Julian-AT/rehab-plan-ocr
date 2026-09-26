import type { Appointment, Point } from "./contracts";
export function problems(a: Appointment): string[] {
  if (!a.included) return [];
  const issues: string[] = [];
  if (
    !a.date ||
    !/^\d{4}-\d{2}-\d{2}$/.test(a.date) ||
    Number.isNaN(Date.parse(a.date)) ||
    new Date(a.date).toISOString().slice(0, 10) !== a.date
  )
    issues.push("Missing or invalid date");
  const time = (s: string | null) => !!s && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);
  if (!time(a.start)) issues.push("Missing start time");
  if (
    !time(a.end) &&
    (!a.duration_minutes || a.duration_minutes < 1 || a.duration_minutes > 1440)
  )
    issues.push("Missing end time or duration");
  if (a.end && !time(a.end)) issues.push("Invalid end time");
  if (
    a.end &&
    a.start &&
    a.end <= a.start &&
    (!a.end_date || a.end_date <= (a.date ?? ""))
  )
    issues.push("Confirm end date for overnight interval");
  if (!a.title.trim()) issues.push("Missing title");
  for (const issue of a.issues)
    if (
      issue.blocking &&
      ![
        "missing_date",
        "missing_start",
        "missing_end",
        "invalid_end",
        "overnight_confirmation",
        "missing_title",
      ].includes(issue.code)
    )
      issues.push(issue.message);
  return [...new Set(issues)];
}
export function mapPoint(m: number[], p: Point): Point {
  const d = m[6] * p.x + m[7] * p.y + m[8];
  return {
    x: (m[0] * p.x + m[1] * p.y + m[2]) / d,
    y: (m[3] * p.x + m[4] * p.y + m[5]) / d,
  };
}
export function emptyAppointment(date: string | null): Appointment {
  return {
    id: crypto.randomUUID(),
    date,
    start: null,
    end: null,
    end_date: null,
    duration_minutes: null,
    title: "",
    location: "",
    therapist: "",
    notes: "",
    included: true,
    provenance: {},
    issues: [],
  };
}
