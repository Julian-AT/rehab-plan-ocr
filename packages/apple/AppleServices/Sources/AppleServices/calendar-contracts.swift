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
    // Compact import approvals cannot display or restore these external fields.
    // Manual/voice editing uses the full metadata snapshot and preserves them.
    // EventKit also represents plain location text as a structured location.
    // Only the additional geometry is outside the approved import values.
    requiresSystemEditor(event) || event.hasRecurrenceRules || event.isDetached
      || protectsImportMetadata(
        allDay: event.isAllDay,
        locationGeometry: event.structuredLocation?.geoLocation != nil
          || (event.structuredLocation?.radius ?? 0) != 0,
        availability: event.availability)
  }
  static func protectsImportMetadata(
    allDay: Bool, locationGeometry: Bool, availability: EKEventAvailability
  ) -> Bool {
    allDay || locationGeometry || ![EKEventAvailability.busy, .notSupported].contains(availability)
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
