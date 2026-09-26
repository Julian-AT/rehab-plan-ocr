"use client";
import { ArrowUpRight, CalendarDays, MapPin, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  agendaAt,
  eventTime,
  relativeEvent,
  type AgendaEvent,
} from "@/lib/agenda";
import type { Agenda } from "./use-agenda";
export function Today({
  agenda,
  importPlan,
  open,
}: {
  agenda: Agenda;
  importPlan: () => void;
  open: (id: string) => void;
}) {
  const { snapshot } = agenda.data;
  const now = agenda.now;
  const { next, today, stale } = agenda.native
    ? (agenda.data.presentation ?? { next: undefined, today: [], stale: false })
    : agendaAt(snapshot, now ?? new Date(0));
  const unavailable = snapshot.access === "unavailable";
  return (
    <div className="today-content">
      {(agenda.error || unavailable || stale) && (
        <div className="agenda-notice" role="status">
          <p>
            {agenda.error ||
              (unavailable
                ? "Kalenderzugriff fehlt. Öffne die Einstellungen und prüfe den Zugriff."
                : "Diese Termine wurden länger nicht abgeglichen.")}
          </p>
          <Button
            variant="outline"
            disabled={agenda.loading}
            onClick={() => void agenda.refresh()}
          >
            Erneut abgleichen
          </Button>
        </div>
      )}
      {(next || today.length > 0) && now ? (
        <>
          {next ? (
            <button
              className="next-appointment"
              onClick={() => open(next.id)}
              aria-label={`${eventTime(next)} ${next.title} öffnen`}
            >
              <div className="card-eyebrow">
                <span>
                  {next.start <= now.valueOf() / 1000
                    ? "DEIN TERMIN LÄUFT"
                    : "DEIN NÄCHSTER TERMIN"}
                </span>
                <ArrowUpRight aria-hidden="true" size={20} />
              </div>
              <div className="hero-time">
                {eventTime(next)}
                <span className="time-dot" />
              </div>
              <h2>{next.title}</h2>
              <p className="room-line">
                <MapPin size={18} aria-hidden="true" />
                {next.room || "Raum nicht angegeben"}
              </p>
              <span className="relative-pill">{relativeEvent(next, now)}</span>
            </button>
          ) : (
            <div className="plan-empty">
              <CalendarDays size={32} strokeWidth={1.5} />
              <h2>Alles erledigt für heute.</h2>
              <p>Deine Termine für diesen Tag bleiben hier im Überblick.</p>
            </div>
          )}
          <section className="day-agenda" aria-labelledby="day-agenda-title">
            <div className="section-heading">
              <h2 id="day-agenda-title">Dein Tagesablauf</h2>
              <span>
                {today.length} {today.length === 1 ? "Termin" : "Termine"}
              </span>
            </div>
            {today.length === 0 && (
              <p className="secondary-copy">
                Heute ist alles erledigt. Dein nächster Termin steht oben.
              </p>
            )}
            <ol className="timeline-list">
              {today.map((event) => (
                <TimelineRow
                  key={event.id}
                  event={event}
                  now={now}
                  open={open}
                />
              ))}
            </ol>
          </section>
        </>
      ) : unavailable || agenda.error ? null : (
        <section className="empty-day">
          <div className="empty-calendar" aria-hidden="true">
            <CalendarDays strokeWidth={1.25} size={48} />
            <span>+</span>
          </div>
          <p className="eyebrow">DEIN TAG. GUT GEPLANT.</p>
          <h2>
            {agenda.loading
              ? "Deine Termine werden geladen."
              : "Mehr Ruhe.\nAlles im Blick."}
          </h2>
          <p>
            Importiere deinen Behandlungsplan.
            <br />
            Deine bestätigten Termine begleiten dich durch den Tag.
          </p>
          <Button onClick={importPlan} size="lg">
            <Plus size={20} aria-hidden="true" />
            Plan importieren
          </Button>
        </section>
      )}
    </div>
  );
}
function TimelineRow({
  event,
  now,
  open,
}: {
  event: AgendaEvent;
  now: Date;
  open: (id: string) => void;
}) {
  const label = relativeEvent(event, now);
  return (
    <li
      className={`timeline-row ${label === "Erledigt" ? "is-past" : ""} ${label === "Jetzt" ? "is-now" : ""}`}
    >
      <button onClick={() => open(event.id)}>
        <time dateTime={new Date(event.start * 1000).toISOString()}>
          {eventTime(event)}
        </time>
        <span className="timeline-marker" aria-hidden="true" />
        <span className="timeline-details">
          <strong>{event.title}</strong>
          <span>{event.room || "Raum nicht angegeben"}</span>
          {label === "Jetzt" && <span className="now-label">Jetzt</span>}
        </span>
        <ArrowUpRight size={18} aria-hidden="true" />
      </button>
    </li>
  );
}
