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
  private let agenda: AgendaService
  private var store: EKEventStore { agenda.store }
  private var queue: DispatchQueue { agenda.queue }
  private let iso = ISO8601DateFormatter()
  private let isForeground: @Sendable () -> Bool
  private let presentEditor: SystemEventPresentation
  init(
    isForeground: @escaping @Sendable () -> Bool = {
      DispatchQueue.main.sync { UIApplication.shared.applicationState == .active }
    }, agenda: AgendaService = .shared,
    presentEditor: @escaping SystemEventPresentation = { reference, completion in
      SystemEventEditor.shared.open(reference, completion: completion)
    }
  ) {
    self.agenda = agenda
    self.isForeground = isForeground
    self.presentEditor = presentEditor
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
          throw NativeServiceError.permissionDenied
        }
        let args =
          try JSONSerialization.jsonObject(with: request.argumentsData) as? [String: Any] ?? [:]
        switch command {
        case "inspectCalendarLinks": request.resolve(try self.inspectLinks(args))
        case "eventCalendars": request.resolve(["calendars": self.calendars()])
        case "queryEvents":
          request.resolve(try self.query(NativeCalendarQuery(legacy: args)).legacyValue)
        case "getEvent":
          request.resolve([
            "event": try self.find(args["event"] as? [String: Any] ?? [:]).map(self.snapshot)
              ?? NSNull()
          ])
        case "mutateEvent":
          request.resolve(try self.mutate(NativeEventMutationRequest(legacy: args)).journalValue)
        case "editSystemEvent":
          try self.presentSystemEvent(
            NativeCalendarReference(legacy: args["event"] as? [String: Any] ?? [:])
          ) { result in
            switch result {
            case .success: request.resolve(["reload": true])
            case .failure(let error): request.reject(error)
            }
          }
        default: throw self.fail("Unbekannte Kalenderfunktion.")
        }
      } catch { request.reject(error) }
    }
  }
  func forget() throws {
    let directory = try AppStorage.prepare().appendingPathComponent(
      "event-receipts", isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
  func calendars() -> [[String: Any]] { calendarDestinations().map(\.legacyValue) }
  private func calendarDestinations() -> [NativeEventCalendarDestination] {
    store.calendars(for: .event).map { c in
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 1
      if let color = c.cgColor {
        UIColor(cgColor: color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      }
      return NativeEventCalendarDestination(
        id: c.calendarIdentifier, title: c.title,
        source: c.source.title, writable: c.allowsContentModifications,
        colorComponents: [Double(red), Double(green), Double(blue)])
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
      throw NativeServiceError.permissionDenied
    }
    return ["access": "fullAccess", "calendars": calendars(), "results": results]
  }

  func readDestinations(
    completion: @escaping @Sendable (Result<[NativeEventCalendarDestination], Error>) -> Void
  ) {
    queue.async {
      do {
        try self.requireReadAccess()
        let result = self.calendarDestinations()
        try self.requireReadAccess()
        completion(.success(result))
      } catch { completion(.failure(error)) }
    }
  }
  func writeMutation(
    _ request: NativeEventMutationRequest,
    completion: @escaping @Sendable (Result<NativeEventMutationResult, Error>) -> Void
  ) {
    queue.async {
      do {
        try self.requireReadAccess()
        completion(.success(try self.mutate(request)))
      } catch { completion(.failure(error)) }
    }
  }
  func readQuery(
    _ request: NativeCalendarQuery,
    completion: @escaping @Sendable (Result<NativeCalendarReadResult, Error>) -> Void
  ) {
    queue.async {
      do {
        try self.requireReadAccess()
        let result = try self.query(request)
        try self.requireReadAccess()
        completion(.success(result))
      } catch { completion(.failure(error)) }
    }
  }
  func readEvent(
    _ reference: NativeCalendarReference,
    completion: @escaping @Sendable (Result<NativeCalendarEvent?, Error>) -> Void
  ) {
    queue.async {
      do {
        try self.requireReadAccess()
        let event = try self.find(reference).map {
          try NativeCalendarEvent(snapshot: self.snapshot($0))
        }
        try self.requireReadAccess()
        completion(.success(event))
      } catch { completion(.failure(error)) }
    }
  }
  func editSystemEvent(
    _ reference: NativeCalendarReference,
    completion: @escaping @Sendable (Result<NativeSystemEventEditAction, Error>) -> Void
  ) {
    queue.async {
      do { try self.presentSystemEvent(reference, completion: completion) } catch {
        completion(.failure(error))
      }
    }
  }
  private func presentSystemEvent(
    _ reference: NativeCalendarReference,
    completion: @escaping @Sendable (Result<NativeSystemEventEditAction, Error>) -> Void
  ) throws {
    try requireReadAccess()
    guard let event = try find(reference) else {
      throw NativeServiceError.invalidInput(
        "Termin nicht verfügbar. Im Kalender nach Name und Datum suchen.")
    }
    let resolved = SystemEventReference(
      calendarID: event.calendar.calendarIdentifier,
      externalID: event.eventIdentifier ?? event.calendarItemIdentifier,
      occurrence: event.occurrenceDate ?? event.startDate, start: event.startDate)
    try requireReadAccess()
    DispatchQueue.main.async { self.presentEditor(resolved, completion) }
  }
  private func requireReadAccess() throws {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      throw NativeServiceError.permissionDenied
    }
  }
  func query(_ request: NativeCalendarQuery) throws -> NativeCalendarReadResult {
    guard let start = iso.date(from: request.startUTC), let end = iso.date(from: request.endUTC),
      end > start, end.timeIntervalSince(start) <= 366 * 86400,
      TimeZone(identifier: request.timezone) != nil, request.calendarIDs.count <= 100,
      request.calendarIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 })
    else { throw NativeServiceError.invalidInput("Kalenderabfrage ungültig.") }
    let selectedIDs = Set(request.calendarIDs)
    let calendars = request.calendarIDs.compactMap { store.calendar(withIdentifier: $0) }
    var unavailable = selectedIDs.subtracting(calendars.map(\.calendarIdentifier))
    var found =
      calendars.isEmpty
      ? []
      : store.events(
        matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
    var imports: [String: String] = [:]
    var unavailableEvents: [NativeCalendarUnavailableEvent] = []
    for record in request.records where record.externalID != nil {
      let owned = record.ownedRecord
      let event: EKEvent
      switch agenda.lookup(owned) {
      case .found(let found): event = found
      case .deleted: continue
      case .unavailable:
        guard selectedIDs.contains(owned.calendar_id) else { continue }
        unavailable.insert(owned.calendar_id)
        unavailableEvents.append(
          NativeCalendarUnavailableEvent(
            id: owned.id, startUTC: owned.approved.start_utc, endUTC: owned.approved.end_utc))
        continue
      }
      guard selectedIDs.contains(event.calendar.calendarIdentifier),
        event.url?.absoluteString == "reha-calendar://event/\(record.id)",
        event.startDate < end, event.endDate > start
      else { continue }
      let value = try NativeCalendarEvent(snapshot: snapshot(event))
      imports[value.id] = record.id
      found.append(event)
    }
    var unique: [String: NativeCalendarEvent] = [:]
    for event in found {
      var value = try NativeCalendarEvent(snapshot: snapshot(event))
      value.importID = imports[value.id]
      unique[value.id] = value
    }
    return NativeCalendarReadResult(
      events: unique.values.sorted {
        $0.values.startUTC < $1.values.startUTC
      }, unavailableCalendarIDs: unavailable.sorted(), unavailableEvents: unavailableEvents)
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
      "system_only": CalendarEventProtection.requiresSystemEditor(event),
      "writable": event.calendar.allowsContentModifications, "values": values, "metadata": metadata,
      "fingerprint": fingerprint,
    ]
  }
  private func find(_ ref: [String: Any]) throws -> EKEvent? {
    try find(NativeCalendarReference(legacy: ref))
  }
  private func find(_ reference: NativeCalendarReference) throws -> EKEvent? {
    guard !reference.calendarID.isEmpty, !reference.externalID.isEmpty,
      let calendar = store.calendar(withIdentifier: reference.calendarID),
      let date = iso.date(from: reference.occurrence)
    else { throw NativeServiceError.invalidInput("Kalender oder Terminzuordnung fehlt.") }
    let external = reference.externalID
    let occurrence = reference.occurrence
    let expectedStart = iso.date(from: reference.expectedStartUTC) ?? date
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
  private func mutate(_ request: NativeEventMutationRequest) throws -> NativeEventMutationResult {
    let proposal = request.proposal
    let token = proposal.token
    let kind = proposal.kind
    let calendarID = proposal.calendarID
    let patch = proposal.patch
    if let saved = try receipt(token) {
      if let result = saved["result"] as? [String: Any] {
        return try NativeEventMutationResult(journal: result)
      }
      return NativeEventMutationResult(
        status: .uncertain, message: "Schreibstatus unklar. Nicht erneut ausgeführt.")
    }
    if request.recoveryOnly {
      return NativeEventMutationResult(
        status: .failed, message: "Auftrag hat EventKit nicht erreicht.")
    }
    guard let calendar = store.calendar(withIdentifier: calendarID),
      calendar.allowsContentModifications
    else { throw fail("Kalender nicht beschreibbar.") }
    let before = try proposal.before.map { try $0.legacyValue }
    let existing = try before.flatMap(find)
    if kind != .create {
      guard let existing, let before,
        NSDictionary(dictionary: snapshot(existing)).isEqual(to: before),
        !CalendarEventProtection.requiresSystemEditor(existing)
      else {
        return NativeEventMutationResult(
          status: .conflict, message: "Termin geändert. Neue Vorschau erforderlich.")
      }
    }
    var oldReceipt: [String: Any]?
    if let undoID = proposal.undoOf {
      oldReceipt = try receipt(undoID)
      guard (oldReceipt?["result"] as? [String: Any])?["status"] as? String == "saved" else {
        throw fail("Wiederherstellungsdaten fehlen.")
      }
    }
    let event = existing ?? EKEvent(eventStore: store)
    let alarmState = try existing.flatMap { try agenda.editingAlarmState($0) }
    if kind == .create {
      event.calendar = calendar
      if let id = proposal.ownedID {
        guard UUID(uuidString: id) != nil else { throw fail("Ungültige Terminzuordnung.") }
        event.url = URL(string: "reha-calendar://event/\(id)")
      }
    }
    if kind != .remove {
      if let title = patch.title { event.title = title }
      if let start = patch.startUTC {
        guard let date = iso.date(from: start) else { throw fail("Beginn ungültig.") }
        event.startDate = date
      }
      if let end = patch.endUTC {
        guard let date = iso.date(from: end) else { throw fail("Ende ungültig.") }
        event.endDate = date
      }
      if let zone = patch.timezone { event.timeZone = TimeZone(identifier: zone) }
      if let place = patch.location { event.location = place }
      if patch.changesReminder {
        // Modify one ordinary relative reminder; unrelated alarms survive.
        var retained = event.alarms ?? []
        if let index = retained.firstIndex(where: {
          $0.absoluteDate == nil && $0.structuredLocation == nil && $0.relativeOffset <= 0
        }) {
          retained.remove(at: index)
        }
        if let minutes = patch.reminderMinutes {
          retained.insert(EKAlarm(relativeOffset: -Double(minutes) * 60), at: 0)
        }
        event.alarms = retained
      }
      if let old = oldReceipt?["proposal"] as? [String: Any],
        let original = old["before"] as? [String: Any],
        let metadata = original["metadata"] as? [String: Any]
      {
        if kind == .create {
          event.notes = metadata["notes"] as? String
          event.url = (metadata["url"] as? String).flatMap(URL.init(string:))
          event.isAllDay = metadata["all_day"] as? Bool ?? false
          event.availability =
            EKEventAvailability(rawValue: metadata["availability"] as? Int ?? -1) ?? .notSupported
          event.timeZone = (metadata["timezone"] as? String).flatMap(TimeZone.init(identifier:))
        }
        if kind == .create || patch.location != nil {
          event.structuredLocation = restoreLocation(metadata["structured_location"])
        }
        if kind == .create || patch.changesReminder {
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
      return NativeEventMutationResult(
        status: .failed, message: "Freigabe durch Unterbrechung verfallen.")
    }
    try persist(
      ["proposal": proposal.journalValue, "alarm_journal": alarmState ?? NSNull() as Any], id: token
    )
    do {
      if kind == .remove {
        try store.remove(event, span: .thisEvent, commit: true)
      } else {
        try store.save(event, span: .thisEvent, commit: true)
      }
      // EventKit has committed. Alarm bookkeeping is independent; preserve its
      // logical snapshot normalization while keeping failures out of write status.
      var warnings: [String] = []
      if kind != .remove, patch.changesReminder {
        do {
          if let id = proposal.ownedID,
            event.url?.absoluteString == "reha-calendar://event/\(id)"
          {
            try agenda.approvedAlarmChanged(id: id, minutes: patch.reminderMinutes)
          } else {
            try agenda.manuallyEditedAlarm(
              event, restoring: oldReceipt?["alarm_journal"] as? [String: Any])
          }
        } catch { warnings.append(CalendarMaintenance.alarmWarning) }
      }
      var savedEvent: NativeCalendarEvent?
      if kind != .remove {
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
        savedEvent = try NativeCalendarEvent(snapshot: checked)
      }
      let result = NativeEventMutationResult(
        status: .saved, event: savedEvent, operationID: token, maintenanceWarnings: warnings)
      try persist(
        [
          "proposal": proposal.journalValue, "result": result.journalValue,
          "alarm_journal": alarmState ?? NSNull() as Any,
        ], id: token
      )
      return result
    } catch {
      return NativeEventMutationResult(
        status: .uncertain, message: "Schreibstatus unklar. Kalender abgleichen.")
    }
  }
}

struct SystemEventReference: Sendable {
  let calendarID: String
  let externalID: String
  let occurrence: Date
  let start: Date
}

typealias SystemEventPresentation =
  @MainActor @Sendable (
    SystemEventReference,
    @escaping @Sendable (Result<NativeSystemEventEditAction, Error>) -> Void
  ) -> Void

@MainActor private final class SystemEventEditor: NSObject, @MainActor EKEventEditViewDelegate {
  static let shared = SystemEventEditor()
  private var editorCompletion: (@Sendable (Result<NativeSystemEventEditAction, Error>) -> Void)?
  private var activeEditor: EKEventEditViewController?
  func open(
    _ reference: SystemEventReference,
    completion: @escaping @Sendable (Result<NativeSystemEventEditAction, Error>) -> Void
  ) {
    guard editorCompletion == nil else {
      completion(.failure(NativeServiceError.invalidInput("Kalenderbearbeitung bereits geöffnet.")))
      return
    }
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      completion(.failure(NativeServiceError.permissionDenied))
      return
    }
    var root = UIApplication.shared.connectedScenes.compactMap {
      ($0 as? UIWindowScene)?.keyWindow?.rootViewController
    }.first
    while let shown = root?.presentedViewController { root = shown }
    guard let root else {
      completion(
        .failure(
          NativeServiceError.invalidInput(
            "Systemkalender nicht erreichbar. Terminname und Datum im Kalender suchen.")))
      return
    }
    let store = EKEventStore()
    guard let calendar = store.calendar(withIdentifier: reference.calendarID) else {
      completion(.failure(NativeServiceError.invalidInput("Kalender nicht verfügbar.")))
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
      completion(
        .failure(
          NativeServiceError.invalidInput(
            "Termin nicht eindeutig verfügbar. Kalenderansicht aktualisieren.")))
      return
    }
    editorCompletion = completion
    let editor = EKEventEditViewController()
    editor.eventStore = store
    editor.event = event
    editor.editViewDelegate = self
    activeEditor = editor
    root.present(editor, animated: true)
  }
  func eventEditViewController(
    _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
  ) {
    guard activeEditor === controller, let completion = editorCompletion else { return }
    editorCompletion = nil
    activeEditor = nil
    controller.dismiss(animated: true)
    switch action {
    case .canceled: completion(.success(.cancelled))
    case .saved: completion(.success(.saved))
    case .deleted: completion(.success(.deleted))
    @unknown default:
      completion(.failure(NativeServiceError.uncertainWrite))
    }
  }
}
