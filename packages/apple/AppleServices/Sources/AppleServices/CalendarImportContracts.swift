import Foundation

public struct NativeImportValues: Sendable, Equatable {
  public let title: String
  public let startUTC: String
  public let endUTC: String
  public let timezone: String
  public let location: String
  public let notes: String
  public let reminderMinutes: Int?

  public init(
    title: String, startUTC: String, endUTC: String, timezone: String,
    location: String, notes: String, reminderMinutes: Int?
  ) {
    self.title = title
    self.startUTC = startUTC
    self.endUTC = endUTC
    self.timezone = timezone
    self.location = location
    self.notes = notes
    self.reminderMinutes = reminderMinutes
  }
  init(_ value: Values) {
    self.init(
      title: value.title, startUTC: value.start_utc, endUTC: value.end_utc,
      timezone: value.timezone, location: value.location, notes: value.notes,
      reminderMinutes: value.reminder_minutes)
  }
  /// The existing import FFI stores unsigned minutes. Reject an unrepresentable
  /// external alarm instead of wrapping it into a different reminder value.
  public var unsignedReminderMinutes: UInt32? {
    get throws {
      guard let reminderMinutes else { return nil }
      guard let value = UInt32(exactly: reminderMinutes) else {
        throw NativeServiceError.storage("Kalendererinnerung kann nicht sicher dargestellt werden.")
      }
      return value
    }
  }
  var legacyValue: [String: Any] {
    [
      "title": title, "start_utc": startUTC, "end_utc": endUTC, "timezone": timezone,
      "location": location, "notes": notes,
      "reminder_minutes": reminderMinutes.map { $0 as Any } ?? NSNull(),
    ]
  }
}

public enum NativeImportKind: String, Sendable {
  case create, update, remove
  /// A non-writing proposal must never become a native write operation.
  case unsupported
}

public struct NativeImportOperation: Sendable {
  public let kind: NativeImportKind
  public let id: String
  public let calendarID: String
  public let externalID: String?
  public let before: NativeImportValues?
  public let after: NativeImportValues?
  public let requiresResolution: Bool

  public init(
    kind: NativeImportKind, id: String, calendarID: String, externalID: String?,
    before: NativeImportValues?, after: NativeImportValues?, requiresResolution: Bool
  ) {
    self.kind = kind
    self.id = id
    self.calendarID = calendarID
    self.externalID = externalID
    self.before = before
    self.after = after
    self.requiresResolution = requiresResolution
  }
}

public enum NativeImportWriteStatus: String, Sendable {
  case saved, failed, uncertain, conflict
}

public struct NativeImportWriteResult: Sendable {
  public let id: String
  public let status: NativeImportWriteStatus
  public let externalID: String?
  public let error: String?
  public let maintenanceWarnings: [String]

  var legacyValue: [String: Any] {
    var result: [String: Any] = ["id": id, "status": status.rawValue]
    if let externalID { result["external_id"] = externalID }
    if let error { result["error"] = error }
    if !maintenanceWarnings.isEmpty { result["maintenance_warnings"] = maintenanceWarnings }
    return result
  }
}

public struct NativeImportSnapshot: Sendable {
  public let current: [String: NativeImportValues]
  public let protectedIDs: [String]

  var legacyValue: [String: Any] {
    ["current": current.mapValues(\.legacyValue), "protected_ids": protectedIDs]
  }
}

public struct NativeImportOverlap: Sendable {
  public let appointmentID: String
  public let externalID: String
  public let title: String
  public let startUTC: String
  public let endUTC: String

  var legacyValue: [String: String] {
    [
      "appointment_id": appointmentID, "external_id": externalID, "title": title,
      "start_utc": startUTC, "end_utc": endUTC,
    ]
  }
}
