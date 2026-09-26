import CoreLocation
import CryptoKit
import EventKit
import EventKitUI
import Foundation
import UIKit

/// Shares the existing EventKit store and serial owner. This path never grants
/// ownership to an external event and never replaces its URL with an app marker.
// Mutable state and EventKit objects stay on agenda.queue. The system editor
// has a separate main-actor store and receives only immutable occurrence identity.
final class EventEditingService: @unchecked Sendable {
  static let shared = EventEditingService()
  private let agenda: AgendaService
  private var store: EKEventStore { agenda.store }
  private var queue: DispatchQueue { agenda.queue }
  private let iso = ISO8601DateFormatter()
  private let isForeground: @Sendable () -> Bool
  init(
    isForeground: @escaping @Sendable () -> Bool = {
      DispatchQueue.main.sync { UIApplication.shared.applicationState == .active }
    }, agenda: AgendaService = .shared
  ) {
    self.agenda = agenda
    self.isForeground = isForeground
  }
  private func fail(_ message: String) -> Error { AgendaError.message(message) }
  func perform(_ command: String, _ request: ServiceRequest) {
    queue.async {
      do {
        if command == "resolveOwnedEvent" {
          let args =
            try JSONSerialization.jsonObject(with: request.argumentsData) as? [String: Any] ?? [:]
          let record = try JSONDecoder().decode(
            OwnedRecord.self, from: JSONSerialization.data(withJSONObject: args["record"] ?? [:]))
          switch self.agenda.lookup(record) {
          case .found(let event):
            var current = self.snapshot(event)
            current["import_id"] = record.id
            request.resolve(["status": "found", "event": current])
          case .deleted: request.resolve(["status": "deleted"])
          case .unavailable: request.resolve(["status": "unavailable"])
          }
          return
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
          throw self.fail("Kalenderzugriff fehlt.")
        }
        let args =
          try JSONSerialization.jsonObject(with: request.argumentsData) as? [String: Any] ?? [:]
        switch command {
        case "inspectCalendarLinks": request.resolve(try self.inspectLinks(args))
        case "eventCalendars": request.resolve(["calendars": self.calendars()])
        case "queryEvents": request.resolve(try self.query(args))
        case "getEvent":
          request.resolve([
            "event": try self.find(args["event"] as? [String: Any] ?? [:]).map(self.snapshot)
              ?? NSNull()
          ])
        case "mutateEvent": request.resolve(try self.mutate(args))
        case "editSystemEvent":
          guard let event = try self.find(args["event"] as? [String: Any] ?? [:]) else {
            throw self.fail("Termin nicht verfügbar. Im Kalender nach Name und Datum suchen.")
          }
          let reference = SystemEventReference(
            calendarID: event.calendar.calendarIdentifier,
            externalID: event.eventIdentifier ?? event.calendarItemIdentifier,
            occurrence: event.occurrenceDate ?? event.startDate, start: event.startDate)
          DispatchQueue.main.async { SystemEventEditor.shared.open(reference, request: request) }
        default: throw self.fail("Unbekannte Kalenderfunktion.")
        }
      } catch { request.reject(error.localizedDescription) }
    }
  }
  func forget() throws {
    let directory = try AppStorage.prepare().appendingPathComponent(
      "event-receipts", isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
  func calendars() -> [[String: Any]] {
    store.calendars(for: .event).map { c in
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 1
      if let color = c.cgColor {
        UIColor(cgColor: color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      }
      return [
        "id": c.calendarIdentifier, "title": c.title, "source": c.source.title,
        "writable": c.allowsContentModifications,
        "color_components": [Double(red), Double(green), Double(blue)],
      ]
    }
  }
  /// Explicit repair searches committed events by the app's exact ownership
  /// marker. A matching title or time is never sufficient to adopt an event.
  private func inspectLinks(_ args: [String: Any]) throws -> [String: Any] {
    store.refreshSourcesIfNecessary()
    let records = try JSONDecoder().decode(
      [OwnedRecord].self,
      from: JSONSerialization.data(withJSONObject: args["records"] ?? []))
    let readable = store.calendars(for: .event)
    var results: [[String: Any]] = []
    for record in records {
      let marker = "reha-calendar://event/\(record.id)"
      var candidate: EKEvent?
      if case .found(let event) = agenda.lookup(record) { candidate = event }
      var ambiguous = false
      if candidate == nil, let date = iso.date(from: record.approved.start_utc), !readable.isEmpty {
        let matches = store.events(
          matching: store.predicateForEvents(
            withStart: date.addingTimeInterval(-366 * 86400),
            end: date.addingTimeInterval(366 * 86400), calendars: readable)
        ).filter { $0.url?.absoluteString == marker }
        if matches.count == 1 { candidate = matches[0] }
        ambiguous = matches.count > 1
      }
      if let candidate {
        results.append(["id": record.id, "status": "found", "event": snapshot(candidate)])
      } else {
        let missing = !readable.contains { $0.calendarIdentifier == record.calendar_id }
        let reason = ambiguous ? "ambiguous" : missing ? "calendar_missing" : "event_missing"
        results.append(["id": record.id, "status": "unavailable", "reason": reason])
      }
    }
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      throw fail("Kalenderzugriff fehlt. Bitte erneut prüfen.")
    }
    return ["access": "fullAccess", "calendars": calendars(), "results": results]
  }

  private func query(_ args: [String: Any]) throws -> [String: Any] {
    guard let ids = args["calendar_ids"] as? [String],
      let from = args["start_utc"] as? String, let to = args["end_utc"] as? String,
      let start = iso.date(from: from), let end = iso.date(from: to), end > start,
      end.timeIntervalSince(start) <= 367 * 86400
    else { throw fail("Suchzeitraum fehlt.") }

    let selectedIDs = Set(ids)
    let calendars = ids.compactMap { store.calendar(withIdentifier: $0) }
    var unavailable = selectedIDs.subtracting(calendars.map(\.calendarIdentifier))
    var found =
      calendars.isEmpty
      ? []
      : store.events(
        matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
    var imports: [String: String] = [:]
    var unavailableEvents: [[String: Any]] = []
    for record in args["records"] as? [[String: Any]] ?? [] {
      guard let external = record["external_id"] as? String, let id = record["id"] as? String else {
        continue
      }
      _ = external
      let owned = try JSONDecoder().decode(
        OwnedRecord.self, from: JSONSerialization.data(withJSONObject: record))
      let event: EKEvent
      switch agenda.lookup(owned) {
      case .found(let found): event = found
      case .deleted: continue
      case .unavailable:
        guard selectedIDs.contains(owned.calendar_id) else { continue }
        unavailable.insert(owned.calendar_id)
        unavailableEvents.append([
          "id": owned.id, "start_utc": owned.approved.start_utc,
          "end_utc": owned.approved.end_utc,
        ])
        continue
      }
      guard selectedIDs.contains(event.calendar.calendarIdentifier),
        event.url?.absoluteString == "reha-calendar://event/\(id)", event.startDate < end,
        event.endDate > start
      else { continue }
      imports[snapshot(event)["id"] as! String] = id
      found.append(event)
    }
    var unique: [String: [String: Any]] = [:]
    for event in found {
      var value = snapshot(event)
      let id = value["id"] as! String
      if let importID = imports[id] { value["import_id"] = importID }
      unique[id] = value
    }
    return [
      "unavailable_calendar_ids": unavailable.sorted(),
      "unavailable_events": unavailableEvents,
      "events": unique.values.sorted {
        (($0["values"] as? [String: Any])?["start_utc"] as? String ?? "")
          < (($1["values"] as? [String: Any])?["start_utc"] as? String ?? "")
      },
    ]
  }
  private func location(_ value: EKStructuredLocation?) -> Any {
    guard let value else { return NSNull() }
    var result: [String: Any] = ["title": value.title ?? "", "radius": value.radius]
    if let geo = value.geoLocation {
      result["latitude"] = geo.coordinate.latitude
      result["longitude"] = geo.coordinate.longitude
    }
    return result
  }
  private func restoreLocation(_ data: Any?) -> EKStructuredLocation? {
    guard let d = data as? [String: Any] else { return nil }
    let value = EKStructuredLocation(title: d["title"] as? String ?? "")
    value.radius = d["radius"] as? Double ?? 0
    if let lat = d["latitude"] as? Double, let lon = d["longitude"] as? Double {
      value.geoLocation = CLLocation(latitude: lat, longitude: lon)
    }
    return value
  }
  private func alarms(_ event: EKEvent) -> [[String: Any]] {
    (event.alarms ?? []).map {
      [
        "relative": $0.relativeOffset,
        "absolute": $0.absoluteDate.map { iso.string(from: $0) } ?? NSNull() as Any,
        "location": location($0.structuredLocation), "proximity": $0.proximity.rawValue,
      ]
    }
  }
  private func restoreAlarms(_ data: Any?) -> [EKAlarm] {
    (data as? [[String: Any]] ?? []).map { d in
      let alarm: EKAlarm
      if let date = (d["absolute"] as? String).flatMap(iso.date) {
        alarm = EKAlarm(absoluteDate: date)
      } else {
        alarm = EKAlarm(relativeOffset: d["relative"] as? Double ?? 0)
      }
      alarm.structuredLocation = restoreLocation(d["location"])
      alarm.proximity = EKAlarmProximity(rawValue: d["proximity"] as? Int ?? 0) ?? .none
      return alarm
    }
  }
  private func recurrence(_ rule: EKRecurrenceRule) -> [String: Any] {
    [
      "calendar": rule.calendarIdentifier, "frequency": rule.frequency.rawValue,
      "interval": rule.interval,
      "first_weekday": rule.firstDayOfTheWeek,
      "weekdays": rule.daysOfTheWeek?.map {
        ["day": $0.dayOfTheWeek.rawValue, "week": $0.weekNumber]
      } ?? [],
      "month_days": rule.daysOfTheMonth ?? [], "year_days": rule.daysOfTheYear ?? [],
      "year_weeks": rule.weeksOfTheYear ?? [], "months": rule.monthsOfTheYear ?? [],
      "positions": rule.setPositions ?? [],
      "end": rule.recurrenceEnd?.endDate.map { iso.string(from: $0) } ?? NSNull() as Any,
      "count": rule.recurrenceEnd?.occurrenceCount ?? 0,
    ]
  }
  private func snapshot(_ event: EKEvent) -> [String: Any] {
    let occurrence = event.occurrenceDate ?? event.startDate!
    let firstReminder = event.alarms?.first(where: {
      $0.absoluteDate == nil && $0.structuredLocation == nil && $0.relativeOffset <= 0
    }).map { Int(-$0.relativeOffset / 60) }
    let logicalReminder = agenda.logicalReminder(for: event, actual: firstReminder)
    let values: [String: Any] = [
      "title": event.title ?? "", "start_utc": iso.string(from: event.startDate),
      "end_utc": iso.string(from: event.endDate),
      "timezone": event.timeZone?.identifier ?? TimeZone.current.identifier,
      "location": event.location ?? "",
      "reminder_minutes": logicalReminder.map { $0 as Any } ?? NSNull(),
    ]
    let managedAlarm = agenda.comparisonAlarmEntry(for: event)
    let comparisonAlarms: [[String: Any]] =
      managedAlarm.map { entry in
        entry.approvedMinutes.map {
          [
            [
              "relative": -Double($0) * 60, "absolute": NSNull(), "location": NSNull(),
              "proximity": 0,
            ]
          ]
        } ?? []
      } ?? alarms(event)
    let metadata: [String: Any] = [
      "notes": event.notes ?? NSNull() as Any, "url": event.url?.absoluteString ?? NSNull() as Any,
      "alarms": comparisonAlarms, "structured_location": location(event.structuredLocation),
      "all_day": event.isAllDay,
      "availability": event.availability.rawValue,
      "timezone": event.timeZone?.identifier ?? NSNull() as Any,
      "recurrence": event.recurrenceRules?.map(recurrence) ?? [], "detached": event.isDetached,
      "modified": managedAlarm == nil
        ? event.lastModifiedDate.map { iso.string(from: $0) } ?? "" : "",
      "attendees": event.attendees?.map {
        $0.url.absoluteString + ":\($0.participantStatus.rawValue)"
      } ?? [],
      "organizer": event.organizer?.url.absoluteString ?? "", "status": event.status.rawValue,
    ]
    let bytes =
      (try? JSONSerialization.data(
        withJSONObject: ["values": values, "metadata": metadata], options: [.sortedKeys])) ?? Data()
    let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let external = event.eventIdentifier ?? event.calendarItemIdentifier
    return [
      "id": "\(event.calendar.calendarIdentifier)|\(external)|\(iso.string(from: occurrence))",
      "external_id": external,
      "calendar_id": event.calendar.calendarIdentifier, "calendar_title": event.calendar.title,
      "source": event.calendar.source.title,
      "occurrence": iso.string(from: occurrence),
      "recurring": event.hasRecurrenceRules || event.isDetached,
      "system_only": event.hasAttendees || event.organizer != nil
        || event.birthdayContactIdentifier != nil,
      "writable": event.calendar.allowsContentModifications, "values": values, "metadata": metadata,
      "fingerprint": fingerprint,
    ]
  }
  private func find(_ ref: [String: Any]) throws -> EKEvent? {
    guard let calendarID = ref["calendar_id"] as? String,
      let calendar = store.calendar(withIdentifier: calendarID),
      let external = ref["external_id"] as? String, let occurrence = ref["occurrence"] as? String,
      let date = iso.date(from: occurrence)
    else { throw fail("Kalender oder Terminzuordnung fehlt.") }
    let expectedStart =
      ((ref["values"] as? [String: Any])?["start_utc"] as? String).flatMap(iso.date) ?? date
    // For recurring instances event(withIdentifier:) may return the series master.
    // Resolve through a bounded predicate and require the exact occurrence.
    let candidates = store.events(
      matching: store.predicateForEvents(
        withStart: expectedStart.addingTimeInterval(-86400),
        end: expectedStart.addingTimeInterval(2 * 86400), calendars: [calendar])
    )
    .filter {
      ($0.eventIdentifier == external || $0.calendarItemIdentifier == external)
        && iso.string(from: $0.occurrenceDate ?? $0.startDate) == occurrence
    }
    if candidates.count > 1 {
      throw fail("Mehrere Serienvorkommen passen. Im Systemkalender öffnen.")
    }
    return candidates.first
  }
  private func receiptURL(_ id: String) throws -> URL {
    guard UUID(uuidString: id) != nil else { throw fail("Auftragskennung ungültig.") }
    let root = try AppStorage.prepare().appendingPathComponent("event-receipts", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent(id + ".json")
  }
  private func receipt(_ id: String) throws -> [String: Any]? {
    let url = try receiptURL(id)
    if !FileManager.default.fileExists(atPath: url.path) { return nil }
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
  }
  private func persist(_ value: [String: Any], id: String) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(
      to: receiptURL(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  private func mutate(_ args: [String: Any]) throws -> [String: Any] {
    guard let p = args["proposal"] as? [String: Any], let token = p["token"] as? String,
      let kind = p["kind"] as? String,
      let calendarID = p["calendar_id"] as? String, let patch = p["patch"] as? [String: Any]
    else { throw fail("Auftrag unvollständig.") }
    if let saved = try receipt(token) {
      return saved["result"] as? [String: Any] ?? [
        "status": "uncertain", "message": "Schreibstatus unklar. Nicht erneut ausgeführt.",
      ]
    }
    if args["recovery_only"] as? Bool == true {
      return ["status": "failed", "message": "Auftrag hat EventKit nicht erreicht."]
    }
    guard let calendar = store.calendar(withIdentifier: calendarID),
      calendar.allowsContentModifications,
      ["create", "update", "remove"].contains(kind)
    else { throw fail("Kalender nicht beschreibbar.") }
    let before = p["before"] as? [String: Any]
    let existing = try before.flatMap(find)
    if kind != "create" {
      guard let existing, let before,
        NSDictionary(dictionary: snapshot(existing)).isEqual(to: before), !existing.hasAttendees,
        existing.organizer == nil
      else {
        return ["status": "conflict", "message": "Termin geändert. Neue Vorschau erforderlich."]
      }
    }
    var oldReceipt: [String: Any]?
    if let undoID = p["undo_of"] as? String {
      oldReceipt = try receipt(undoID)
      guard (oldReceipt?["result"] as? [String: Any])?["status"] as? String == "saved" else {
        throw fail("Wiederherstellungsdaten fehlen.")
      }
    }
    let event = existing ?? EKEvent(eventStore: store)
    let alarmState = try existing.flatMap { try agenda.editingAlarmState($0) }
    if kind == "create" {
      event.calendar = calendar
      if let id = p["owned_id"] as? String {
        guard UUID(uuidString: id) != nil else { throw fail("Ungültige Terminzuordnung.") }
        event.url = URL(string: "reha-calendar://event/\(id)")
      }
    }
    if kind != "remove" {
      if let title = patch["title"] as? String { event.title = title }
      if let start = patch["start_utc"] as? String {
        guard let date = iso.date(from: start) else { throw fail("Beginn ungültig.") }
        event.startDate = date
      }
      if let end = patch["end_utc"] as? String {
        guard let date = iso.date(from: end) else { throw fail("Ende ungültig.") }
        event.endDate = date
      }
      if let zone = patch["timezone"] as? String { event.timeZone = TimeZone(identifier: zone) }
      if let place = patch["location"] as? String { event.location = place }
      if let reminder = patch["reminder_minutes"] {
        // Modify one ordinary relative reminder; unrelated alarms survive.
        var retained = event.alarms ?? []
        if let index = retained.firstIndex(where: {
          $0.absoluteDate == nil && $0.structuredLocation == nil && $0.relativeOffset <= 0
        }) {
          retained.remove(at: index)
        }
        if let minutes = reminder as? Int {
          retained.insert(EKAlarm(relativeOffset: -Double(minutes) * 60), at: 0)
        }
        event.alarms = retained
      }
      if let old = oldReceipt?["proposal"] as? [String: Any],
        let original = old["before"] as? [String: Any],
        let metadata = original["metadata"] as? [String: Any]
      {
        if kind == "create" {
          event.notes = metadata["notes"] as? String
          event.url = (metadata["url"] as? String).flatMap(URL.init(string:))
          event.isAllDay = metadata["all_day"] as? Bool ?? false
          event.availability =
            EKEventAvailability(rawValue: metadata["availability"] as? Int ?? -1) ?? .notSupported
          event.timeZone = (metadata["timezone"] as? String).flatMap(TimeZone.init(identifier:))
        }
        if kind == "create" || patch["location"] != nil {
          event.structuredLocation = restoreLocation(metadata["structured_location"])
        }
        if kind == "create" || patch["reminder_minutes"] != nil {
          event.alarms = restoreAlarms(metadata["alarms"])
        }
      }
      guard let start = event.startDate, let end = event.endDate, end > start else {
        throw fail("Terminzeit ungültig.")
      }
    }
    // A durable native receipt narrows the crash window. An unfinished receipt
    // remains uncertain; absence of an event is never proof of a deletion.
    let active = isForeground()
    guard active else {
      return ["status": "failed", "message": "Freigabe durch Unterbrechung verfallen."]
    }
    try persist(["proposal": p, "alarm_journal": alarmState ?? NSNull() as Any], id: token)
    do {
      if kind == "remove" {
        try store.remove(event, span: .thisEvent, commit: true)
      } else {
        try store.save(event, span: .thisEvent, commit: true)
      }
      if kind != "remove", patch["reminder_minutes"] != nil {
        if let id = p["owned_id"] as? String,
          event.url?.absoluteString == "reha-calendar://event/\(id)"
        {
          try agenda.approvedAlarmChanged(id: id, minutes: patch["reminder_minutes"] as? Int)
        } else {
          try agenda.manuallyEditedAlarm(
            event, restoring: oldReceipt?["alarm_journal"] as? [String: Any])
        }
      }
      var savedEvent: Any = NSNull()
      if kind != "remove" {
        // EventKit may finalize detached-instance metadata during commit. Journal
        // the persisted occurrence rather than the object's pre-commit cache.
        let written = snapshot(event)
        guard let persisted = try find(written) else {
          throw fail("Gespeicherter Termin kann noch nicht gelesen werden.")
        }
        let checked = snapshot(persisted)
        guard
          NSDictionary(dictionary: written["values"] as? [String: Any] ?? [:]).isEqual(
            to: checked["values"] as? [String: Any] ?? [:])
        else {
          throw fail("Termin wurde während des Speicherns erneut geändert.")
        }
        savedEvent = checked
      }
      let result: [String: Any] = ["status": "saved", "event": savedEvent, "operation_id": token]
      try persist(
        ["proposal": p, "result": result, "alarm_journal": alarmState ?? NSNull() as Any], id: token
      )
      return result
    } catch {
      return ["status": "uncertain", "message": "Schreibstatus unklar. Kalender abgleichen."]
    }
  }
}

private struct SystemEventReference: Sendable {
  let calendarID: String
  let externalID: String
  let occurrence: Date
  let start: Date
}

@MainActor private final class SystemEventEditor: NSObject, @MainActor EKEventEditViewDelegate {
  static let shared = SystemEventEditor()
  private var editorRequest: ServiceRequest?
  func open(_ reference: SystemEventReference, request: ServiceRequest) {
    guard editorRequest == nil else {
      request.reject("Kalenderbearbeitung bereits geöffnet.")
      return
    }
    var root = UIApplication.shared.connectedScenes.compactMap {
      ($0 as? UIWindowScene)?.keyWindow?.rootViewController
    }.first
    while let shown = root?.presentedViewController { root = shown }
    guard let root else {
      request.reject("Systemkalender nicht erreichbar. Terminname und Datum im Kalender suchen.")
      return
    }
    let store = EKEventStore()
    guard let calendar = store.calendar(withIdentifier: reference.calendarID) else {
      request.reject("Kalender nicht verfügbar.")
      return
    }
    let candidates = store.events(
      matching: store.predicateForEvents(
        withStart: reference.start.addingTimeInterval(-86400),
        end: reference.start.addingTimeInterval(2 * 86400), calendars: [calendar])
    )
    .filter {
      ($0.eventIdentifier == reference.externalID
        || $0.calendarItemIdentifier == reference.externalID)
        && ($0.occurrenceDate ?? $0.startDate) == reference.occurrence
    }
    guard candidates.count == 1, let event = candidates.first else {
      request.reject("Termin nicht eindeutig verfügbar. Kalenderansicht aktualisieren.")
      return
    }
    editorRequest = request
    let editor = EKEventEditViewController()
    editor.eventStore = store
    editor.event = event
    editor.editViewDelegate = self
    root.present(editor, animated: true)
  }
  func eventEditViewController(
    _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
    editorRequest?.resolve(["reload": true])
    editorRequest = nil
  }
}
