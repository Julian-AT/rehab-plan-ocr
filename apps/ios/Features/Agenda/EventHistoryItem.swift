import Foundation
import RehaCore

/// Display projection of typed history; no journal writes or JSON transport.
struct EventHistoryItem: Identifiable, Sendable {
  let id: String
  let createdAt: TimeInterval
  let proposal: EventProposalView
  let status: EventHistoryStatus
  let undoneBy: String?

  init(_ record: EventHistoryRecord) throws {
    id = record.id
    createdAt = TimeInterval(record.createdAt)
    proposal = try EventProposalView(record.proposal)
    status = record.status
    undoneBy = record.undoneBy
  }
}

extension CalendarAdministrationStatus {
  var unavailableCount: Int {
    let selected = Set(displayCalendarIds + [calendarId].compactMap { $0 }.filter { !$0.isEmpty })
    return selected.subtracting(platform.calendars.map(\.id)).union(platform.unavailableCalendarIds)
      .count
  }
}
