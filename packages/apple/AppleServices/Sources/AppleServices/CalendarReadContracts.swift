import Foundation

/// Immutable read values cross queues directly. Only metadata keeps its journal JSON.
public struct NativeCalendarQuery: Sendable {
  public var calendarIDs: [String]
  public var startUTC: String
  public var endUTC: String
  public var timezone: String
  public var selectionRevision: UInt64
  public var records: [NativeCalendarRecord]
  public init(
    calendarIDs: [String], startUTC: String, endUTC: String, timezone: String,
    selectionRevision: UInt64, records: [NativeCalendarRecord]
  ) {
    self.calendarIDs = calendarIDs
    self.startUTC = startUTC
    self.endUTC = endUTC
    self.timezone = timezone
    self.selectionRevision = selectionRevision
    self.records = records
  }
}
public struct NativeCalendarRecord: Sendable {
  public var id: String
  public var calendarID: String
  public var externalID: String?
  public var status: String
  public var title: String
  public var startUTC: String
  public var endUTC: String
  public var timezone: String
  public var location: String
  public var notes: String
  public var reminderMinutes: Int?
  public init(
    id: String, calendarID: String, externalID: String?, status: String, title: String,
    startUTC: String, endUTC: String, timezone: String, location: String, notes: String,
    reminderMinutes: Int?
  ) {
    self.id = id
    self.calendarID = calendarID
    self.externalID = externalID
    self.status = status
    self.title = title
    self.startUTC = startUTC
    self.endUTC = endUTC
    self.timezone = timezone
    self.location = location
    self.notes = notes
    self.reminderMinutes = reminderMinutes
  }
}
public struct NativeCalendarReference: Sendable {
  public var calendarID: String
  public var externalID: String
  public var occurrence: String
  public var expectedStartUTC: String
  public init(calendarID: String, externalID: String, occurrence: String, expectedStartUTC: String)
  {
    self.calendarID = calendarID
    self.externalID = externalID
    self.occurrence = occurrence
    self.expectedStartUTC = expectedStartUTC
  }
}
public struct NativeCalendarValues: Sendable {
  public var title: String
  public var startUTC: String
  public var endUTC: String
  public var timezone: String
  public var location: String
  public var reminderMinutes: Int64?
  public init(
    title: String, startUTC: String, endUTC: String, timezone: String, location: String,
    reminderMinutes: Int64?
  ) {
    self.title = title
    self.startUTC = startUTC
    self.endUTC = endUTC
    self.timezone = timezone
    self.location = location
    self.reminderMinutes = reminderMinutes
  }
}
public struct NativeCalendarEvent: Sendable {
  public var id: String
  public var externalID: String
  public var calendarID: String
  public var calendarTitle: String
  public var source: String
  public var occurrence: String
  public var recurring: Bool
  public var systemOnly: Bool
  public var writable: Bool
  public var values: NativeCalendarValues
  public var metadataJSON: String
  public var fingerprint: String
  public var importID: String?
  public init(
    id: String, externalID: String, calendarID: String, calendarTitle: String, source: String,
    occurrence: String, recurring: Bool, systemOnly: Bool, writable: Bool,
    values: NativeCalendarValues, metadataJSON: String, fingerprint: String, importID: String?
  ) {
    self.id = id
    self.externalID = externalID
    self.calendarID = calendarID
    self.calendarTitle = calendarTitle
    self.source = source
    self.occurrence = occurrence
    self.recurring = recurring
    self.systemOnly = systemOnly
    self.writable = writable
    self.values = values
    self.metadataJSON = metadataJSON
    self.fingerprint = fingerprint
    self.importID = importID
  }
}
public struct NativeCalendarUnavailableEvent: Sendable {
  public var id: String
  public var startUTC: String
  public var endUTC: String
  public init(id: String, startUTC: String, endUTC: String) {
    self.id = id
    self.startUTC = startUTC
    self.endUTC = endUTC
  }
}
public struct NativeCalendarReadResult: Sendable {
  public var events: [NativeCalendarEvent]
  public var unavailableCalendarIDs: [String]
  public var unavailableEvents: [NativeCalendarUnavailableEvent]
  public init(
    events: [NativeCalendarEvent], unavailableCalendarIDs: [String],
    unavailableEvents: [NativeCalendarUnavailableEvent]
  ) {
    self.events = events
    self.unavailableCalendarIDs = unavailableCalendarIDs
    self.unavailableEvents = unavailableEvents
  }
}

