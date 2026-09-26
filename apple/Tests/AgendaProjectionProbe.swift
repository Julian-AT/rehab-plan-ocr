import Foundation

@main struct AgendaProjectionProbe {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-09-12T10:00:00Z")!
        func event(_ id: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: id, external_id: id, calendar_id: id, calendar_title: "Therapie", source: id,
                occurrence: start, recurring: false, system_only: false, writable: true,
                values: CalendarEventValues(title: id, start_utc: start, end_utc: end, timezone: "Europe/Vienna", location: "Raum 2.14", reminder_minutes: nil),
                metadata: .object(["all_day": .bool(allDay)]), fingerprint: id)
        }
        let past = event("past", "2026-09-12T08:00:00Z", "2026-09-12T09:00:00Z")
        let midnight = event("midnight", "2026-09-11T21:00:00Z", "2026-09-12T11:00:00Z")
        let ongoing = event("ongoing", "2026-09-12T09:00:00Z", "2026-09-12T11:00:00Z")
        let next = event("next", "2026-09-12T11:00:00Z", "2026-09-12T12:00:00Z")
        let overlap = event("overlap", "2026-09-12T11:00:00Z", "2026-09-12T12:00:00Z")
        let allDay = event("all-day", "2026-09-11T22:00:00Z", "2026-09-12T22:00:00Z", allDay: true)
        let expired = event("expired", "2026-09-10T22:00:00Z", "2026-09-11T22:00:00Z", allDay: true)
        let future = (13...17).map { event("future-\($0)", "2026-09-\($0)T10:00:00Z", "2026-09-\($0)T11:00:00Z") }
        let all = [past, midnight, ongoing, next, overlap, allDay, expired, next] + future
        let agenda = AgendaProjection(events: all.reversed(), now: now, calendar: calendar)
        precondition(agenda.today.count == 6 && agenda.remaining.count == 5 && agenda.past.map(\.id) == ["past"])
        precondition(agenda.marker(for: midnight, now: now) == "Jetzt")
        precondition(agenda.marker(for: ongoing, now: now) == "Jetzt")
        precondition(agenda.marker(for: next, now: now) == "Als Nächstes")
        precondition(agenda.marker(for: allDay, now: now) == nil)
        precondition(agenda.future.count == 5 && agenda.future.prefix(3).flatMap(\.events).count == 3)
        let ids = (agenda.today + agenda.future.flatMap(\.events)).map(\.id)
        precondition(Set(ids).count == ids.count && !ids.contains("expired"))
        let empty = AgendaProjection(events: [], now: now, calendar: calendar)
        precondition(empty.today.isEmpty && empty.future.isEmpty && empty.nextID == nil)
        let tomorrow = AgendaProjection(events: future, now: now, calendar: calendar)
        precondition(tomorrow.today.isEmpty && tomorrow.nextID == nil)
        let one = AgendaProjection(events: [next], now: now, calendar: calendar)
        precondition(one.remaining.count == 1 && one.nextID == next.id)
        let dst = event("dst", "2026-10-24T21:00:00Z", "2026-10-25T03:00:00Z")
        let dstNow = iso.date(from: "2026-10-25T01:30:00Z")!
        precondition(AgendaProjection(events: [dst], now: dstNow, calendar: calendar).remaining.map(\.id) == ["dst"])
        print("Agenda: empty, one, ongoing, past, overnight, all-day, overlap, duplicate identities, five future days and DST passed")
    }
}
