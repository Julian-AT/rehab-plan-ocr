import Foundation

@main struct AgendaProjectionProbe {
  static func main() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-09-12T10:00:00Z")!
    func event(_ id: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent
    {
      CalendarEvent(
        id: id, external_id: id, calendar_id: id, calendar_title: "Therapie", source: id,
        occurrence: start, recurring: false, system_only: false, writable: true,
        values: CalendarEventValues(
          title: id, start_utc: start, end_utc: end, timezone: "Europe/Vienna",
          location: "Raum 2.14", reminder_minutes: nil),
        metadata: .object(["all_day": .bool(allDay)]), fingerprint: id)
    }
    let past = event("past", "2026-09-12T08:00:00Z", "2026-09-12T09:00:00Z")
    let midnight = event("midnight", "2026-09-11T21:00:00Z", "2026-09-12T11:00:00Z")
    let ongoing = event("ongoing", "2026-09-12T09:00:00Z", "2026-09-12T11:00:00Z")
    let next = event("next", "2026-09-12T11:00:00Z", "2026-09-12T12:00:00Z")
    let overlap = event("overlap", "2026-09-12T11:00:00Z", "2026-09-12T12:00:00Z")
    let allDay = event("all-day", "2026-09-11T22:00:00Z", "2026-09-12T22:00:00Z", allDay: true)
    let expired = event("expired", "2026-09-10T22:00:00Z", "2026-09-11T22:00:00Z", allDay: true)
    let future = (13...17).map {
      event("future-\($0)", "2026-09-\($0)T10:00:00Z", "2026-09-\($0)T11:00:00Z")
    }
    let all = [past, midnight, ongoing, next, overlap, allDay, expired, next] + future
    let agenda = AgendaProjection(events: all.reversed(), now: now, calendar: calendar)
    precondition(
      agenda.today.count == 6 && agenda.remaining.count == 5 && agenda.past.map(\.id) == ["past"])
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
    precondition(
      AgendaProjection(events: [dst], now: dstNow, calendar: calendar).remaining.map(\.id) == [
        "dst"
      ])
    let monday = AgendaWeek(containing: now, calendar: calendar)
    precondition(calendar.component(.weekday, from: monday.start) == 2 && monday.days.count == 7)
    precondition(monday == AgendaWeek(containing: monday.days[6], calendar: calendar))
    precondition(AgendaWeek(containing: monday.end, calendar: calendar).start == monday.end)
    let selected = calendar.date(byAdding: .day, value: 1, to: now)!
    let otherDay = DayAgenda(events: all, date: selected, now: now, calendar: calendar)
    precondition(otherDay.events.map(\.id) == ["future-13"] && !otherDay.isComplete)
    let complete = DayAgenda(events: [past], date: now, now: now, calendar: calendar)
    precondition(complete.isComplete)
    precondition(!DayAgenda(events: [], date: now, now: now, calendar: calendar).isComplete)
    precondition(
      !DayAgenda(events: [past, allDay], date: now, now: now, calendar: calendar).isComplete)
    precondition(
      !DayAgenda(
        events: [past], date: now, now: past.values.end.addingTimeInterval(-1), calendar: calendar
      ).isComplete)
    precondition(
      DayAgenda(events: [past], date: now, now: past.values.end, calendar: calendar).isComplete)
    let day = DayAgenda(events: all, date: now, now: now, calendar: calendar)
    precondition(day.allDay.map(\.id) == ["all-day"])
    precondition(day.timed.first?.start == 0 && day.timed.first?.event.id == "midnight")
    precondition(day.timed.first?.duration == 13 * 60)
    let short = event("short", "2026-09-12T13:00:00Z", "2026-09-12T13:01:00Z")
    let adjacent = event("adjacent", "2026-09-12T13:02:00Z", "2026-09-12T13:04:00Z")
    let after = event("after", "2026-09-12T14:00:00Z", "2026-09-12T14:30:00Z")
    let layout = AgendaLayout.place(
      DayAgenda(events: [short, adjacent, after], date: now, now: now, calendar: calendar).timed)
    precondition(layout[0].height == 44 && layout[1].height == 44)
    precondition(layout[0].column != layout[1].column && layout[0].columns == 2)
    precondition(layout[2].columns == 1 && layout[2].height == 48)
    let overlaps = AgendaLayout.place(day.timed)
    for a in overlaps {
      for b in overlaps where a.id != b.id && a.column == b.column {
        precondition(
          a.segment.start + a.height / 96 * 60 <= b.segment.start
            || b.segment.start + b.height / 96 * 60 <= a.segment.start)
      }
    }
    let autumn = DayAgenda(events: [dst], date: dstNow, now: dstNow, calendar: calendar)
    precondition(autumn.minutes == 1500 && autumn.timed.first?.duration == 300)
    let springDate = iso.date(from: "2026-03-29T10:00:00Z")!
    let spring = event("spring", "2026-03-29T00:30:00Z", "2026-03-29T01:30:00Z")
    let springDay = DayAgenda(
      events: [spring], date: springDate, now: springDate, calendar: calendar)
    precondition(springDay.minutes == 1380 && springDay.timed.first?.duration == 60)
    let boundary = event("boundary", "2026-09-11T21:00:00Z", "2026-09-11T22:00:00Z")
    precondition(
      DayAgenda(events: [boundary], date: now, now: now, calendar: calendar).events.isEmpty)
    let multiday = event("multi", "2026-09-11T21:00:00Z", "2026-09-14T01:00:00Z")
    precondition(
      DayAgenda(events: [multiday], date: now, now: now, calendar: calendar).timed.first?.duration
        == 1440)
    let lastDay = iso.date(from: "2026-09-14T10:00:00Z")!
    precondition(
      DayAgenda(events: [multiday], date: lastDay, now: now, calendar: calendar).timed.first?
        .duration == 180)
    let early = event("early", "2026-09-12T03:00:00Z", "2026-09-12T04:00:00Z")
    let late = event("late", "2026-09-12T16:00:00Z", "2026-09-12T17:00:00Z")
    let crossing = event("crossing", "2026-09-12T15:59:00Z", "2026-09-12T17:00:00Z")
    let windowDay = DayAgenda(
      events: all + [early, late, crossing, multiday], date: now, now: now, calendar: calendar)
    let window = AgendaWindow(agenda: windowDay, now: now, calendar: calendar)
    precondition(
      calendar.component(.hour, from: window.start) == 6
        && calendar.component(.hour, from: window.end) == 18)
    precondition(window.minutes == 720 && Set(window.outside.map(\.id)) == ["early", "late"])
    precondition(window.timed.first { $0.id == "midnight" }?.duration == 420)
    precondition(window.timed.first { $0.id == "multi" }?.duration == 720)
    precondition(window.timed.first { $0.id == "crossing" }?.duration == 1)
    precondition(AgendaLayout.place(window.timed).first { $0.id == "crossing" }!.height >= 44)
    precondition(window.timed.allSatisfy { $0.start >= 0 && $0.start + $0.duration <= 720 })
    precondition(AgendaWindow(agenda: autumn, now: dstNow, calendar: calendar).minutes == 720)
    precondition(
      AgendaWindow(agenda: springDay, now: springDate, calendar: calendar).minutes == 720)
    precondition(
      !DayAgenda(events: [past, late], date: now, now: now, calendar: calendar).isComplete)
    precondition(window.scrollMinute >= 0 && window.scrollMinute <= 720)
    // The requested swipe direction, vertical scroll rejection, week and DST boundaries.
    let sunday = monday.days[6]
    precondition(
      AgendaNavigation.swipedDate(sunday, horizontal: -90, vertical: 4, calendar: calendar)
        == monday.end)
    precondition(
      AgendaNavigation.swipedDate(monday.end, horizontal: 90, vertical: 4, calendar: calendar)
        == sunday)
    precondition(
      AgendaNavigation.swipedDate(now, horizontal: 60, vertical: 100, calendar: calendar) == nil)
    precondition(
      AgendaNavigation.swipedDate(now, horizontal: 12, vertical: 0, calendar: calendar) == nil)
    for date in [springDate, dstNow] {
      let next = AgendaNavigation.swipedDate(
        date, horizontal: -100, vertical: 0, calendar: calendar)!
      precondition(calendar.component(.hour, from: next) == 0)
      precondition(
        AgendaNavigation.swipedDate(next, horizontal: 100, vertical: 0, calendar: calendar)
          == calendar.startOfDay(for: date))
    }
    let lastOfYear = iso.date(from: "2026-12-31T11:00:00Z")!
    let firstOfYear = AgendaNavigation.swipedDate(
      lastOfYear, horizontal: -80, vertical: 0, calendar: calendar)!
    precondition(
      calendar.component(.year, from: firstOfYear) == 2027
        && calendar.component(.day, from: firstOfYear) == 1)
    for density in AgendaDensity.allCases {
      let segments = DayAgenda(
        events: [short, adjacent, next, overlap, after], date: now, now: now, calendar: calendar
      ).timed
      let readable = ReadableAgendaLayout(
        segments, minutes: 1440, pointsPerHour: density.pointsPerHour)
      for minute in stride(from: 0.0, through: 1440.0, by: 15) {
        precondition(abs(readable.minute(at: readable.y(minute)) - minute) < 0.01)
      }
      precondition(readable.items.first { $0.id == "short" }!.height == 44)
      precondition(readable.items.allSatisfy { $0.height >= 44 })
      precondition(readable.height == 24 * density.pointsPerHour)
      for minute in stride(from: 0.0, through: 1380.0, by: 60) {
        precondition(
          abs(readable.y(minute + 60) - readable.y(minute) - density.pointsPerHour) < 0.001)
      }
      for a in readable.items {
        for b in readable.items where a.id != b.id && a.placement.column == b.placement.column {
          precondition(a.top + a.height <= b.top || b.top + b.height <= a.top)
        }
      }
      precondition(
        readable.items.first { $0.id == "next" }!.top
          == readable.items.first { $0.id == "overlap" }!.top)
    }
    var axis = AgendaAxisLock()
    precondition(axis.update(x: 3, y: 3) == nil)
    precondition(axis.update(x: 6, y: 6) == .vertical)
    precondition(axis.update(x: 100, y: 7) == .vertical)
    axis.reset()
    precondition(axis.update(x: -7, y: 6) == .horizontal)
    precondition(axis.update(x: 0, y: 100) == .horizontal)
    let firstWindow = AgendaWindow(
      agenda: DayAgenda(events: [short, adjacent], date: now, now: now, calendar: calendar),
      now: now, calendar: calendar)
    let secondWindow = AgendaWindow(agenda: day, now: now, calendar: calendar)
    let common = ReadableAgendaLayout(
      firstWindow.timed + secondWindow.timed, pointsPerHour: 72)
    let a = ReadableAgendaLayout(segments: firstWindow.timed, projection: common, pointsPerHour: 72)
    let b = ReadableAgendaLayout(
      segments: secondWindow.timed, projection: common, pointsPerHour: 72)
    for minute in stride(from: 0.0, through: 720.0, by: 5) {
      precondition(a.y(minute) == b.y(minute))
      precondition(abs(a.minute(at: b.y(minute)) - minute) < 0.001)
    }
    var withNotes = next
    let json = try! JSONEncoder().encode(withNotes)
    var object = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
    object["metadata"] = [
      "notes":
        "Therapeut:in: Anna Beispiel\n  MSc\nKlinik: Laßnitzhöhe\nRaum: Raum 2.14\nHinweise: Nicht als Therapeut verwenden"
    ]
    withNotes = try! JSONDecoder().decode(
      CalendarEvent.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(withNotes.therapist == "Anna Beispiel, MSc")
    precondition(withNotes.placeDescription == "Raum 2.14 · Laßnitzhöhe")
    precondition(next.therapist == nil && next.therapistDescription == nil)
    object["metadata"] = ["notes": "Therapeut:  \nRaum: \t"]
    var values = object["values"] as! [String: Any]
    values["location"] = "  \n"
    object["values"] = values
    let missing = try! JSONDecoder().decode(
      CalendarEvent.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(missing.placeDescription == nil && missing.therapistDescription == nil)
    precondition(!missing.spoken.contains("angegeben") && !missing.spoken.contains("Therapeut:"))
    precondition(AgendaDensity.allCases.map(\.pointsPerHour) == [96, 144, 192])
    let linkID = "5A99D362-901B-4FAD-8A0B-20B7B4EBCABD"
    precondition(AgendaLink(URL(string: "reha-calendar://event/\(linkID)")!) == .event(linkID))
    precondition(AgendaLink(URL(string: "reha-calendar://today")!) == .today)
    for link in [
      "reha-calendar://event/extra/\(linkID)", "reha-calendar://event/\(linkID)?edit=true",
      "reha-calendar://event/\(linkID)#extra", "reha-calendar://event/invalid",
      "reha-calendar://user@event/\(linkID)", "reha-calendar://today?extra=true",
    ] {
      precondition(AgendaLink(URL(string: link)!) == nil)
    }
    print(
      "Agenda: weekly navigation, selected day, completion boundary, empty, overlapping hit areas, short events, all-day, midnight, multiday 23/25-hour DST days and clipped 06–18 window passed"
    )
  }
}
