import EventKit
import Foundation
import RehaCore

@MainActor struct NativeAgendaSource: AgendaDataSource {
  let core: NativeApplication
  var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

  func selection() async throws -> AgendaSelection {
    struct Ownership: Decodable {
      struct Record: Decodable { let id: String }
      let records: [Record]
    }
    let owned = try await core.eventRequest("ownedEventRecords", [:], as: Ownership.self)
    let preferences = try await core.preferences()
    return AgendaSelection(
      calendarIDs: Set(preferences.displayCalendarIds), hasOwnedEvents: !owned.records.isEmpty)
  }

  func synchronize() async throws {
    _ = try await core.calendarRequest(command: "refreshAgenda", arguments: "{}")
  }

  func events(in week: AgendaWeek) async throws -> CalendarQueryResponse {
    #if DEBUG && targetEnvironment(simulator)
      // Make refresh flicker observable in UI tests without changing returned data.
      if ProcessInfo.processInfo.arguments.contains("--preview-agenda-delay") {
        try await Task.sleep(for: .seconds(3))
      }
    #endif
    let iso = ISO8601DateFormatter()
    return try await core.eventRequest(
      "queryCalendarEvents",
      ["start_utc": iso.string(from: week.start), "end_utc": iso.string(from: week.end)],
      as: CalendarQueryResponse.self)
  }
}
