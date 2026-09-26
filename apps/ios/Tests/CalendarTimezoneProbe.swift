import Foundation

private actor ZonedCalendarFixture {
  var intervals: [(Date, Date)] = []
  let events: [CalendarEvent]
  init(_ events: [CalendarEvent]) { self.events = events }
  func query(_ start: Date, _ end: Date) -> CalendarQueryResponse {
    intervals.append((start, end))
    return CalendarQueryResponse(events: events, unavailableCalendarIDs: [])
  }
}

@main struct CalendarTimezoneProbe {
  static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  static func calendar(_ zone: String) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone)!
    return value
  }
  static func event(_ id: String, _ start: String, _ end: String) -> CalendarEvent {
    CalendarEvent(
      id: id, external_id: id, calendar_id: "visible", calendar_title: "Privat", source: "Quelle",
      occurrence: "", recurring: false, system_only: false, writable: true,
      values: CalendarEventValues(
        title: "Bewegung", start_utc: start, end_utc: end, timezone: "UTC",
        location: "Raum 7", reminder_minutes: nil), metadata: .object([:]), fingerprint: id)
  }
  static func main() async throws {
    let vienna = calendar("Europe/Vienna")
    let lagos = calendar("Africa/Lagos")
    let start = date("2026-03-28T23:00:00Z")
    let fixture = ZonedCalendarFixture([
      event("late", "2026-03-29T22:30:00Z", "2026-03-29T22:45:00Z")
    ])
    let conversation = CalendarConversation(fetch: { await fixture.query($0, $1) })
    let token = UUID()
    await conversation.begin(token)
    let first = try await conversation.resolve(
      CalendarQuestion(detail: .count, date: start, timezone: vienna.timeZone.identifier),
      token: token, now: start)
    let second = try await conversation.resolve(
      CalendarQuestion(detail: .count, date: start, timezone: lagos.timeZone.identifier),
      token: token, now: start)
    precondition(first.total == 0 && second.total == 1, "Different civil-day ends reused one cache")
    let intervals = await fixture.intervals
    precondition(intervals.count == 2)
    precondition(intervals[0].0 == start && intervals[1].0 == start)
    precondition(intervals[0].1 == date("2026-03-29T22:00:00Z"))
    precondition(intervals[1].1 == date("2026-03-29T23:00:00Z"))

    let autumn = date("2026-10-24T22:00:00Z")
    _ = try await conversation.resolve(
      CalendarQuestion(detail: .count, date: autumn, timezone: vienna.timeZone.identifier),
      token: token, now: autumn)
    let autumnInterval = await fixture.intervals.last!
    precondition(autumnInterval.0 == autumn)
    precondition(autumnInterval.1 == date("2026-10-25T23:00:00Z"))

    let newYork = calendar("America/New_York")
    let day = date("2026-09-15T04:00:00Z")
    let late = event("night", "2026-09-16T02:00:00Z", "2026-09-16T02:30:00Z")
    let evening = ZonedCalendarFixture([late])
    let reference = CalendarConversation(fetch: { await evening.query($0, $1) })
    let referenceToken = UUID()
    await reference.begin(referenceToken)
    let listed = try await reference.resolve(
      CalendarQuestion(date: day, timezone: newYork.timeZone.identifier), token: referenceToken,
      now: day)
    precondition(listed.events.map(\.id) == ["night"], "Captured day lost its late appointment")
    precondition(listed.text.contains("15. September") && listed.text.contains("22:00"))
    let detail = try await reference.resolve(
      CalendarQuestion(
        detail: .room, date: day, usesLastPage: true, timezone: newYork.timeZone.identifier),
      token: referenceToken, now: day)
    precondition(detail.text == "Der Raum ist Raum 7.", "Reference used the device's day")
    let spokenStart = try await reference.resolve(
      CalendarQuestion(detail: .start, usesLastPage: true, timezone: newYork.timeZone.identifier),
      token: referenceToken, now: day)
    precondition(spokenStart.text.contains("15. September") && spokenStart.text.contains("22:00"))
    let context = try await reference.context()
    precondition(
      context.contains("2026-09-15"), "Discussed civil date was reformatted in device zone")
    let pagingFixture = ZonedCalendarFixture(
      (0..<6).map { index in
        event("page-\(index)", "2026-09-16T02:0\(index):00Z", "2026-09-16T02:1\(index):00Z")
      })
    let paging = CalendarConversation(fetch: { await pagingFixture.query($0, $1) })
    let pageToken = UUID()
    await paging.begin(pageToken)
    let page = try await paging.resolve(
      CalendarQuestion(date: day, timezone: newYork.timeZone.identifier), token: pageToken, now: day
    )
    precondition(page.events.count == 5)
    // Continuation retains the original interval and zone even if the next
    // request carries a different device zone.
    let more = try await paging.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true, timezone: "Europe/Vienna"),
      token: pageToken, now: day)
    precondition(more.events.map(\.id) == ["page-5"] && more.text.contains("22:05"))
    for phrase in ["Termine heute", "Und morgen", "Nächster Termin", "Welcher Raum?", "Danach"] {
      let parsed = CalendarQuestion.direct(phrase, now: day, calendar: newYork)
      precondition(parsed?.timezone == newYork.timeZone.identifier, phrase)
    }
    print(
      "Calendar timezone: DST cache separation, captured day, live references, spoken times and rule scope passed"
    )
  }
}
