import EventKit
import UIKit

/// Called only on the plugin's serial calendar queue, after full access is granted.
final class DedicatedCalendar {
  static let title = "Laßnitzhöhe"
  private let defaults: UserDefaults
  private let key = "reha-calendar.destination"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func forget() {
    defaults.removeObject(forKey: key)
  }

  func resolve(in store: EKEventStore) throws -> EKCalendar {
    let saved = defaults.dictionary(forKey: key) as? [String: String]
    if let id = saved?["id"], let calendar = store.calendar(withIdentifier: id) {
      guard calendar.allowsContentModifications else {
        throw Failure.message("Der gespeicherte Kalender ist schreibgeschützt. Wähle einen beschreibbaren Kalender.")
      }
      try renameOwnedDefault(calendar, saved: saved, in: store)
      remember(calendar)
      return calendar
    }

    // Identifiers can change during account sync. Match cached name/account only
    // when unambiguous; never create another calendar while the saved one is absent.
    let matches = store.calendars(for: .event).filter { calendar in
      guard calendar.title == (saved?["title"] ?? Self.title) else { return false }
      guard let saved else { return true }
      return calendar.source.sourceIdentifier == saved["source_id"]
        || (calendar.source.title == saved["source_title"]
          && String(calendar.source.sourceType.rawValue) == saved["source_type"])
    }
    if matches.count == 1, let calendar = matches.first, calendar.allowsContentModifications {
      remember(calendar)
      return calendar
    }
    guard matches.isEmpty, saved == nil else {
      throw Failure.message(
        "The saved calendar is unavailable, read-only or ambiguous. Check its account in Apple Calendar, or select a writable calendar below."
      )
    }

    let eligible = store.sources.filter { $0.sourceType == .local || $0.sourceType == .calDAV }
    let preferred = store.defaultCalendarForNewEvents?.source
    let source =
      eligible.first { $0.sourceIdentifier == preferred?.sourceIdentifier }
      ?? eligible.first { $0.sourceType == .local }
      ?? (eligible.count == 1 ? eligible.first : nil)
    guard let source else {
      throw Failure.message(
        "Erstelle in Apple Kalender einen Kalender namens Laßnitzhöhe und versuche es erneut. Kein eindeutiger Account unterstützt die Kalendererstellung."
      )
    }

    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = Self.title
    calendar.source = source
    calendar.cgColor = UIColor(red: 0.12, green: 0.48, blue: 0.58, alpha: 1).cgColor
    try store.saveCalendar(calendar, commit: true)
    remember(calendar)
    return calendar
  }

  private func renameOwnedDefault(_ calendar: EKCalendar, saved: [String: String]?, in store: EKEventStore) throws {
    // A persisted destination is evidence of app setup. Preserve any user rename.
    guard saved?["id"] == calendar.calendarIdentifier,
          saved?["title"] == "Reha Calendar", calendar.title == "Reha Calendar" else { return }
    calendar.title = Self.title
    try store.saveCalendar(calendar, commit: true)
  }

  private func remember(_ calendar: EKCalendar) {
    defaults.set(
      [
        "id": calendar.calendarIdentifier,
        "title": calendar.title ?? Self.title,
        "source_id": calendar.source.sourceIdentifier,
        "source_title": calendar.source.title,
        "source_type": String(calendar.source.sourceType.rawValue),
      ], forKey: key)
  }

  private enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? {
      switch self {
      case .message(let value): return value
      }
    }
  }
}
