import Foundation
import RehaCore

actor CalendarFixture {
  var events: [CalendarEvent]
  var calls = 0
  init(_ events: [CalendarEvent]) { self.events = events }
  func replace(_ events: [CalendarEvent]) { self.events = events }
  func query(_ start: Date, _ end: Date, _ expected: AgendaSelection?) throws
    -> CalendarQueryResponse
  {
    calls += 1
    let scope = AgendaSelection(calendarIDs: ["visible"])
    guard expected == nil || expected == scope else { throw CalendarQueryFailure.selectionChanged }
    return CalendarQueryResponse(scope: scope, events: events, unavailableCalendarIDs: [])
  }
}

/// Simulate a Core selection change between the answer range and anchor lookup.
private actor ChangingSelectionFixture {
  let events: [CalendarEvent]
  var scope = AgendaSelection(calendarIDs: ["visible"], revision: 4)
  var changeAfterRead = false
  var ignoreExpected = false
  var requested: [AgendaSelection?] = []
  init(_ events: [CalendarEvent]) { self.events = events }
  func arm(ignoreExpected: Bool) {
    changeAfterRead = true
    self.ignoreExpected = ignoreExpected
    requested = []
  }
  func query(_ start: Date, _ end: Date, _ expected: AgendaSelection?) throws
    -> CalendarQueryResponse
  {
    requested.append(expected)
    if !ignoreExpected, let expected, expected != scope {
      throw CalendarQueryFailure.selectionChanged
    }
    let result = CalendarQueryResponse(scope: scope, events: events, unavailableCalendarIDs: [])
    if changeAfterRead {
      changeAfterRead = false
      scope.revision += 2  // A -> B -> A; IDs and timezone look unchanged.
    }
    return result
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
    for phrase in [
      "Wann habe ich morgen meinen ersten Termin?",
      "Um wie viel Uhr beginnt mein erster Termin morgen?",
      "Der erste Termin am Mittwoch", "Wann ist der erste Termin am 16.09.2026?",
    ] {
      guard let query = CalendarQuestion.direct(phrase, now: now) else {
        preconditionFailure("Missing first-appointment query: \(phrase)")
      }
      precondition(query.detail == .first && query.date != nil && query.days == 1, phrase)
      precondition(query.ordinal == 0 && !query.usesLastPage && query.title.isEmpty, phrase)
    }
    precondition(CalendarQuestion.direct("Was steht für morgen an?", now: now)?.detail == .list)
    for phrase in [
      "Wann habe ich morgen meinen ersten Termin außer Physiotherapie?",
      "Wann habe ich morgen meinen ersten Termin und übermorgen?",
      "Wann beginnt mein erster Termin am 31.02.2026?",
      "Was steht für morgen an im Kalender Privat?",
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
    let later = ISO8601DateFormatter().date(from: "2026-09-15T10:45:00Z")!
    let firstOfDay = CalendarAnswer.build(
      CalendarQuestion(detail: .first), events: rows, now: later)
    let nextUpcoming = CalendarAnswer.build(
      CalendarQuestion(detail: .next), events: rows, now: later)
    precondition(
      firstOfDay.events.map(\.id) == ["0"], "First of the day must include past appointments")
    precondition(nextUpcoming.events.map(\.id) == ["3"], "Next must exclude ended appointments")
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
    var vienna = Calendar(identifier: .gregorian)
    vienna.timeZone = TimeZone(identifier: "Europe/Vienna")!
    for phrase in ["Termine am 21. September", "Termine am einundzwanzigsten September"] {
      let request = CalendarQuestion.direct(phrase, now: now, calendar: vienna)
      precondition(request?.date != nil, phrase)
      precondition(vienna.component(.day, from: request!.date!) == 21, phrase)
    }
    for phrase in [
      "Termine am 31. Februar", "Termine am 12. September 202", "Termine nicht morgen",
      "Termine am einunddreissigsten April",
    ] {
      precondition(CalendarQuestion.direct(phrase, now: now, calendar: vienna) == nil, phrase)
    }
    let negatedCount = CalendarQuestion.direct(
      "Habe ich keine Termine morgen?", now: now, calendar: vienna)
    precondition(vienna.component(.day, from: negatedCount!.date!) == 16)
    let morning = CalendarQuestion.direct("Termine heute vormittags", now: now, calendar: vienna)!
    precondition(morning.beforeMinutes == 720 && morning.afterMinutes == nil)
    let afternoon = CalendarQuestion.direct(
      "Termine heute nachmittags", now: now, calendar: vienna)!
    precondition(afternoon.afterMinutes == 720 && afternoon.beforeMinutes == 1080)
    let boundedNext = CalendarQuestion.direct(
      "Was habe ich morgen als Nächstes nach 8 Uhr?", now: now, calendar: vienna)!
    precondition(boundedNext.detail == .next && boundedNext.afterMinutes == 480)
    precondition(vienna.component(.day, from: boundedNext.date!) == 16)
    let spokenBound = CalendarQuestion.direct(
      "Was habe ich morgen als Nächstes nach acht Uhr?", now: now, calendar: vienna)
    precondition(spokenBound == boundedNext)
    let correctedDay = CalendarQuestion.direct(
      "Nicht morgen, sondern übermorgen: Welche Termine habe ich da?", now: now, calendar: vienna)!
    precondition(correctedDay.detail == .list)
    precondition(vienna.component(.day, from: correctedDay.date!) == 17)
    precondition(CalendarQuestion.direct("Und der Raum dazu?")?.detail == .room)
    for phrase in [
      "Und der Raum dazu außer Gymnastik?", "Und der Raum dazu morgen?",
      "Was habe ich morgen als Nächstes nach 8 Uhr und vor 11 Uhr?",
      "Nicht morgen, sondern übermorgen: Welche Termine habe ich da außer Bewegung?",
    ] {
      precondition(CalendarQuestion.direct(phrase, now: now, calendar: vienna) == nil, phrase)
    }
    precondition(
      CalendarAnswer.build(morning, events: rows, now: now).events.map(\.id) == ["0", "1"])
    precondition(CalendarAnswer.build(afternoon, events: rows, now: now).total == 6)
    let late = CalendarQuestion.direct(
      "Wie viele Termine habe ich heute nach 14 uhr", now: now, calendar: vienna)!
    precondition(CalendarAnswer.build(late, events: rows, now: now).total == 4)
    precondition(CalendarQuestion.direct("Termine heute nach 25 uhr", now: now) == nil)
    precondition(CalendarQuestion.direct("Termine heute nach 14 uhr nach 10 uhr", now: now) == nil)
    precondition(
      CalendarQuestion.direct("Termine heute nach 14 uhr außer Bewegung", now: now) == nil)
    let invalidBounds = CalendarQuestion(afterMinutes: 900, beforeMinutes: 800)
    precondition(!invalidBounds.validTimeBounds)
    var differentZone = morning
    differentZone.timezone = "UTC"
    precondition(CalendarAnswer.build(differentZone, events: rows, now: now).total == 4)
    let allDay = CalendarEvent(
      id: "all-day", external_id: "all-day", calendar_id: "visible", calendar_title: "Privat",
      source: "Quelle", occurrence: "", recurring: false, system_only: false, writable: true,
      values: rows[0].values, metadata: .object(["all_day": .bool(true)]), fingerprint: "all-day")
    let timedAndUnknown = CalendarAnswer.build(morning, events: rows + [allDay], now: now)
    precondition(
      timedAndUnknown.total == 2 && timedAndUnknown.text.contains("keine bekannte Uhrzeit"))
    var understood = CalendarUnderstanding.Query(
      detail: .list, date: "2026-09-15", days: 1, title: "", excluding: "", calendarName: nil,
      reference: nil, ordinal: 0, usesLastPage: false, after: "12:00", before: "18:00")
    let validatedTime = try understood.validated()
    precondition(validatedTime.afterMinutes == 720)
    for invalid in ["25:00", "12:61", "morgen"] {
      understood.after = invalid
      do {
        _ = try understood.validated()
        preconditionFailure("Invalid model time accepted")
      } catch CalendarUnderstandingError.invalidRequest {}
    }
    let boundedFixture = CalendarFixture(rows)
    let boundedStore = CalendarConversation(fetch: { start, end, scope in
      try await boundedFixture.query(start, end, scope)
    })
    let boundedToken = UUID()
    await boundedStore.begin(boundedToken)
    let boundedFirst = try await boundedStore.resolve(afternoon, token: boundedToken, now: now)
    let boundedMore = try await boundedStore.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: boundedToken, now: now)
    precondition(boundedFirst.total == 6 && boundedMore.events.map(\.id) == ["7"])
    do {
      _ = try await boundedStore.resolve(invalidBounds, token: boundedToken)
      preconditionFailure("Contradictory time bounds accepted")
    } catch CalendarUnderstandingError.invalidRequest {}
    let relativeFixture = CalendarFixture(rows)
    let relativeStore = CalendarConversation(fetch: { start, end, scope in
      try await relativeFixture.query(start, end, scope)
    })
    let relativeToken = UUID()
    await relativeStore.begin(relativeToken)
    _ = try await relativeStore.resolve(
      CalendarQuestion(detail: .next, date: now), token: relativeToken, now: now)
    let afterThat = CalendarQuestion.direct("Und danach?", now: now)!
    let relativeNext = try await relativeStore.resolve(afterThat, token: relativeToken, now: now)
    precondition(relativeNext.events.map(\.id) == ["1"], "After that must not repeat the anchor")
    let relativeMore = try await relativeStore.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: relativeToken, now: now)
    precondition(relativeMore.events.map(\.id) == ["2", "3", "4", "5", "6"])
    let relativeFresh = UUID()
    await relativeFixture.replace(Array(rows.dropFirst()))
    await relativeStore.begin(relativeFresh)
    let hiddenAnchor = try await relativeStore.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: relativeFresh, now: now)
    precondition(hiddenAnchor.events.isEmpty && hiddenAnchor.text.contains("nicht mehr lesbar"))
    var tomorrowValues = rows[0].values
    tomorrowValues.start_utc = "2026-09-16T08:00:00Z"
    tomorrowValues.end_utc = "2026-09-16T08:30:00Z"
    // Keep a distinct event identity while putting the target outside the anchor day.
    let nextDayEvent = CalendarEvent(
      id: "tomorrow", external_id: "tomorrow", calendar_id: "visible", calendar_title: "Privat",
      source: "Quelle", occurrence: "", recurring: false, system_only: false, writable: true,
      values: tomorrowValues, metadata: .object([:]), fingerprint: "tomorrow")
    let nextDayFixture = CalendarFixture(rows + [nextDayEvent])
    let nextDayStore = CalendarConversation(fetch: { start, end, scope in
      try await nextDayFixture.query(start, end, scope)
    })
    let nextDayToken = UUID()
    await nextDayStore.begin(nextDayToken)
    _ = try await nextDayStore.resolve(
      CalendarQuestion(detail: .next, date: now), token: nextDayToken, now: now)
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
    let conflictingDate = try await nextDayStore.resolve(
      CalendarQuestion(detail: .room, date: tomorrow, usesLastPage: true),
      token: nextDayToken, now: now)
    precondition(conflictingDate.events.isEmpty && conflictingDate.text.contains("anderen Tag"))
    let tomorrowAfter = try await nextDayStore.resolve(
      CalendarQuestion(detail: .next, date: tomorrow, usesLastPage: true),
      token: nextDayToken, now: now)
    precondition(
      tomorrowAfter.events.map(\.id) == ["tomorrow"],
      "Explicit date must survive reference resolution")
    let tomorrowMore = try await nextDayStore.resolve(
      CalendarQuestion(offset: 5, usesLastPage: true), token: nextDayToken, now: now)
    precondition(tomorrowMore.events.isEmpty && tomorrowMore.offset == 1)
    for ignoresExpected in [false, true] {
      let changing = ChangingSelectionFixture(rows + [nextDayEvent])
      let guarded = CalendarConversation(fetch: { try await changing.query($0, $1, $2) })
      let priorTurn = UUID()
      await guarded.begin(priorTurn)
      _ = try await guarded.resolve(
        CalendarQuestion(detail: .next, date: now), token: priorTurn, now: now)
      let turn = UUID()
      await guarded.begin(turn)
      await changing.arm(ignoreExpected: ignoresExpected)
      do {
        _ = try await guarded.resolve(
          CalendarQuestion(detail: .next, date: tomorrow, usesLastPage: true), token: turn, now: now
        )
        preconditionFailure("An answer combined two different selection revisions")
      } catch CalendarQueryFailure.selectionChanged {}
      let requests = await changing.requested
      precondition(requests.count == 2 && requests[0] == nil)
      precondition(requests[1]?.revision == 4 && requests[1]?.calendarIDs == ["visible"])
      do {
        _ = try await guarded.resolve(CalendarQuestion(date: tomorrow), token: turn, now: now)
        preconditionFailure("An invalidated turn reused its old answer cache")
      } catch CalendarQueryFailure.selectionChanged {}
      let freshTurn = UUID()
      await guarded.begin(freshTurn)
      let fresh = try await guarded.resolve(
        CalendarQuestion(date: tomorrow), token: freshTurn, now: now)
      precondition(fresh.events.map(\.id) == ["tomorrow"])
      let freshRequests = await changing.requested
      precondition(freshRequests.last! == nil, "A new turn must capture the new selection")
    }
    let fixture = CalendarFixture(rows)
    let store = CalendarConversation(fetch: { start, end, scope in
      try await fixture.query(start, end, scope)
    })
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
