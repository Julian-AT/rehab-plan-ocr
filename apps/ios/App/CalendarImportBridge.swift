import AppleServices
import Foundation
import RehaCore

extension NativeBridge {
  static func importValues(_ value: EventValues) -> NativeImportValues {
    NativeImportValues(
      title: value.title, startUTC: value.startUtc, endUTC: value.endUtc,
      timezone: value.timezone, location: value.location, notes: value.notes,
      reminderMinutes: value.reminderMinutes.map(Int.init))
  }
  static func approvedValues(_ value: NativeImportValues) throws -> EventValues {
    try EventValues(
      title: value.title, startUtc: value.startUTC, endUtc: value.endUTC,
      timezone: value.timezone, location: value.location, notes: value.notes,
      reminderMinutes: value.unsignedReminderMinutes)
  }
  static func nativeRecord(_ record: ImportRecord) -> NativeCalendarRecord {
    nativeRecord(
      id: record.id, calendarID: record.calendarId, externalID: record.externalId,
      status: record.status, values: record.approved)
  }
  private static func nativeRecord(
    id: String, calendarID: String, externalID: String?, status: String, values: EventValues
  ) -> NativeCalendarRecord {
    NativeCalendarRecord(
      id: id, calendarID: calendarID, externalID: externalID, status: status,
      title: values.title, startUTC: values.startUtc, endUTC: values.endUtc,
      timezone: values.timezone, location: values.location, notes: values.notes,
      reminderMinutes: values.reminderMinutes.map(Int.init))
  }
  func snapshot(records: [ImportRecord]) throws -> LiveCalendar {
    do {
      let result = try NativeServiceCall.waitValue(for: .snapshot) { completion in
        NativeServices.shared.importSnapshot(records.map(Self.nativeRecord), completion: completion)
      }
      return try LiveCalendar(
        current: result.current.mapValues(Self.approvedValues), protectedIds: result.protectedIDs)
    } catch { throw Self.appError(error) }
  }
  func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
    let kind: NativeImportKind =
      switch operation.kind {
      case .create: .create
      case .update: .update
      case .remove: .remove
      default: .unsupported
      }
    let request = NativeImportOperation(
      kind: kind, id: operation.id, calendarID: operation.calendarId,
      externalID: operation.externalId, before: operation.before.map(Self.importValues),
      after: operation.after.map(Self.importValues),
      requiresResolution: operation.requiresResolution)
    do {
      let result = try NativeServiceCall.waitValue(for: .apply) { completion in
        NativeServices.shared.applyImport(
          request, recoveryOnly: recoveryOnly, completion: completion)
      }
      let status: WriteStatus =
        switch result.status {
        case .saved: .saved
        case .failed: .failed
        case .uncertain: .uncertain
        case .conflict: .conflict
        }
      return CalendarResult(
        id: result.id, status: status, externalId: result.externalID,
        error: result.error, maintenanceWarnings: result.maintenanceWarnings)
    } catch { throw Self.appError(error) }
  }
  func syncAgenda(request: AgendaSyncRequest) throws -> AgendaSyncResult {
    do {
      let result = try NativeServiceCall.waitValue(for: .agenda) { completion in
        NativeServices.shared.synchronizeAgenda(
          records: request.records.map {
            Self.nativeRecord(
              id: $0.id, calendarID: $0.calendarId, externalID: $0.externalId,
              status: $0.status, values: $0.approved)
          },
          preferences: ReminderPreferences(
            enabled: request.preferences.enabled,
            minutes: request.preferences.minutes.map(Int.init),
            sound: request.preferences.sound, preview: request.preferences.preview),
          displayCalendarIDs: request.displayCalendarIds, completion: completion)
      }
      return AgendaSyncResult(
        maintenanceWarnings: result.reminders.error.flatMap { $0.isEmpty ? nil : [$0] } ?? [])
    } catch { throw Self.appError(error) }
  }
  func forgetCalendar() throws {
    do {
      try NativeServiceCall.waitValue(for: .forgetCalendar) { completion in
        NativeServices.shared.forgetCalendar(completion: completion)
      }
    } catch { throw Self.appError(error) }
  }
  func overlaps(events: [String: EventValues], exclude: [String]) throws -> [CalendarOverlap] {
    do {
      let overlaps = try NativeServiceCall.waitValue(for: .overlaps) { completion in
        NativeServices.shared.importOverlaps(
          events: events.mapValues(Self.importValues), exclude: exclude, completion: completion)
      }
      return overlaps.map {
        CalendarOverlap(
          appointmentId: $0.appointmentID, externalId: $0.externalID, title: $0.title,
          startUtc: $0.startUTC, endUtc: $0.endUTC)
      }
    } catch { throw Self.appError(error) }
  }
}
