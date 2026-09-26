import { describe, expect, it } from "vitest";
import {
  agendaAt,
  emptyAgenda,
  eventIDFromURL,
  relativeEvent,
  type AgendaEvent,
} from "./agenda";
const event = (id: string, start: string, end: string): AgendaEvent => ({
  id,
  start: Date.parse(start) / 1000,
  end: Date.parse(end) / 1000,
  timezone: "Europe/Vienna",
  title: "Physiotherapie",
  room: "Raum 204",
  status: "current",
});
describe("saved agenda", () => {
  it("shows running events first, retains simultaneous events and deduplicates stable imports", () => {
    const now = new Date("2026-09-11T07:30:00Z");
    const a = event("a", "2026-09-11T07:00:00Z", "2026-09-11T08:00:00Z");
    const b = event("b", "2026-09-11T07:00:00Z", "2026-09-11T08:00:00Z");
    const state = agendaAt({ ...emptyAgenda.snapshot, events: [b, a, a] }, now);
    expect(state.next?.id).toBe("a");
    expect(state.today.map((v) => v.id)).toEqual(["a", "b"]);
    expect(relativeEvent(a, now)).toBe("Jetzt");
    expect(
      agendaAt(
        { ...emptyAgenda.snapshot, events: [a] },
        new Date("2026-09-11T08:00:00Z"),
      ).next,
    ).toBeUndefined();
  });
  it("does not invent appointments from an empty snapshot and flags a stale one", () => {
    expect(agendaAt(emptyAgenda.snapshot, new Date()).today).toEqual([]);
    expect(
      agendaAt({ ...emptyAgenda.snapshot, updatedAt: 1 }, new Date(86402000))
        .stale,
    ).toBe(true);
  });
  it("accepts only exact event deep links with a stable UUID", () => {
    const id = "aabbccdd-1111-2222-3333-123456789012";
    expect(eventIDFromURL(`reha-calendar://event/${id}`)).toBe(id);
    for (const url of [
      `https://event/${id}`,
      `reha-calendar://event/${id}/extra`,
      `reha-calendar://event/${id}?evil=1`,
      "reha-calendar://event/..",
      "garbage",
    ])
      expect(eventIDFromURL(url)).toBeNull();
  });
});
