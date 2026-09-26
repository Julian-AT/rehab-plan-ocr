import Foundation

@MainActor private final class Source: AgendaDataSource {
  var hasAccess = true
  var selected = AgendaSelection(calendarIDs: ["therapy"])
  var responses: [Date: CalendarQueryResponse] = [:]
  var queries: [Date] = []
  var synchronizations = 0
  var holdNext = false
  var failure = false
  var wrongResponseScope = false
  var maintenanceFailure = false
  var maintenancePending: CheckedContinuation<Void, Never>?
  var holdMaintenance = false
  var scopes: [AgendaSelection] = []
  var pending: CheckedContinuation<Void, Never>?
  func selection() async throws -> AgendaSelection { selected }
  func synchronize() async throws {
    synchronizations += 1
    if holdMaintenance {
      await withCheckedContinuation { maintenancePending = $0 }
    }
    if maintenanceFailure { throw CocoaError(.fileReadUnknown) }
  }
  func events(in week: AgendaWeek, scope: AgendaSelection) async throws -> CalendarQueryResponse {
    scopes.append(scope)
    queries.append(week.start)
    let result =
      responses[week.start]
      ?? CalendarQueryResponse(
        scope: AgendaSelection(calendarIDs: ["therapy"]), events: [], unavailableCalendarIDs: [])
    if holdNext {
      holdNext = false
      await withCheckedContinuation { pending = $0 }
    }
    if failure { throw CocoaError(.fileReadUnknown) }
    return CalendarQueryResponse(
      scope: wrongResponseScope ? AgendaSelection(calendarIDs: ["hidden"]) : scope,
      events: result.events, unavailableCalendarIDs: result.unavailableCalendarIDs,
      unavailableEvents: result.unavailableEvents)
  }
  func release() {
    let continuation = pending
    pending = nil
    continuation?.resume()
  }
}

@main @MainActor struct TodayModelProbe {
  private static let week = AgendaWeek(containing: Date())
  private static func event(_ title: String) -> CalendarEvent {
    let iso = ISO8601DateFormatter()
    let start = iso.string(from: week.start.addingTimeInterval(9 * 3600))
    return CalendarEvent(
      id: "appointment", external_id: "event", calendar_id: "therapy", calendar_title: "Therapie",
      source: "local", occurrence: start, recurring: false, system_only: false, writable: true,
      values: CalendarEventValues(
        title: title, start_utc: start,
        end_utc: iso.string(from: week.start.addingTimeInterval(10 * 3600)),
        timezone: Calendar.current.timeZone.identifier, location: "Raum 1", reminder_minutes: nil),
      metadata: .object([:]), fingerprint: title)
  }
  private static func response(_ title: String) -> CalendarQueryResponse {
    CalendarQueryResponse(
      scope: AgendaSelection(calendarIDs: ["therapy"]), events: [event(title)],
      unavailableCalendarIDs: [])
  }
  private static func refresh(_ model: TodayModel, _ source: Source, key: String) async {
    await model.refresh(using: source, week: week, visibleWeek: week.start, key: key)
    await Task.yield()
  }
  private static func waitForQuery(_ source: Source) async {
    for _ in 0..<10_000 {
      if source.pending != nil { return }
      await Task.yield()
    }
    preconditionFailure("The controlled query never started")
  }

  static func main() async {
    await retainsAndRevalidates()
    await marksOnlyKnownDaysAndClearsRepairedGaps()
    await rejectsSupersededAndCancelledLoads()
    await invalidatesSensitiveContexts()
    await boundsCacheAndReusesRecentWeeks()
    await selectionRaceAndIndependentMaintenance()
    await rejectsMismatchedResponseScope()
    print(
      "Agenda cache: refresh, empty weeks, errors, cancellation, invalidation and eviction passed")
  }

  private static func rejectsMismatchedResponseScope() async {
    let source = Source()
    let model = TodayModel()
    source.responses[week.start] = response("Falsche Auswahl")
    source.wrongResponseScope = true
    await refresh(model, source, key: "wrong-response-scope")
    precondition(model.events(on: week.start) == nil)
    source.wrongResponseScope = false
    await refresh(model, source, key: "restored-response-scope")
    precondition(model.events(on: week.start)?.first?.values.title == "Falsche Auswahl")
  }

