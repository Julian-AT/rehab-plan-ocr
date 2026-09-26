#if DEBUG && targetEnvironment(simulator)
  import Foundation
  import RehaCore

  @MainActor enum CalendarToolProbe {
    static func run(_ core: NativeApplication, day: Date) async throws {
      let store = CalendarConversation(fetch: { start, end, scope in
        try await core.calendarEvents(from: start, to: end, expecting: scope)
      })
      let token = UUID()
      await store.begin(token)
      func require(_ test: Bool, _ name: String) throws {
        guard test else {
          throw LocalSpeechError.message("Kalenderprüfung fehlgeschlagen: " + name)
        }
      }
      let first = try await store.resolve(CalendarQuestion(date: day), token: token)
      try require(first.total == 12 && first.events.count == 5, "pagination")
      try require(first.events[1].values.title == "Prüftermin 2", "order")
      let detail = try await store.resolve(
        CalendarQuestion(detail: .therapist, ordinal: 2, usesLastPage: true), token: token)
      try require(detail.text.contains("Anna Beispiel"), "verified therapist")
      try require(!detail.text.contains(first.events[1].calendar_title), "calendar names omitted")
      do {
        _ = try await store.resolve(CalendarQuestion(ordinal: Int.min), token: token)
        throw LocalSpeechError.message("Invalid ordinal accepted")
      } catch CalendarUnderstandingError.invalidRequest {}
      try require(CalendarConversation.civilDate("2026-02-31") == nil, "invalid date")
      let second = try await store.resolve(
        CalendarQuestion(offset: 5, usesLastPage: true), token: token)
      try require(second.events.count == 5 && second.offset == 5, "second page")
      let third = try await store.resolve(
        CalendarQuestion(offset: 5, usesLastPage: true), token: token)
      try require(third.events.count == 2 && third.offset == 10, "last page")
      for _ in 0..<2 {
        let exhausted = try await store.resolve(
          CalendarQuestion(offset: 5, usesLastPage: true), token: token)
        try require(exhausted.events.isEmpty && exhausted.offset == 12, "stable exhausted page")
      }
      let next = try await store.resolve(
        CalendarQuestion(detail: .next, date: day), token: token, now: day)
      try require(next.events.first?.values.title == "Prüftermin 1", "next event")
      let following = try await store.resolve(
        CalendarQuestion(offset: 5, usesLastPage: true), token: token, now: day)
      try require(
        following.offset == 1 && following.events.first?.values.title == "Prüftermin 2",
        "more after next skips no events")
      let change = CalendarUnderstanding.Change(title: "Test", date: nil, time: nil, duration: nil)
      let intent = try change.validated(action: .create)
      try require(intent.newDate == nil && intent.newTime == nil, "missing values stay missing")
      let unchanged = try await store.resolve(
        CalendarQuestion(detail: .count, date: day), token: token)
      try require(unchanged.total == 12, "no writes while interpreting")
      await store.invalidate()
      do {
        _ = try await store.resolve(CalendarQuestion(date: day), token: token)
        throw LocalSpeechError.message("Stale request accepted")
      } catch is CancellationError {}
      let fresh = UUID()
      await store.begin(fresh)
      await store.invalidate(token)
      await store.clear(token)  // Late cleanup must not stop a newer turn.
      let emptyDay = Calendar.current.date(byAdding: .day, value: 3, to: day)!
      let empty = try await store.resolve(CalendarQuestion(date: emptyDay), token: fresh)
      try require(empty.total == 0, "empty day")
      let forged = try await store.resolve(CalendarQuestion(reference: "forged"), token: fresh)
      try require(
        forged.events.isEmpty && forged.text.contains("Welchen Termin"), "forged reference")
      try Data(
        "Calendar answers: integration checks passed; interpretation never writes calendar events.\n"
          .utf8
      ).write(to: URL.documentsDirectory.appendingPathComponent("preview-calendar-tools.txt"))
    }
  }
#endif
