import Foundation
import RehaCore

actor CalendarFixture {
  var events: [CalendarEvent]
  var calls = 0
  init(_ events: [CalendarEvent]) { self.events = events }
  func replace(_ events: [CalendarEvent]) { self.events = events }
  func query(_ start: Date, _ end: Date) -> CalendarQueryResponse {
    calls += 1
    return CalendarQueryResponse(events: events, unavailableCalendarIDs: [])
  }
}

@main struct CalendarAnswerProbe {
  static func main() async throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-15T06:00:00Z")!
    func event(_ id: String, title: String = "Bewegung", hour: Int = 8, room: String = "")
      -> CalendarEvent
    {
      CalendarEvent(
        id: id, external_id: id, calendar_id: "visible", calendar_title: "Privat", source: "Quelle",
        occurrence: "", recurring: false, system_only: false, writable: true,
        values: CalendarEventValues(
          title: title, start_utc: String(format: "2026-09-15T%02d:00:00Z", hour),
          end_utc: String(format: "2026-09-15T%02d:30:00Z", hour), timezone: "Europe/Vienna",
          location: room, reminder_minutes: nil),
        metadata: .object([:]), fingerprint: id)
    }
    for phrase in [
      "Was ist mein nächster Termin?", "Wann ist mein nächster Termin?", "Nächster Termin",
    ] {
      precondition(CalendarQuestion.direct(phrase, now: now)?.detail == .next, phrase)
    }
    for phrase in [
      "Termine morgen", "Morgen Termine vorlesen", "Habe ich keine Termine?",
      "Welche Termine habe ich heute?", "Wie viele Termine habe ich morgen?",
    ] {
      precondition(CalendarQuestion.direct(phrase, now: now) != nil, phrase)
    }
    for phrase in [
      "Termine nicht morgen sondern am Freitag",
      "Was ist mein nächster Termin nach der Physiotherapie?", "Termine im Kalender Privat morgen",
      "Termine am 31.02.2026", "Termine nächste Woche", "Wie viele Termine außer Bewegung?",
      "Termine übermorgen und morgen",
    ] {
      precondition(CalendarQuestion.direct(phrase, now: now) == nil, phrase)
    }
    precondition(CalendarQuestion.isRepeat("Bitte wiederholen!"))
    precondition(CalendarQuestion.concernsCalendar("Was steht danach an?"))
    precondition(!CalendarQuestion.concernsCalendar("Wie geht es dir?"))
    let vocabulary = CalendarVocabulary.phrases(
      titles: Array(repeating: "Therapie", count: 50) + (0..<50).map { "Übung \($0)" })
    precondition(vocabulary.count == 32 && Set(vocabulary.map { $0.lowercased() }).count == 32)
    precondition(
      !CalendarVocabulary.phrases(titles: [String(repeating: "x", count: 81)]).contains(
        String(repeating: "x", count: 81)))
    print(
      "Structured schema bytes: \((try JSONEncoder().encode(CalendarUnderstanding.generationSchema)).count)"
    )
    let rows = (0..<8).map { event("\($0)", hour: 8 + $0) }
    let list = CalendarAnswer.build(
      CalendarQuestion(), events: rows.reversed() + [rows[0]], now: now)
    precondition(list.total == 8 && list.events.map(\.id) == ["0", "1", "2", "3", "4"])
    precondition(list.text.contains("3 weitere") && !list.text.contains("Privat"))
    let count = CalendarAnswer.build(
      CalendarQuestion(detail: .count), events: rows + [rows[0]], warning: "Unvollständig.",
      now: now)
    precondition(
      count.total == 8 && count.text.hasPrefix("Unvollständig.")
        && count.text.contains("8 passende"))
    let duplicates = CalendarAnswer.build(
      CalendarQuestion(detail: .count), events: [event("a"), event("b")], now: now)
    precondition(duplicates.total == 2, "Distinct events with identical fields must survive")
    let excluded = CalendarAnswer.build(
      CalendarQuestion(detail: .count, excluding: "Bewegung"), events: rows, now: now)
    precondition(excluded.total == 0)
    let fixture = CalendarFixture(rows)
    let store = CalendarConversation(fetch: { start, end in await fixture.query(start, end) })
    let token = UUID()
    await store.begin(token)
    let first = try await store.resolve(CalendarQuestion(date: now), token: token, now: now)
    precondition(first.events.count == 5)
    _ = try await store.resolve(CalendarQuestion(date: now), token: token, now: now)
    let firstCalls = await fixture.calls
    precondition(firstCalls == 1, "One query snapshot per answer")
    let second = try await store.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: token, now: now)
    precondition(second.events.map(\.id) == ["5", "6", "7"])
    let exhausted = try await store.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: token, now: now)
    precondition(exhausted.events.isEmpty && exhausted.offset == 8)
    let exhaustedAgain = try await store.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: token, now: now)
    precondition(exhaustedAgain.events.isEmpty && exhaustedAgain.offset == 8)
    _ = try await store.resolve(CalendarQuestion(detail: .next, date: now), token: token, now: now)
    let following = try await store.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: token, now: now)
    precondition(
      following.events.map(\.id) == ["1", "2", "3", "4", "5"],
      "More after the next event must not skip four events")
    _ = try await store.resolve(CalendarQuestion(date: now, offset: 5), token: token, now: now)
    let detail = try await store.resolve(
      CalendarQuestion(detail: .room, ordinal: 2, usesLastPage: true), token: token, now: now)
    precondition(detail.text == "Für diesen Termin ist mir kein Raum bekannt.")
    let nextToken = UUID()
    await fixture.replace([])  // Simulate a hidden calendar or deleted event.
    await store.begin(nextToken)
    let hidden = try await store.resolve(
      CalendarQuestion(detail: .room, usesLastPage: true), token: nextToken, now: now)
    precondition(hidden.events.isEmpty && hidden.text.contains("nicht mehr lesbar"))
    let secondCalls = await fixture.calls
    precondition(secondCalls == 2)
    do {
      _ = try await store.resolve(CalendarQuestion(), token: token, now: now)
      preconditionFailure("Old generation must not publish")
    } catch is CancellationError {}
    let empty = try await store.resolve(
      CalendarQuestion(detail: .count, date: now), token: nextToken, now: now)
    precondition(empty.total == 0)
    await store.clear()
    let lastToken = UUID()
    await store.begin(lastToken)
    let ambiguous = try await store.resolve(
      CalendarQuestion(detail: .room, usesLastPage: true), token: lastToken, now: now, address: .sie
    )
    precondition(ambiguous.text == "Welchen Termin meinen Sie?")
    let reply = ConversationReply(first.text)
    precondition(reply.text.contains("Bewegung") && reply.speech.contains("Bewegung"))
    if CommandLine.arguments.count == 2 {
      let examples = [
        (
          "next",
          CalendarAnswer.build(
            CalendarQuestion(detail: .next),
            events: [event("sample", title: "Physiotherapie", room: "Raum 2.14")], now: now
          ).text
        ),
        ("count", count.text),
        ("unknown-room", detail.text),
        ("clarify-sie", ambiguous.text),
      ].map { name, text in ["name": name, "text": text, "speech": ConversationReply(text).speech] }
      try JSONSerialization.data(withJSONObject: examples, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    print(
      "Calendar answers: direct/complex routing, counts, pages, exclusions, duplicates, missing rooms, Du/Sie, live visibility, per-answer cache and cancellation passed"
    )
  }
}