  private static func selectionRaceAndIndependentMaintenance() async {
    let model = TodayModel()
    let source = Source()
    source.responses[week.start] = response("Sichtbar")
    source.holdMaintenance = true
    await refresh(model, source, key: "maintenance")
    precondition(model.events(on: week.start)?.count == 1)
    precondition(model.availability == .ready, "Slow maintenance must not delay first content")
    for _ in 0..<10_000 {
      if source.maintenancePending != nil { break }
      await Task.yield()
    }
    precondition(source.maintenancePending != nil)
    source.maintenanceFailure = true
    source.maintenancePending?.resume()
    source.maintenancePending = nil
    source.holdNext = true
    let pending = Task { await refresh(model, source, key: "selection-race") }
    await waitForQuery(source)
    precondition(source.scopes.last == source.selected)
    source.selected.revision += 2  // A -> B -> A while the read is suspended.
    source.release()
    await pending.value
    precondition(model.events(on: week.start) == nil, "Obsolete scope must never enter the cache")
    source.selected = AgendaSelection(calendarIDs: [])
    let count = source.queries.count
    await refresh(model, source, key: "empty-after-save")
    precondition(source.queries.count == count && model.availability == .noSelection)
  }

  private static func marksOnlyKnownDaysAndClearsRepairedGaps() async {
    let model = TodayModel()
    let source = Source()
    let iso = ISO8601DateFormatter()
    let second = Calendar.current.date(byAdding: .day, value: 1, to: week.start)!
    let third = Calendar.current.date(byAdding: .day, value: 2, to: week.start)!
    let fourth = Calendar.current.date(byAdding: .day, value: 3, to: week.start)!
    source.responses[week.start] = CalendarQueryResponse(
      scope: AgendaSelection(calendarIDs: ["therapy"]),
      events: [event("Weiterhin lesbar")], unavailableCalendarIDs: ["gone"],
      unavailableEvents: [
        UnavailableCalendarEvent(
          id: "missing",
          start: iso.string(from: second.addingTimeInterval(-3600)), end: iso.string(from: third))
      ])
    await refresh(model, source, key: "gap")
    precondition(model.hasKnownGap(on: week.start) && model.hasKnownGap(on: second))
    precondition(!model.hasKnownGap(on: third) && !model.hasKnownGap(on: fourth))
    precondition(model.events(on: week.start)?.count == 1, "Readable events must not be hidden")
    source.responses[week.start] = CalendarQueryResponse(
      scope: AgendaSelection(calendarIDs: ["therapy"]),
      events: [], unavailableCalendarIDs: ["unknown-calendar"])
    await refresh(model, source, key: "unknown-days")
    precondition(
      !model.hasKnownGap(on: week.start),
      "A missing whole calendar does not identify particular days")
    precondition(!model.unavailableCalendars.isEmpty)
    source.responses[week.start] = response("Bereinigt")
    await refresh(model, source, key: "repaired")
    precondition(!model.hasKnownGap(on: second) && model.unavailableCalendars.isEmpty)
    model.invalidate()
    precondition(!model.hasKnownGap(on: week.start))
  }

  private static func retainsAndRevalidates() async {
    let model = TodayModel()
    let source = Source()
    source.responses[week.start] = response("Original")
    await refresh(model, source, key: "initial")
    precondition(source.queries.count == 3 && source.synchronizations == 1)
    source.responses[week.start] = response("Geändert")
    source.holdNext = true
    let pending = Task { await refresh(model, source, key: "changed") }
    await waitForQuery(source)
    precondition(model.isRefreshing && model.availability == .ready)
    precondition(model.events(on: week.start)?.first?.values.title == "Original")
    source.release()
    await pending.value
    precondition(model.events(on: week.start)?.first?.values.title == "Geändert")
    source.failure = true
    await refresh(model, source, key: "failed")
    precondition(model.error != nil && model.availability == .failed)
    precondition(model.events(on: week.start)?.first?.values.title == "Geändert")
    source.failure = false
    source.responses[week.start] = CalendarQueryResponse(
      scope: AgendaSelection(calendarIDs: ["therapy"]),
      events: [], unavailableCalendarIDs: ["gone"])
    await refresh(model, source, key: "deleted")
    precondition(model.events(on: week.start)?.isEmpty == true && model.error == nil)
    precondition(model.unavailableCalendars == ["gone"])
    source.responses[week.start] = CalendarQueryResponse(
      scope: AgendaSelection(calendarIDs: ["therapy"]), events: [], unavailableCalendarIDs: [])
    source.holdNext = true
    let empty = Task { await refresh(model, source, key: "empty") }
    await waitForQuery(source)
    precondition(model.events(on: week.start)?.isEmpty == true && model.availability == .ready)
    source.release()
    await empty.value
    precondition(model.unavailableCalendars.isEmpty)
    let queries = source.queries.count
    await refresh(model, source, key: "empty")
    precondition(source.queries.count == queries, "Fresh weeks must not be queried again")
  }

