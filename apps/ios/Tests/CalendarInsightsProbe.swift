import Foundation

@main struct CalendarInsightsProbe {
  static func main() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    let day = CalendarConversation.civilDate("2026-09-27", calendar: calendar)!
    func event(_ id: String, _ start: String, _ end: String, allDay: Bool = false) -> CalendarEvent
    {
      CalendarEvent(
        id: id, external_id: id, calendar_id: "visible", calendar_title: "Privat",
        source: "fixture", occurrence: "", recurring: false, system_only: false, writable: true,
        values: CalendarEventValues(
          title: id, start_utc: start, end_utc: end,
          timezone: calendar.timeZone.identifier, location: "", reminder_minutes: nil),
        metadata: .object(["all_day": .bool(allDay)]), fingerprint: id)
    }
    let a = event("Physio", "2026-09-27T07:00:00Z", "2026-09-27T08:00:00Z")
    let b = event("Ergo", "2026-09-27T07:30:00Z", "2026-09-27T09:00:00Z")
    let adjacent = event("Training", "2026-09-27T09:00:00Z", "2026-09-27T09:30:00Z")
    let crossing = event("Nacht", "2026-09-26T21:00:00Z", "2026-09-26T23:00:00Z")
    let scope = AgendaSelection(calendarIDs: ["visible"], revision: 7)
    func answer(
      _ detail: CalendarQuestion.Detail, events: [CalendarEvent], after: Int? = nil,
      before: Int? = nil, unavailable: [String] = []
    ) throws -> CalendarAnswer.Result {
      let query = CalendarQuestion(
        detail: detail, date: day, afterMinutes: after, beforeMinutes: before,
        timezone: calendar.timeZone.identifier)
      return CalendarInsights.answer(
        try CalendarInsightRequest(question: query, start: day),
        response: CalendarQueryResponse(
          scope: scope, events: events, unavailableCalendarIDs: unavailable))
    }
    let gaps = try answer(.freeTime, events: [a, b, a, adjacent], after: 8 * 60, before: 12 * 60)
    precondition(gaps.total == 2 && gaps.text.contains("08:00") && gaps.text.contains("11:30"))
    precondition(!gaps.text.contains("10:00"), "Overlapping events invented a free gap")
    let conflicts = try answer(.conflicts, events: [a, b, a, adjacent])
    precondition(conflicts.total == 1 && conflicts.text.contains("Physio und Ergo"))
    let sum = try answer(.totalDuration, events: [a, b, adjacent, crossing])
    precondition(sum.text.contains("240 Minuten"), "Midnight clipping or overlap sum wrong")
    let restricted = try answer(
      .totalDuration, events: [a, b], after: 9 * 60 + 45, before: 10 * 60 + 15)
    precondition(
      restricted.text.contains("45 Minuten"), "Bounds filtered starts instead of clipping durations"
    )
    let allDay = event("Ganztägig", "2026-09-26T22:00:00Z", "2026-09-27T22:00:00Z", allDay: true)
    let allDayFree = try answer(.freeTime, events: [allDay])
    let allDaySum = try answer(.totalDuration, events: [allDay])
    let missing = try answer(.freeTime, events: [], unavailable: ["missing"])
    precondition(allDayFree.total == 0)
    precondition(allDaySum.text.contains("0 Minuten"))
    precondition(missing.text.contains("nicht verlässlich"))
    for (date, hours) in [("2026-03-29", 23), ("2026-10-25", 25)] {
      let start = CalendarConversation.civilDate(date, calendar: calendar)!
      let request = try CalendarInsightRequest(
        question: CalendarQuestion(
          detail: .freeTime, date: start,
          timezone: calendar.timeZone.identifier), start: start)
      precondition(request.windows[0].duration == Double(hours * 3600))
      do {
        _ = try CalendarInsightRequest(
          question: CalendarQuestion(
            detail: .freeTime, date: start,
            afterMinutes: 150, beforeMinutes: 210, timezone: calendar.timeZone.identifier),
          start: start)
        preconditionFailure("Nonexistent/repeated clock time silently resolved")
      } catch CalendarUnderstandingError.invalidRequest {}
    }
    for (text, detail) in [
      ("Wann habe ich frei morgen von 9 bis 12 Uhr?", CalendarQuestion.Detail.freeTime),
      ("Gibt es Überschneidungen heute?", .conflicts),
      ("Wie lange dauern meine Termine insgesamt morgen?", .totalDuration),
      ("Tagesübersicht morgen", .dailySummary),
    ] {
      precondition(
        CalendarQuestion.direct(text, now: day, calendar: calendar)?.detail == detail, text)
    }
    let conversation = CalendarConversation { _, _, _ in
      CalendarQueryResponse(scope: scope, events: [a, b], unavailableCalendarIDs: [])
    }
    let token = UUID()
    await conversation.begin(token)
    let result = try await conversation.resolve(
      CalendarQuestion(
        detail: .freeTime, date: day,
        timezone: calendar.timeZone.identifier), token: token, now: day)
    precondition(result.evidence?.selection.revision == 7 && result.evidence?.sources.count == 2)
    let followup = CalendarQuestion.direct("nur morgen nachmittags", now: day, calendar: calendar)!
    let refined = try await conversation.resolve(followup, token: token, now: day)
    precondition(refined.text.contains("frei"), "Follow-up lost the free-time question")
    print(
      "Calendar insights: overlap union, adjacent events, duplicates, midnight clipping, partial availability, all-day duration, 23/25-hour days, ambiguous DST clocks, direct questions, follow-ups and source freshness passed"
    )
  }
}
