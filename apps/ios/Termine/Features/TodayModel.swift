import Foundation
import Observation

struct AgendaSelection {
  let calendarIDs: Set<String>
}

@MainActor protocol AgendaDataSource {
  var hasAccess: Bool { get }
  func selection() async throws -> AgendaSelection
  func synchronize() async throws
  func events(in week: AgendaWeek) async throws -> CalendarQueryResponse
}

/// Retain complete week snapshots while refreshing. Freshness and request identity
/// are separate: a cancelled prefetch cannot overwrite a later request or reset.
@MainActor @Observable final class TodayModel {
  enum Availability { case loading, ready, noAccess, noSelection, failed }
  private struct Snapshot {
    let response: CalendarQueryResponse
    let epoch: UUID
  }
  private var cache: [Date: Snapshot] = [:]
  private var recentWeeks: [Date] = []
  private var epoch = UUID()
  private var requestID = UUID()
  private var refreshKey: String?
  private var synchronizedEpoch: UUID?
  private var calendarIDs: Set<String>?
  private var calendar = Calendar.current
  private let describe: (Error) -> String
  private(set) var availability: Availability = .loading
  private(set) var error: String?
  private(set) var isRefreshing = false
  private(set) var unavailableCalendars = Set<String>()

  init(describe: @escaping (Error) -> String = { $0.localizedDescription }) {
    self.describe = describe
  }

  func events(on date: Date) -> [CalendarEvent]? {
    cache[AgendaWeek(containing: date, calendar: calendar).start]?.response.events
  }

  func hasKnownGap(on date: Date) -> Bool {
    cache[AgendaWeek(containing: date, calendar: calendar).start]?
      .response.unavailableEvents?.contains { $0.overlaps(date, calendar: calendar) } == true
  }

  /// Used for changed display selection, local erasure and civil-time changes.
  func invalidate() {
    requestID = UUID()
    epoch = UUID()
    refreshKey = nil
    calendarIDs = nil
    clearSnapshots()
    availability = .loading
    isRefreshing = false
    error = nil
  }

  func refresh(
    using source: any AgendaDataSource, week: AgendaWeek, visibleWeek: Date, key: String,
    calendar: Calendar = .current
  ) async {
    guard !Task.isCancelled else { return }
    if self.calendar != calendar {
      invalidate()
      self.calendar = calendar
    }
    let request = UUID()
    requestID = request
    guard accept(request, source: source) else { return }
    if key != refreshKey {
      refreshKey = key
      epoch = UUID()
    }
    isRefreshing = true
    error = nil
    availability = events(on: week.start) == nil ? .loading : .ready
    defer { if requestID == request { isRefreshing = false } }

    var seen = Set<Date>()
    let weeks =
      ([week.start, visibleWeek]
      + [week.start, visibleWeek].flatMap { center in
        [-7, 7].map { calendar.date(byAdding: .day, value: $0, to: center)! }
      }).map { AgendaWeek(containing: $0, calendar: calendar) }.filter {
        seen.insert($0.start).inserted
      }
    // A bounded in-memory cache also keeps recently visited, more distant weeks.
    for item in weeks.reversed() { touch(item.start) }
    do {
      let selection = try await source.selection()
      guard accept(request, source: source) else { return }
      if calendarIDs != selection.calendarIDs {
        clearSnapshots()
        calendarIDs = selection.calendarIDs
        epoch = UUID()
        availability = .loading
      }
      guard !selection.calendarIDs.isEmpty else {
        clearSnapshots()
        availability = .noSelection
        return
      }
      if synchronizedEpoch != epoch {
        try await source.synchronize()
        guard accept(request, source: source) else { return }
        synchronizedEpoch = epoch
      }
      updateUnavailable(weeks)
      for item in weeks where cache[item.start]?.epoch != epoch {
        let result = try await source.events(in: item)
        guard accept(request, source: source) else { return }
        cache[item.start] = Snapshot(response: result, epoch: epoch)
        touch(item.start)
        while cache.count > 12,
          let oldest = recentWeeks.first(where: { !seen.contains($0) })
        {
          cache.removeValue(forKey: oldest)
          recentWeeks.removeAll { $0 == oldest }
        }
        updateUnavailable(weeks)
        availability = .ready
      }
    } catch {
      guard accept(request, source: source) else { return }
      self.error = describe(error)
      availability = .failed
    }
  }

  private func accept(_ request: UUID, source: any AgendaDataSource) -> Bool {
    guard requestID == request, !Task.isCancelled else { return false }
    guard source.hasAccess else {
      clearSnapshots()
      availability = .noAccess
      error = nil
      isRefreshing = false
      return false
    }
    return true
  }

  private func touch(_ date: Date) {
    guard cache[date] != nil else { return }
    recentWeeks.removeAll { $0 == date }
    recentWeeks.append(date)
  }

  private func updateUnavailable(_ weeks: [AgendaWeek]) {
    unavailableCalendars = Set(
      weeks.flatMap {
        cache[$0.start]?.response.unavailableCalendarIDs ?? []
      })
  }

  private func clearSnapshots() {
    cache = [:]
    recentWeeks = []
    unavailableCalendars = []
  }
}
