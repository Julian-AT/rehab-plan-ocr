import Foundation
import RehaCore

extension AgendaSelection {
  init(_ scope: AgendaQueryScope) {
    self.init(
      calendarIDs: Set(scope.calendarIds), timezone: scope.timezone, revision: scope.revision)
  }
  var nativeScope: AgendaQueryScope {
    AgendaQueryScope(calendarIds: calendarIDs.sorted(), timezone: timezone, revision: revision)
  }
}

extension NativeApplication {
  func calendarEvents(from start: Date, to end: Date, expecting scope: AgendaSelection? = nil)
    async throws -> CalendarQueryResponse
  {
    let iso = ISO8601DateFormatter()
    let request = AgendaQueryRequest(
      startUtc: iso.string(from: start), endUtc: iso.string(from: end),
      expectedScope: scope?.nativeScope)
    let result: AgendaQueryResult
    do {
      result = try await queryCalendarEvents(request: request)
    } catch AppError.StaleRevision {
      throw CalendarQueryFailure.selectionChanged
    } catch AppError.Cancelled {
      throw CancellationError()
    }
    let actual = AgendaSelection(result.scope)
    guard result.startUtc == request.startUtc, result.endUtc == request.endUtc,
      scope == nil || scope == actual
    else { throw CalendarQueryFailure.invalidResponse }
    return CalendarQueryResponse(
      scope: actual, events: try result.events.map(CalendarEvent.init),
      unavailableCalendarIDs: result.unavailableCalendarIds,
      unavailableEvents: result.unavailableEvents.map {
        UnavailableCalendarEvent(id: $0.id, start: $0.startUtc, end: $0.endUtc)
      })
  }
}
