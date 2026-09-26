import Foundation
import RehaCore

/// The UI and deterministic flow tests use the same typed mutation boundary.
@MainActor struct EventMutationClient {
  let register: @MainActor @Sendable () async throws -> String
  let invalidate: @MainActor @Sendable (String) async -> Void
  let preview: @MainActor @Sendable (EventPreviewRequest) async throws -> EventPreviewResult
  let confirm: @MainActor @Sendable (EventConfirmRequest) async throws -> EventMutationResult
  let undo: @MainActor @Sendable (EventUndoRequest) async throws -> EventPreviewResult
}
extension EventEditPatch {
  static var empty: Self {
    Self(title: nil, startUtc: nil, endUtc: nil, timezone: nil, location: nil, reminder: .unchanged)
  }
  /// Only the speech planner's field edits use this adapter; the calendar
  /// request itself always crosses the typed boundary.
  init(editingFields fields: [String: JSONValue]) throws {
    self = .empty
    for (key, value) in fields {
      switch (key, value) {
      case ("title", .string(let v)): title = v
      case ("start_utc", .string(let v)): startUtc = v
      case ("end_utc", .string(let v)): endUtc = v
      case ("timezone", .string(let v)): timezone = v
      case ("location", .string(let v)): location = v
      case ("reminder_minutes", .null): reminder = .disabled
      case ("reminder_minutes", .number(let v))
      where v.isFinite && v.rounded() == v && (0...10080).contains(v):
        reminder = .minutes(minutes: UInt32(v))
      default: throw AppError.Validation(message: "Nicht unterstützte Terminänderung.")
      }
    }
  }
  var displayFields: [String: JSONValue] {
    var fields: [String: JSONValue] = [:]
    if let title { fields["title"] = .string(title) }
    if let startUtc { fields["start_utc"] = .string(startUtc) }
    if let endUtc { fields["end_utc"] = .string(endUtc) }
    if let timezone { fields["timezone"] = .string(timezone) }
    if let location { fields["location"] = .string(location) }
    switch reminder {
    case .unchanged: break
    case .disabled: fields["reminder_minutes"] = .null
    case .minutes(let minutes): fields["reminder_minutes"] = .number(Double(minutes))
    }
    return fields
  }
}
extension EventMutationKind {
  var journalName: String {
    switch self {
    case .create: "create"
    case .update: "update"
    case .remove: "remove"
    }
  }
}
extension CalendarEvent {
  init(_ event: CalendarReadEvent) throws {
    self.init(
      id: event.id, external_id: event.externalId, calendar_id: event.calendarId,
      calendar_title: event.calendarTitle, source: event.source, occurrence: event.occurrence,
      recurring: event.recurring, system_only: event.systemOnly, writable: event.writable,
      values: CalendarEventValues(
        title: event.values.title, start_utc: event.values.startUtc,
        end_utc: event.values.endUtc, timezone: event.values.timezone,
        location: event.values.location,
        reminder_minutes: event.values.reminderMinutes.map(Int.init)),
      metadata: try JSONDecoder().decode(JSONValue.self, from: Data(event.metadataJson.utf8)),
      fingerprint: event.fingerprint, import_id: event.importId)
  }
  var nativeReadEvent: CalendarReadEvent {
    get throws {
      CalendarReadEvent(
        id: id, externalId: external_id, calendarId: calendar_id, calendarTitle: calendar_title,
        source: source, occurrence: occurrence, recurring: recurring, systemOnly: system_only,
        writable: writable,
        values: CalendarReadValues(
          title: values.title, startUtc: values.start_utc, endUtc: values.end_utc,
          timezone: values.timezone, location: values.location,
          reminderMinutes: values.reminder_minutes.map(Int64.init)),
        metadataJson: String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self),
        fingerprint: fingerprint, importId: import_id)
    }
  }
}
extension EventProposalView {
  init(_ proposal: EventEditProposal) throws {
    self.init(
      token: proposal.token, session: proposal.session, revision: proposal.revision,
      kind: proposal.kind.journalName, calendar_id: proposal.calendarId,
      calendar_title: proposal.calendarTitle,
      before: try proposal.before.map(CalendarEvent.init), patch: proposal.patch.displayFields,
      undo_of: proposal.undoOf)
  }
}
