import EventKit
import Foundation
import RehaCore

@MainActor struct NativeAgendaSource: AgendaDataSource {
  let core: NativeApplication
  var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

  func selection() async throws -> AgendaSelection {
    AgendaSelection(try await core.agendaSelection())
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
    return try await core.calendarEvents(from: week.start, to: week.end, expecting: scope)
  }
}
