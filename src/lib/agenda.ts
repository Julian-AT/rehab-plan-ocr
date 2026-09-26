export interface AgendaEvent {
  id: string;
  start: number;
  end: number;
  timezone: string;
  title: string;
  room: string;
  status: string;
}
export interface AgendaSnapshot {
  schemaVersion: number;
  updatedAt: number;
  access: "available" | "empty" | "unavailable";
  events: AgendaEvent[];
  deletedIDs: string[];
}
export interface ReminderStatus {
  authorization: "notDetermined" | "authorized" | "provisional" | "denied";
  enabled: boolean;
  scheduled: number;
  calendar: number;
  protected: number;
  error: string | null;
  migrationVersion: number;
}
export interface AgendaResponse {
  snapshot: AgendaSnapshot;
  reminders: ReminderStatus;
  presentation?: AgendaPresentation;
}
export interface AgendaPresentation {
  next?: AgendaEvent;
  today: AgendaEvent[];
  stale: boolean;
}
export const emptyAgenda: AgendaResponse = {
  snapshot: {
    schemaVersion: 1,
    updatedAt: 0,
    access: "empty",
    events: [],
    deletedIDs: [],
  },
  reminders: {
    authorization: "notDetermined",
    enabled: false,
    scheduled: 0,
    calendar: 0,
    protected: 0,
    error: null,
    migrationVersion: 0,
  },
};
export function eventIDFromURL(value: string): string | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "reha-calendar:" ||
      url.hostname !== "event" ||
      url.search ||
      url.hash
    )
      return null;
    const id = url.pathname.slice(1);
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      id,
    )
      ? id
      : null;
  } catch {
    return null;
  }
}
export function agendaAt(snapshot: AgendaSnapshot, now: Date) {
  const seconds = now.valueOf() / 1000;
  const dayStart = new Date(now);
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);
  const unique = [
    ...new Map(snapshot.events.map((event) => [event.id, event])).values(),
  ].sort((a, b) => a.start - b.start || a.id.localeCompare(b.id));
  return {
    next: unique.find((event) => event.end > seconds),
    today: unique.filter(
      (event) =>
        event.start < dayEnd.valueOf() / 1000 &&
        event.end > dayStart.valueOf() / 1000,
    ),
    stale: snapshot.updatedAt > 0 && seconds - snapshot.updatedAt > 86400,
  };
}
export function eventTime(event: AgendaEvent) {
  return new Date(event.start * 1000).toLocaleTimeString("de-AT", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: event.timezone,
  });
}
export function relativeEvent(event: AgendaEvent, now: Date) {
  const seconds = now.valueOf() / 1000;
  if (event.start <= seconds && event.end > seconds) return "Jetzt";
  if (event.end <= seconds) return "Erledigt";
  const minutes = Math.ceil((event.start - seconds) / 60);
  if (minutes < 60)
    return `In ${minutes} ${minutes === 1 ? "Minute" : "Minuten"}`;
  if (minutes < 1440)
    return `In ${Math.floor(minutes / 60)} ${Math.floor(minutes / 60) === 1 ? "Stunde" : "Stunden"}`;
  return new Date(event.start * 1000).toLocaleDateString("de-AT", {
    weekday: "short",
    day: "numeric",
    month: "short",
    timeZone: event.timezone,
  });
}
