import EventKit
import Foundation
import RehaCore

@MainActor struct NativeAgendaSource: AgendaDataSource {
  let core: NativeApplication
  var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

  func selection() async throws -> AgendaSelection {
    try await core.eventRequest("agendaSelection", [:], as: AgendaSelection.self)
  }

  func synchronize() async throws {
    _ = try await core.calendarRequest(command: "refreshAgenda", arguments: "{}")
  }

  func events(in week: AgendaWeek, scope: AgendaSelection) async throws -> CalendarQueryResponse {
    #if DEBUG && targetEnvironment(simulator)
      // Make refresh flicker observable in UI tests without changing returned data.
      if ProcessInfo.processInfo.arguments.contains("--preview-agenda-delay") {
        try await Task.sleep(for: .seconds(3))
      }
    #endif
    let iso = ISO8601DateFormatter()
    return try await core.eventRequest(
      "queryCalendarEvents",
      [
        "start_utc": iso.string(from: week.start), "end_utc": iso.string(from: week.end),
        "scope": [
          "calendar_ids": scope.calendarIDs.sorted(), "timezone": scope.timezone,
          "revision": scope.revision,
        ],
      ],
      as: CalendarQueryResponse.self)
  }
}
