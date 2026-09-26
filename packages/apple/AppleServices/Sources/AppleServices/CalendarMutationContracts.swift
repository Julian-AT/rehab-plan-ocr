import CoreFoundation
import Foundation

public enum NativeEventMutationKind: String, Sendable { case create, update, remove }
public enum NativeEventReminderChange: Sendable, Equatable {
  case unchanged, disabled
  case minutes(UInt32)
}
public struct NativeEventEditPatch: Sendable {
  public var title: String?
  public var startUTC: String?
  public var endUTC: String?
  public var timezone: String?
  public var location: String?
  public var reminder: NativeEventReminderChange
  public init(
    title: String?, startUTC: String?, endUTC: String?, timezone: String?, location: String?,
    reminder: NativeEventReminderChange
  ) {
    self.title = title
    self.startUTC = startUTC
    self.endUTC = endUTC
    self.timezone = timezone
    self.location = location
    self.reminder = reminder
  }
  var changesReminder: Bool { reminder != .unchanged }
  var reminderMinutes: Int? {
    if case .minutes(let minutes) = reminder { Int(minutes) } else { nil }
  }
  var journalValue: [String: Any] {
    var result: [String: Any] = [:]
    if let title { result["title"] = title }
    if let startUTC { result["start_utc"] = startUTC }
    if let endUTC { result["end_utc"] = endUTC }
    if let timezone { result["timezone"] = timezone }
    if let location { result["location"] = location }
    switch reminder {
    case .unchanged: break
    case .disabled: result["reminder_minutes"] = NSNull()
    case .minutes(let value): result["reminder_minutes"] = value
    }
    return result
  }
  init(journal: [String: Any]) throws {
    let keys: Set<String> = [
      "title", "start_utc", "end_utc", "timezone", "location", "reminder_minutes",
    ]
    guard Set(journal.keys).isSubset(of: keys) else {
      throw NativeServiceError.invalidInput("Nicht unterstützte Terminänderung.")
    }
    func text(_ key: String) throws -> String? {
      guard let value = journal[key] else { return nil }
      guard let value = value as? String else {
        throw NativeServiceError.invalidInput("Termintext ungültig.")
      }
      return value
    }
    let reminder: NativeEventReminderChange
    if let value = journal["reminder_minutes"] {
      if value is NSNull {
        reminder = .disabled
      } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
        number.doubleValue.isFinite,
        number.doubleValue.rounded() == number.doubleValue, (0...10080).contains(number.doubleValue)
      {
        reminder = .minutes(number.uint32Value)
      } else {
        throw NativeServiceError.invalidInput("Erinnerung ungültig.")
      }
    } else {
      reminder = .unchanged
    }
    self.init(
      title: try text("title"), startUTC: try text("start_utc"), endUTC: try text("end_utc"),
      timezone: try text("timezone"), location: try text("location"), reminder: reminder)
  }
}
public struct NativeEventEditProposal: Sendable {
  public var token: String
  public var session: String
  public var revision: UInt64
  public var expiresAt: Int64
  public var kind: NativeEventMutationKind
  public var calendarID: String
  public var calendarTitle: String
  public var before: NativeCalendarEvent?
  public var patch: NativeEventEditPatch
  public var undoOf: String?
  public var ownedID: String?
  public var origin: String
  public init(
    token: String, session: String, revision: UInt64, expiresAt: Int64,
    kind: NativeEventMutationKind,
    calendarID: String, calendarTitle: String, before: NativeCalendarEvent?,
    patch: NativeEventEditPatch,
    undoOf: String?, ownedID: String?, origin: String
  ) {
    self.token = token
    self.session = session
    self.revision = revision
    self.expiresAt = expiresAt
    self.kind = kind
    self.calendarID = calendarID
    self.calendarTitle = calendarTitle
    self.before = before
    self.patch = patch
    self.undoOf = undoOf
    self.ownedID = ownedID
    self.origin = origin
  }
  var journalValue: [String: Any] {
    get throws {
      [
        "token": token, "session": session, "revision": revision, "expires_at": expiresAt,
        "kind": kind.rawValue, "calendar_id": calendarID, "calendar_title": calendarTitle,
        "before": try before.map { try $0.legacyValue } ?? NSNull() as Any,
        "patch": patch.journalValue,
        "undo_of": undoOf ?? NSNull() as Any, "owned_id": ownedID ?? NSNull() as Any,
        "origin": origin,
      ]
    }
  }
  init(journal p: [String: Any]) throws {
    guard let token = p["token"] as? String, let rawKind = p["kind"] as? String,
      let kind = NativeEventMutationKind(rawValue: rawKind),
      let calendar = p["calendar_id"] as? String,
      let patch = p["patch"] as? [String: Any]
    else { throw NativeServiceError.invalidInput("Auftrag unvollständig.") }
    self.init(
      token: token, session: p["session"] as? String ?? "",
      revision: (p["revision"] as? NSNumber)?.uint64Value ?? 0,
      expiresAt: (p["expires_at"] as? NSNumber)?.int64Value ?? 0, kind: kind, calendarID: calendar,
      calendarTitle: p["calendar_title"] as? String ?? "",
      before: try (p["before"] as? [String: Any]).map(NativeCalendarEvent.init(snapshot:)),
      patch: try NativeEventEditPatch(journal: patch), undoOf: p["undo_of"] as? String,
      ownedID: p["owned_id"] as? String,
      origin: p["origin"] as? String ?? "unknown")
  }
}
public struct NativeEventMutationRequest: Sendable {
  public var proposal: NativeEventEditProposal
  public var recoveryOnly: Bool
  public init(proposal: NativeEventEditProposal, recoveryOnly: Bool) {
    self.proposal = proposal
    self.recoveryOnly = recoveryOnly
  }
  init(legacy args: [String: Any]) throws {
    guard let p = args["proposal"] as? [String: Any] else {
      throw NativeServiceError.invalidInput("Auftrag unvollständig.")
    }
    self.init(
      proposal: try NativeEventEditProposal(journal: p),
      recoveryOnly: args["recovery_only"] as? Bool ?? false)
  }
}
public enum NativeEventMutationStatus: String, Sendable {
  case saved, failed, uncertain, conflict, acknowledged
}
public struct NativeEventMutationResult: Sendable {
  public var status: NativeEventMutationStatus
  public var event: NativeCalendarEvent?
  public var operationID: String?
  public var message: String?
  public var maintenanceWarnings: [String]
  public init(
    status: NativeEventMutationStatus, event: NativeCalendarEvent? = nil,
    operationID: String? = nil,
    message: String? = nil, maintenanceWarnings: [String] = []
  ) {
    self.status = status
    self.event = event
    self.operationID = operationID
    self.message = message
    self.maintenanceWarnings = maintenanceWarnings
  }
  var journalValue: [String: Any] {
    get throws {
      var value: [String: Any] = ["status": status.rawValue]
      if status == .saved || event != nil {
        value["event"] = try event.map { try $0.legacyValue } ?? NSNull() as Any
      }
      if let operationID { value["operation_id"] = operationID }
      if let message { value["message"] = message }
      if !maintenanceWarnings.isEmpty { value["maintenance_warnings"] = maintenanceWarnings }
      return value
    }
  }
  init(journal: [String: Any]) throws {
    guard
      let status = (journal["status"] as? String).flatMap(NativeEventMutationStatus.init(rawValue:))
    else {
      throw NativeServiceError.storage("Unbekannter Schreibstatus.")
    }
    self.init(
      status: status,
      event: try (journal["event"] as? [String: Any]).map(NativeCalendarEvent.init(snapshot:)),
      operationID: journal["operation_id"] as? String, message: journal["message"] as? String,
      maintenanceWarnings: journal["maintenance_warnings"] as? [String] ?? [])
  }
}
public struct NativeEventCalendarDestination: Sendable {
  public let id: String
  public let title: String
  public let source: String
  public let writable: Bool
  public let colorComponents: [Double]?
  public init(id: String, title: String, source: String, writable: Bool, colorComponents: [Double]?)
  {
    self.id = id
    self.title = title
    self.source = source
    self.writable = writable
    self.colorComponents = colorComponents
  }
  var legacyValue: [String: Any] {
    var result: [String: Any] = ["id": id, "title": title, "source": source, "writable": writable]
    if let colorComponents { result["color_components"] = colorComponents }
    return result
  }
}
