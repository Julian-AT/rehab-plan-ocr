import Foundation

/// Transaction boundaries shared by the actual EventKit/UN implementation and
/// fault-injection tests. Every callback may fail; the durable phase always says
/// what must be reconciled on the next launch.
enum ReminderTransfer {
  struct IO {
    var journal: (AlarmJournalEntry) throws -> Void
    var addNotification: () throws -> Void
    var notificationConfirmed: () throws -> Bool
    var removeCalendarAlarm: () throws -> Void
    var restoreCalendarAlarm: (Int?) throws -> Void
    var cancelNotification: () -> Void
  }
  static func handoff(
    entry original: AlarmJournalEntry, signature: String, fireAt: Double,
    reserveMinutes: Int, io: IO
  ) throws -> AlarmJournalEntry {
    var entry = original
    entry.phase = "scheduling"
    entry.signature = signature
    entry.fireAt = fireAt
    try io.journal(entry)
    do {
      if try !io.notificationConfirmed() { try io.addNotification() }
      guard try io.notificationConfirmed() else {
        throw TransferError.notConfirmed
      }
      try io.removeCalendarAlarm()
      entry.phase = "app"
      entry.expectedMinutes = reserveMinutes
      try io.journal(entry)
      return entry
    } catch {
      // Do not discard the request before a durable calendar reserve exists.
      _ = try restore(entry: entry, minutes: reserveMinutes, io: io)
      throw error
    }
  }
  static func restore(entry original: AlarmJournalEntry, minutes: Int?, io: IO) throws
    -> AlarmJournalEntry
  {
    var entry = original
    entry.phase = "restoring"
    entry.restoreMinutes = minutes
    try io.journal(entry)
    try io.restoreCalendarAlarm(minutes)
    entry.phase = "calendar"
    entry.expectedMinutes = minutes
    entry.restoreMinutes = nil
    entry.signature = nil
    entry.fireAt = nil
    try io.journal(entry)
    io.cancelNotification()
    return entry
  }
  enum TransferError: Error { case notConfirmed }
}

struct CalendarAlarmDescriptor {
  var relativeOffset: Double
  var absolute: Bool = false
  var location: Bool = false
  var proximity: Bool = false
}
enum AlarmOwnership {
  static func journalEntry(for url: URL?, in journal: [String: AlarmJournalEntry])
    -> AlarmJournalEntry?
  {
    guard let url, let id = url.pathComponents.last,
      url.absoluteString == "reha-calendar://event/\(id)"
    else { return nil }
    return journal[id]
  }
  static func matches(_ alarms: [CalendarAlarmDescriptor], minutes: Int?) -> Bool {
    guard let minutes else { return alarms.isEmpty }
    guard alarms.count == 1, let alarm = alarms.first else { return false }
    return !alarm.absolute && !alarm.location && !alarm.proximity
      && abs(alarm.relativeOffset + Double(minutes * 60)) < 0.01
  }
  static func manageable(
    _ alarms: [CalendarAlarmDescriptor], recurring: Bool, writable: Bool,
    entry: AlarmJournalEntry
  ) -> Bool {
    guard !recurring, writable, entry.phase != "protected" else { return false }
    switch entry.phase {
    case "app": return alarms.isEmpty
    case "scheduling": return alarms.isEmpty || matches(alarms, minutes: entry.expectedMinutes)
    case "restoring":
      return alarms.isEmpty || matches(alarms, minutes: entry.expectedMinutes)
        || matches(alarms, minutes: entry.restoreMinutes)
    default: return matches(alarms, minutes: entry.expectedMinutes)
    }
  }
}