  private static func rejectsSupersededAndCancelledLoads() async {
    let model = TodayModel()
    let source = Source()
    source.responses[week.start] = response("Original")
    await refresh(model, source, key: "original")
    source.responses[week.start] = response("Veraltet")
    source.holdNext = true
    let old = Task { await refresh(model, source, key: "same-epoch") }
    await waitForQuery(source)
    source.responses[week.start] = response("Neu")
    // A changed page can start another task without changing the refresh epoch.
    await refresh(model, source, key: "same-epoch")
    source.release()
    await old.value
    precondition(model.events(on: week.start)?.first?.values.title == "Neu")
    source.responses[week.start] = response("Abgebrochen")
    source.holdNext = true
    let cancelled = Task { await refresh(model, source, key: "cancelled") }
    await waitForQuery(source)
    cancelled.cancel()
    source.release()
    await cancelled.value
    precondition(model.events(on: week.start)?.first?.values.title == "Neu")
    precondition(model.error == nil && !model.isRefreshing)
  }

  private static func invalidatesSensitiveContexts() async {
    let model = TodayModel()
    let source = Source()
    source.responses[week.start] = response("Original")
    await refresh(model, source, key: "initial")
    source.holdNext = true
    let erased = Task { await refresh(model, source, key: "erase") }
    await waitForQuery(source)
    model.invalidate()
    source.release()
    await erased.value
    precondition(model.events(on: week.start) == nil)
    await refresh(model, source, key: "after-erase")
    source.selected = AgendaSelection(calendarIDs: ["other"])
    source.responses[week.start] = response("Andere Auswahl")
    source.holdNext = true
    let changed = Task { await refresh(model, source, key: "selection") }
    await waitForQuery(source)
    precondition(model.events(on: week.start) == nil)
    source.release()
    await changed.value
    source.holdNext = true
    let revoked = Task { await refresh(model, source, key: "access") }
    await waitForQuery(source)
    source.hasAccess = false
    source.release()
    await revoked.value
    precondition(model.events(on: week.start) == nil && model.availability == .noAccess)
    source.hasAccess = true
    source.selected = AgendaSelection(calendarIDs: [])
    await refresh(model, source, key: "no-selection")
    precondition(model.events(on: week.start) == nil && model.availability == .noSelection)
    let queryCount = source.queries.count
    await refresh(model, source, key: "still-no-selection")
    precondition(model.events(on: week.start) == nil && model.availability == .noSelection)
    precondition(source.queries.count == queryCount)
    source.selected = AgendaSelection(calendarIDs: ["other"])
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(
      secondsFromGMT: calendar.timeZone.secondsFromGMT() == 0 ? 3600 : 0)!
    let shifted = AgendaWeek(containing: week.start, calendar: calendar)
    source.holdNext = true
    let timezone = Task {
      await model.refresh(
        using: source, week: shifted, visibleWeek: shifted.start, key: "timezone",
        calendar: calendar)
    }
    await waitForQuery(source)
    precondition(model.events(on: week.start) == nil)
    source.release()
    await timezone.value
    precondition(model.events(on: shifted.start) != nil)
  }

  private static func boundsCacheAndReusesRecentWeeks() async {
    let model = TodayModel()
    let source = Source()
    for offset in 0..<18 {
      let date = Calendar.current.date(byAdding: .day, value: offset * 7, to: week.start)!
      let target = AgendaWeek(containing: date)
      await model.refresh(using: source, week: target, visibleWeek: date, key: "browsing")
      let retained = (-1...19).filter { index in
        model.events(on: Calendar.current.date(byAdding: .day, value: index * 7, to: week.start)!)
          != nil
      }
      precondition(retained.count <= 12)
    }
    precondition(model.events(on: week.start) == nil)
    let recent = Calendar.current.date(byAdding: .day, value: 14 * 7, to: week.start)!
    precondition(model.events(on: recent)?.isEmpty == true)
    let count = source.queries.count
    await model.refresh(
      using: source, week: AgendaWeek(containing: recent), visibleWeek: recent, key: "browsing")
    for _ in 0..<10_000 {
      if source.synchronizations > 0 { break }
      await Task.yield()
    }
    precondition(source.queries.count == count && source.synchronizations == 1)
  }
}
