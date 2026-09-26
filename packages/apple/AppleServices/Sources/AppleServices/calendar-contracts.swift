import EventKit
import Foundation

enum CalendarMaintenance {
  static let alarmWarning =
    "Der Termin ist gespeichert. Die Erinnerungen konnten noch nicht aktualisiert werden."
}

enum CalendarEventProtection {
  static func requiresSystemEditor(_ event: EKEvent) -> Bool {
    event.hasAttendees || event.organizer != nil || event.birthdayContactIdentifier != nil
  }
  static func protectsImport(_ event: EKEvent) -> Bool {
    requiresSystemEditor(event) || event.hasRecurrenceRules || event.isDetached
  }
}

struct Values: Codable, Equatable {
  var title: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var start_utc: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var end_utc: String
  var timezone: String
  var location: String
  var notes: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var reminder_minutes: Int?
}
struct OwnedRecord: Codable {
  let status: String
  let id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let external_id: String?
  let approved: Values
}
