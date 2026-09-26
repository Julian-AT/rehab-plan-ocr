import Foundation

// This is the entire public App Group payload. Photos, notes, therapists and
// calendar identifiers belong exclusively to the application's private store.
public struct AgendaEvent: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var start: Double
  public var end: Double
  public var timezone: String
  public var title: String
  public var room: String
  public var status: String = "current"
  public var owned: Bool? = nil
  public var startDate: Date { Date(timeIntervalSince1970: start) }
  public var endDate: Date { Date(timeIntervalSince1970: end) }
  public var url: URL {
    URL(string: owned == false ? "reha-calendar://today" : "reha-calendar://event/\(id)")!
  }
  public func isRunning(at date: Date) -> Bool { startDate <= date && date < endDate }
}

public struct AgendaSnapshot: Codable, Equatable, Sendable {
  public static let version = 1
  public static let group = "group.at.rehakalender.personal"
  public static let filename = "agenda-v1.json"
  public static let widgetKind = "RehaAgenda"
  public var schemaVersion = version
  public var updatedAt: Double
  public var access: String
  public var events: [AgendaEvent]
  public var deletedIDs: [String] = []

  public static func empty(access: String = "empty", now: Date = Date()) -> Self {
    Self(updatedAt: now.timeIntervalSince1970, access: access, events: [])
  }
  public func state(at date: Date) -> String {
    if access == "unavailable" { return "unavailable" }
    if date.timeIntervalSince1970 - updatedAt > 24 * 3600 { return "stale" }
    return access
  }
  public func upcoming(at date: Date) -> [AgendaEvent] {
    events.filter { $0.endDate > date }.sorted {
      if $0.start == $1.start { return $0.id < $1.id }
      return $0.start < $1.start
    }
  }
  public func presentation(at date: Date, calendar: Calendar = .current) -> AgendaPresentation {
    AgendaPresentation(
      next: upcoming(at: date).first, today: allToday(at: date, calendar: calendar),
      stale: state(at: date) == "stale")
  }
  public func allToday(at date: Date, calendar: Calendar = .current) -> [AgendaEvent] {
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    return events.filter { $0.startDate < end && $0.endDate > start }
      .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
  }
  public func today(at date: Date, calendar: Calendar = .current) -> [AgendaEvent] {
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    return upcoming(at: date).filter { $0.startDate < end && $0.endDate > start }
  }
  // Calendar arithmetic, not 86400-second days: this includes DST transitions.
  public func boundaries(after now: Date, calendar: Calendar = .current) -> [Date] {
    let horizon = calendar.date(byAdding: .day, value: 2, to: now)!
    var dates = Set<Date>([now])
    for event in events {
      for date in [event.startDate, event.endDate] where date > now && date <= horizon {
        dates.insert(date)
      }
    }
    for offset in 1...2 {
      dates.insert(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!)
    }
    let staleAt = Date(timeIntervalSince1970: updatedAt + 24 * 3600 + 1)
    if staleAt > now && staleAt <= horizon { dates.insert(staleAt) }
    return dates.sorted()
  }
  public static func read(from root: URL?) -> Self {
    guard let root else { return .empty(access: "unavailable") }
    do {
      let data = try Data(contentsOf: root.appendingPathComponent(filename))
      let snapshot = try JSONDecoder().decode(Self.self, from: data)
      guard snapshot.schemaVersion == version else { return .empty(access: "unavailable") }
      return snapshot
    } catch { return .empty(access: "unavailable") }
  }
}

// Shared consumer decisions for SwiftUI and the Tauri iOS shell. This is returned
// only to the app, and does not change the restricted App Group snapshot schema.
public struct AgendaPresentation: Codable, Sendable {
  public var next: AgendaEvent?
  public var today: [AgendaEvent]
  public var stale: Bool
}

public enum AgendaFormat {
  public static func time(_ event: AgendaEvent) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_AT")
    formatter.timeZone = TimeZone(identifier: event.timezone) ?? .current
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: event.startDate)
  }
  public static func room(_ event: AgendaEvent) -> String {
    event.room.isEmpty ? "Raum nicht angegeben" : event.room
  }
}

public struct ReminderPreferences: Codable, Equatable, Sendable {
  public var enabled = false
  public var minutes: Int? = 10
  public var sound = true
  public var preview = true
}

struct AlarmJournalEntry: Codable {
  // Write-ahead phases allow replay after termination between EventKit and UN.
  var phase: String = "calendar"
  var expectedMinutes: Int?
  var approvedMinutes: Int?
  var restoreMinutes: Int?
  var signature: String?
  var fireAt: Double?
}

enum ReminderPolicy {
  static let limit = 60
  static let allowedMinutes = [5, 10, 15, 30, 60]
  static func selected(_ events: [AgendaEvent], now: Date, preferences: ReminderPreferences) -> Set<
    String
  > {
    guard preferences.enabled, let minutes = preferences.minutes else { return [] }
    return Set(
      events.filter { $0.start - Double(minutes * 60) > now.timeIntervalSince1970 + 1 }
        .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        .prefix(limit).map(\.id))
  }
  static func canSnooze(start: Date, now: Date) -> Bool {
    now.addingTimeInterval(5 * 60) < start
  }
}