extension NativeCalendarRecord {
  var ownedRecord: OwnedRecord {
    OwnedRecord(
      status: status, id: id, calendar_id: calendarID, external_id: externalID,
      approved: Values(
        title: title, start_utc: startUTC, end_utc: endUTC, timezone: timezone,
        location: location, notes: notes, reminder_minutes: reminderMinutes))
  }
  init(_ record: OwnedRecord) {
    self.init(
      id: record.id, calendarID: record.calendar_id, externalID: record.external_id,
      status: record.status, title: record.approved.title, startUTC: record.approved.start_utc,
      endUTC: record.approved.end_utc, timezone: record.approved.timezone,
      location: record.approved.location, notes: record.approved.notes,
      reminderMinutes: record.approved.reminder_minutes)
  }
}
extension NativeCalendarQuery {
  /// Existing service/probe adapter only. NativeBridge calls the typed method.
  init(legacy args: [String: Any]) throws {
    guard let ids = args["calendar_ids"] as? [String],
      let start = args["start_utc"] as? String, let end = args["end_utc"] as? String
    else { throw NativeServiceError.invalidInput("Kalenderabfrage unvollständig.") }
    let records = try JSONDecoder().decode(
      [OwnedRecord].self,
      from: JSONSerialization.data(withJSONObject: args["records"] ?? []))
    self.init(
      calendarIDs: ids, startUTC: start, endUTC: end,
      timezone: args["timezone"] as? String ?? TimeZone.current.identifier,
      selectionRevision: (args["selection_revision"] as? NSNumber)?.uint64Value ?? 0,
      records: records.map(NativeCalendarRecord.init))
  }
}
extension NativeCalendarReference {
  init(legacy value: [String: Any]) throws {
    guard let calendar = value["calendar_id"] as? String,
      let external = value["external_id"] as? String,
      let occurrence = value["occurrence"] as? String
    else { throw NativeServiceError.invalidInput("Kalender oder Terminzuordnung fehlt.") }
    self.init(
      calendarID: calendar, externalID: external, occurrence: occurrence,
      expectedStartUTC: (value["values"] as? [String: Any])?["start_utc"] as? String ?? occurrence)
  }
}
extension NativeCalendarEvent {
  /// The existing EventKit snapshot also supplies durable comparisons and undo.
  /// Keep that metadata/fingerprint contract byte-for-byte while typing reads.
  init(snapshot: [String: Any]) throws {
    func string(_ object: [String: Any], _ key: String) throws -> String {
      guard let value = object[key] as? String else {
        throw NativeServiceError.storage("Kalenderantwort unvollständig.")
      }
      return value
    }
    guard let values = snapshot["values"] as? [String: Any],
      let recurring = snapshot["recurring"] as? Bool,
      let systemOnly = snapshot["system_only"] as? Bool,
      let writable = snapshot["writable"] as? Bool,
      let metadata = snapshot["metadata"] as? [String: Any]
    else { throw NativeServiceError.storage("Kalenderantwort unvollständig.") }
    self.init(
      id: try string(snapshot, "id"), externalID: try string(snapshot, "external_id"),
      calendarID: try string(snapshot, "calendar_id"),
      calendarTitle: try string(snapshot, "calendar_title"),
      source: try string(snapshot, "source"), occurrence: try string(snapshot, "occurrence"),
      recurring: recurring, systemOnly: systemOnly, writable: writable,
      values: NativeCalendarValues(
        title: try string(values, "title"),
        startUTC: try string(values, "start_utc"), endUTC: try string(values, "end_utc"),
        timezone: try string(values, "timezone"), location: try string(values, "location"),
        reminderMinutes: (values["reminder_minutes"] as? NSNumber)?.int64Value),
      metadataJSON: String(
        decoding: try JSONSerialization.data(withJSONObject: metadata, options: .sortedKeys),
        as: UTF8.self),
      fingerprint: try string(snapshot, "fingerprint"), importID: snapshot["import_id"] as? String)
  }
  var legacyValue: [String: Any] {
    get throws {
      var result: [String: Any] = [
        "id": id, "external_id": externalID, "calendar_id": calendarID,
        "calendar_title": calendarTitle,
        "source": source, "occurrence": occurrence, "recurring": recurring,
        "system_only": systemOnly,
        "writable": writable, "fingerprint": fingerprint,
        "values": [
          "title": values.title, "start_utc": values.startUTC, "end_utc": values.endUTC,
          "timezone": values.timezone, "location": values.location,
          "reminder_minutes": values.reminderMinutes.map { $0 as Any } ?? NSNull(),
        ],
        "metadata": try JSONSerialization.jsonObject(with: Data(metadataJSON.utf8)),
      ]
      if let importID { result["import_id"] = importID }
      return result
    }
  }
}
extension NativeCalendarReadResult {
  var legacyValue: [String: Any] {
    get throws {
      [
        "events": try events.map { try $0.legacyValue },
        "unavailable_calendar_ids": unavailableCalendarIDs,
        "unavailable_events": unavailableEvents.map {
          ["id": $0.id, "start_utc": $0.startUTC, "end_utc": $0.endUTC]
        },
      ]
    }
  }
}
