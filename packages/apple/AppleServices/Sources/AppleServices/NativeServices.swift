import EventKit
import PhotosUI
import UIKit
import UserNotifications
import Vision

struct SnapshotArgs: Decodable { let records: [OwnedRecord] }
struct OverlapArgs: Decodable {
  let events: [String: Values]
  let exclude: [String]
}
struct CalendarArgs: Decodable { let dedicated: Bool? }
struct Operation: Decodable {
  let kind: String
  let id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let external_id: String?
  let before: Values?
  let after: Values?
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let requires_resolution: Bool
}
struct WriteArgs: Decodable {
  let operation: Operation
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let recovery_only: Bool
}
struct PhotoArgs: Decodable { let base64: String }
struct ShareArgs: Decodable {
  let filename: String
  let content: String
}

/// EventKit and its date formatter are owned by calendarQueue. Presentation is
/// isolated separately so UIKit cannot infer main-actor isolation for the bridge.
public final class NativeServices: @unchecked Sendable {
  public static let shared = NativeServices()
  public func calendarStatus(
    completion: @escaping @Sendable (Result<NativeCalendarPlatformStatus, Error>) -> Void
  ) {
    calendarQueue.async { completion(.success(self.agendaService.calendarStatus())) }
  }
  public func eventCalendars(
    completion: @escaping @Sendable (Result<[NativeEventCalendarDestination], Error>) -> Void
  ) {
    measured(.calendarRead) { done in
      calendarReads.readDestinations(completion: done)
    } completion: {
      completion($0)
    }
  }
  public func mutateEvent(
    _ request: NativeEventMutationRequest,
    completion: @escaping @Sendable (Result<NativeEventMutationResult, Error>) -> Void
  ) {
    let correlation = request.proposal.token
    let began = ContinuousClock.now
    LocalDiagnostics.shared.record(.calendarWrite, .started, correlation: correlation)
    calendarReads.writeMutation(request) { result in
      let duration = began.duration(to: .now).components
      let outcome: DiagnosticOutcome = if case .success = result { .completed } else { .failed }
      LocalDiagnostics.shared.record(
        .calendarWrite, outcome, correlation: correlation,
        durationMs: Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000))
      completion(result)
    }
  }
  public func queryCalendar(
    _ request: NativeCalendarQuery,
    completion: @escaping @Sendable (Result<NativeCalendarReadResult, Error>) -> Void
  ) {
    measured(.calendarRead) { done in
      calendarReads.readQuery(request, completion: done)
    } completion: {
      completion($0)
    }
  }
  public func resolveCalendarEvent(
    _ reference: NativeCalendarReference,
    completion: @escaping @Sendable (Result<NativeCalendarEvent?, Error>) -> Void
  ) {
    measured(.calendarRead) { done in
      calendarReads.readEvent(reference, completion: done)
    } completion: {
      completion($0)
    }
  }
  private func measured<Value: Sendable>(
    _ step: DiagnosticStep,
    start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void,
    completion: @escaping @Sendable (Result<Value, Error>) -> Void
  ) {
    let correlation = UUID().uuidString
    let began = ContinuousClock.now
    LocalDiagnostics.shared.record(step, .started, correlation: correlation)
    start { result in
      let duration = began.duration(to: .now).components
      let outcome: DiagnosticOutcome = if case .success = result { .completed } else { .failed }
      LocalDiagnostics.shared.record(
        step, outcome, correlation: correlation,
        durationMs: Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000))
      completion(result)
    }
  }
  /// Permission alone never creates a calendar or changes the visible selection.
  public func requestCalendarAccess(
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    store.requestFullAccessToEvents { granted, _ in
      completion(granted ? .success(()) : .failure(NativeServiceError.permissionDenied))
    }
  }
  public func reminderStatus(
    completion: @escaping @Sendable (Result<NativeAgendaStatus, Error>) -> Void
  ) {
    calendarQueue.async { self.agendaService.readStatus(completion) }
  }
  /// Authorization changes no reminder preferences. The settings save owns activation.
  public func requestReminderPermission(
    completion: @escaping @Sendable (Result<NativeAgendaStatus, Error>) -> Void
  ) {
    measured(.reminderSettings) { done in
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
        _, error in
        if let error { done(.failure(error)) } else { self.reminderStatus(completion: done) }
      }
    } completion: {
      completion($0)
    }
  }
  public func testReminder(
    completion: @escaping @Sendable (Result<NativeNotificationReceipt, Error>) -> Void
  ) {
    measured(.reminderPlan) { done in
      calendarQueue.async { self.agendaService.testNotification(done) }
    } completion: {
      completion($0)
    }
  }
  public func perform(
    _ command: String, arguments: Data,
    completion: @escaping @Sendable (Result<Data, Error>) -> Void
  ) {
    let correlation = UUID().uuidString
    let began = Date()
    let step: DiagnosticStep? =
      switch command {
      case "camera", "photos", "decodePhoto": .intake
      case "recognize": .ocr
      case "mutateEvent": .calendarWrite
      case "queryEvents", "getEvent", "calendarStatus", "inspectCalendarLinks":
        .calendarRead
      case "enableReminders": .reminderSettings
      default: nil
      }
    if let step { LocalDiagnostics.shared.record(step, .started, correlation: correlation) }
    let request = ServiceRequest(
      arguments: arguments,
      completion: { result in
        if let step {
          let outcome: DiagnosticOutcome = if case .success = result { .completed } else { .failed }
          LocalDiagnostics.shared.record(
            step, outcome, correlation: correlation,
            durationMs: Int(Date().timeIntervalSince(began) * 1000))
        }
        completion(result)
      })
    do {
      switch command {
      case "eventCalendars", "queryEvents", "getEvent", "mutateEvent", "editSystemEvent",
        "resolveOwnedEvent", "inspectCalendarLinks":
        calendarReads.perform(command, request)
      case "calendarStatus":
        calendarQueue.async { request.resolve(self.agendaService.calendarStatus().legacyValue) }
      case "calendars": try calendars(request)
      case "snapshot": try snapshot(request)
      case "overlaps": try overlaps(request)
      case "forgetCalendar": forgetCalendar(request)
      case "apply": try apply(request)
      case "agenda": try agenda(request)
      case "agendaPresentation":
        calendarQueue.async {
          do { request.resolve(try self.agendaService.presentation()) } catch {
            request.reject(error)
          }
        }
      case "enableReminders": try enableReminders(request)
      case "requestReminderPermission": requestReminderPermission(request)
      case "reminderStatus": reminderStatus(request)
      case "pendingEventOpen": try pendingEventOpen(request)
      case "testReminder": testReminder(request)
      case "camera": DispatchQueue.main.async { NativePresentation.shared.camera(request) }
      case "photos": DispatchQueue.main.async { NativePresentation.shared.photos(request) }
      case "decodePhoto":
        DispatchQueue.global(qos: .userInitiated).async {
          do { try self.decodePhoto(request) } catch { request.reject(error) }
        }
      case "recognize":
        DispatchQueue.global(qos: .userInitiated).async {
          do { try self.recognize(request) } catch { request.reject(error) }
        }
      case "protectStorage": try protectStorage(request)
      case "share":
        DispatchQueue.main.async {
          do { try NativePresentation.shared.share(request) } catch {
            request.reject(error)
          }
        }
      case "deviceInfo": DispatchQueue.main.async { NativePresentation.shared.deviceInfo(request) }
      default: request.reject("Unbekannte native Aktion.")
      }
    } catch { request.reject(error) }
  }
  private let agendaService: AgendaService
  private let calendarReads: EventEditingService
  private var store: EKEventStore { agendaService.store }
  private let dedicatedCalendar = DedicatedCalendar()
  private var calendarQueue: DispatchQueue { agendaService.queue }
  private let iso = ISO8601DateFormatter()
  init(agenda: AgendaService = .shared) {
    agendaService = agenda
    calendarReads = EventEditingService(agenda: agenda)
  }
  public func start() {
    self.agendaService.start()
    Task { @MainActor in NativePresentation.shared.start() }
  }
  private func values(_ event: EKEvent) -> Values {
    Values(
      title: event.title ?? "", start_utc: iso.string(from: event.startDate),
      end_utc: iso.string(from: event.endDate),
      timezone: event.timeZone?.identifier ?? "Europe/Vienna", location: event.location ?? "",
      notes: event.notes ?? "",
      reminder_minutes: self.agendaService.logicalReminder(
        for: event, actual: event.alarms?.first.map { Int(-$0.relativeOffset / 60) }))
  }
  private func marker(_ id: String) -> String { "reha-calendar://event/\(id)" }
  private func owns(_ event: EKEvent, _ id: String) -> Bool {
    event.url?.absoluteString == marker(id)
  }
  private func calendarAccess<Value>(
    _ completion: (Result<Value, Error>) -> Void
  ) -> Bool {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      completion(.failure(NativeServiceError.permissionDenied))
      return false
    }
    return true
  }
  func calendars(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(CalendarArgs.self)
    requestCalendarAccess { result in
      if case .failure(let error) = result {
        invoke.reject(error)
        return
      }
      self.calendarQueue.async {
        var dedicatedID: String?
        var setupError: String?
        if args.dedicated == true {
          do {
            dedicatedID = try self.dedicatedCalendar.resolve(in: self.store).calendarIdentifier
          } catch {
            setupError = error.localizedDescription
          }
        }
        let calendars = self.store.calendars(for: .event).filter(\.allowsContentModifications).map {
          calendar in
          [
            "id": calendar.calendarIdentifier, "title": calendar.title,
            "source": calendar.source.title,
            "writable": calendar.allowsContentModifications,
            "is_default": calendar.calendarIdentifier
              == self.store.defaultCalendarForNewEvents?.calendarIdentifier,
          ] as [String: Any]
        }
        var result: [String: Any] = ["calendars": calendars]
        if let dedicatedID { result["dedicated_id"] = dedicatedID }
        if let setupError { result["setup_error"] = setupError }
        invoke.resolve(result)
      }
    }
  }
  public func importSnapshot(
    _ records: [NativeCalendarRecord],
    completion: @escaping @Sendable (Result<NativeImportSnapshot, Error>) -> Void
  ) {
    measured(.calendarRead) { done in
      guard calendarAccess(done) else { return }
      calendarQueue.async {
        var current: [String: NativeImportValues] = [:]
        var protected: [String] = []
        for record in records {
          if let external = record.externalID,
            let event = self.store.event(withIdentifier: external), self.owns(event, record.id),
            event.calendar.calendarIdentifier == record.calendarID
          {
            current[record.id] = NativeImportValues(self.values(event))
            if CalendarEventProtection.protectsImport(event)
              || self.agendaService.alarmIsProtected(
                event, approvedMinutes: record.reminderMinutes)
            {
              protected.append(record.id)
            }
          }
        }
        done(.success(NativeImportSnapshot(current: current, protectedIDs: protected)))
      }
    } completion: {
      completion($0)
    }
  }
  public func importOverlaps(
    events: [String: NativeImportValues], exclude: [String],
    completion: @escaping @Sendable (Result<[NativeImportOverlap], Error>) -> Void
  ) {
    measured(.calendarRead) { done in
      guard calendarAccess(done) else { return }
      calendarQueue.async {
        var overlaps: [NativeImportOverlap] = []
        for (id, values) in events.sorted(by: { $0.key < $1.key }) {
          guard let start = self.iso.date(from: values.startUTC),
            let end = self.iso.date(from: values.endUTC)
          else { continue }
          let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
          for event in self.store.events(matching: predicate) {
            guard event.startDate < end, event.endDate > start,
              !exclude.contains(where: { self.owns(event, $0) })
            else { continue }
            overlaps.append(
              NativeImportOverlap(
                appointmentID: id, externalID: event.eventIdentifier ?? "",
                title: event.title ?? "Termin", startUTC: self.iso.string(from: event.startDate),
                endUTC: self.iso.string(from: event.endDate)))
          }
        }
        overlaps.sort {
          ($0.appointmentID, $0.externalID, $0.startUTC, $0.endUTC, $0.title)
            < ($1.appointmentID, $1.externalID, $1.startUTC, $1.endUTC, $1.title)
        }
        done(.success(overlaps))
      }
    } completion: {
      completion($0)
    }
  }
  public func forgetCalendar(
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    calendarQueue.async {
      do {
        try self.agendaService.forget()
        try self.calendarReads.forget()
        self.dedicatedCalendar.forget()
        completion(.success(()))
      } catch { completion(.failure(error)) }
    }
  }
  // Existing JSON clients delegate to the same typed operations.
  func snapshot(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(SnapshotArgs.self)
    importSnapshot(args.records.map(NativeCalendarRecord.init)) { result in
      switch result {
      case .success(let value): invoke.resolve(value.legacyValue)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func overlaps(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(OverlapArgs.self)
    importOverlaps(events: args.events.mapValues(NativeImportValues.init), exclude: args.exclude) {
      result in
      switch result {
      case .success(let value): invoke.resolve(["overlaps": value.map(\.legacyValue)])
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func forgetCalendar(_ invoke: ServiceRequest) {
    forgetCalendar { result in
      switch result {
      case .success: invoke.resolve()
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  public func applyImport(
    _ operation: NativeImportOperation, recoveryOnly: Bool,
    completion: @escaping @Sendable (Result<NativeImportWriteResult, Error>) -> Void
  ) {
    measured(.calendarWrite) { done in
      writeImport(operation, recoveryOnly: recoveryOnly, completion: done)
    } completion: {
      completion($0)
    }
  }
  private func writeImport(
    _ op: NativeImportOperation, recoveryOnly: Bool,
    completion: @escaping @Sendable (Result<NativeImportWriteResult, Error>) -> Void
  ) {
    guard calendarAccess(completion) else { return }
    calendarQueue.async {
      func finish(
        _ status: NativeImportWriteStatus, _ event: EKEvent? = nil, _ message: String? = nil,
        warnings: [String] = []
      ) {
        completion(
          .success(
            NativeImportWriteResult(
              id: op.id, status: status, externalID: event?.eventIdentifier,
              error: message, maintenanceWarnings: warnings)))
      }
      guard UUID(uuidString: op.id) != nil, !op.requiresResolution,
        [.create, .update, .remove].contains(op.kind),
        let calendar = self.store.calendar(withIdentifier: op.calendarID),
        calendar.allowsContentModifications
      else {
        finish(.failed, nil, "Ungültiger Auftrag oder nicht beschreibbarer Kalender.")
        return
      }
      var existing: EKEvent?
      if let external = op.externalID { existing = self.store.event(withIdentifier: external) }
      if let event = existing,
        !self.owns(event, op.id) || event.calendar.calendarIdentifier != op.calendarID
      {
        finish(.conflict, nil, "Eintrag ist nicht diesem App-Import zugeordnet.")
        return
      }
      if op.kind == .create || (recoveryOnly && existing == nil) {
        guard let expected = op.after ?? op.before,
          let date = self.iso.date(from: expected.startUTC)
        else {
          finish(.failed, nil, "Datum fehlt.")
          return
        }
        let predicate = self.store.predicateForEvents(
          withStart: date.addingTimeInterval(-86400), end: date.addingTimeInterval(2 * 86400),
          calendars: [calendar])
        let matches = self.store.events(matching: predicate).filter { self.owns($0, op.id) }
        if matches.count > 1 {
          finish(.conflict, nil, "Mehrere zugeordnete Einträge: manuell prüfen.")
          return
        }
        existing = matches.first ?? existing
      }
      if recoveryOnly {
        if op.kind == .remove {
          finish(
            .uncertain, existing,
            "Löschstatus kann nicht sicher bewiesen werden. Im Kalender prüfen.")
          return
        }
        if let event = existing, let after = op.after,
          NativeImportValues(self.values(event)) == after
        {
          finish(.saved, event)
          return
        }
        finish(
          .uncertain, existing, "Schreibergebnis noch unklar. Kein neuer Termin wurde erstellt.")
        return
      }
      if op.kind == .create, let event = existing {
        if let after = op.after, NativeImportValues(self.values(event)) == after {
          finish(.saved, event)
        } else {
          finish(.conflict, event, "Vorhandener App-Termin weicht ab.")
        }
        return
      }
      if op.kind != .create {
        if let event = existing,
          CalendarEventProtection.protectsImport(event)
            || self.agendaService.alarmIsProtected(
              event, approvedMinutes: op.before?.reminderMinutes)
        {
          finish(
            .conflict, event,
            "Zusätzliche Kalenderangaben, Serien, Einladungen und veränderte Alarme bleiben geschützt."
          )
          return
        }
        guard let event = existing, let before = op.before,
          NativeImportValues(self.values(event)) == before
        else {
          finish(
            .conflict, existing,
            "Kalender wurde seit der Vorschau verändert. Vorschau erneut erstellen.")
          return
        }
      }
      do {
        if op.kind == .remove, let event = existing {
          try self.store.remove(event, span: .thisEvent, commit: true)
          finish(.saved)
          return
        }
        guard let after = op.after, let start = self.iso.date(from: after.startUTC),
          let end = self.iso.date(from: after.endUTC), end > start,
          let timezone = TimeZone(identifier: after.timezone)
        else {
          finish(.failed, nil, "Ungültige Terminzeit.")
          return
        }
        let event = existing ?? EKEvent(eventStore: self.store)
        let alarmChanged =
          op.kind == .create || op.before?.reminderMinutes != after.reminderMinutes
        if alarmChanged, existing != nil,
          self.agendaService.alarmIsProtected(event, approvedMinutes: op.before?.reminderMinutes)
        {
          finish(.conflict, event, "Manuell veränderte Kalenderalarme bleiben geschützt.")
          return
        }
        event.calendar = calendar
        event.title = after.title
        event.startDate = start
        event.endDate = end
        event.timeZone = timezone
        event.location = after.location
        event.notes = after.notes
        event.url = URL(string: self.marker(op.id))
        if alarmChanged {
          event.alarms = after.reminderMinutes.map { [EKAlarm(relativeOffset: -Double($0) * 60)] }
        }
        try self.store.save(event, span: .thisEvent, commit: true)
        var warnings: [String] = []
        if alarmChanged {
          do {
            try self.agendaService.approvedAlarmChanged(id: op.id, minutes: after.reminderMinutes)
          } catch { warnings.append(CalendarMaintenance.alarmWarning) }
        }
        finish(.saved, event, warnings: warnings)
      } catch {
        finish(.uncertain, existing, "EventKit konnte den Schreibstatus nicht sicher bestätigen.")
      }
    }
  }
  func apply(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(WriteArgs.self)
    let op = args.operation
    let operation = NativeImportOperation(
      kind: NativeImportKind(rawValue: op.kind) ?? .unsupported,
      id: op.id, calendarID: op.calendar_id, externalID: op.external_id,
      before: op.before.map(NativeImportValues.init), after: op.after.map(NativeImportValues.init),
      requiresResolution: op.requires_resolution)
    applyImport(operation, recoveryOnly: args.recovery_only) { result in
      switch result {
      case .success(let value): invoke.resolve(value.legacyValue)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  public func synchronizeAgenda(
    records: [NativeCalendarRecord], preferences: ReminderPreferences,
    displayCalendarIDs: [String],
    completion: @escaping @Sendable (Result<NativeAgendaStatus, Error>) -> Void
  ) {
    calendarQueue.async {
      do {
        try self.agendaService.sync(
          AgendaSyncArgs(
            records: records.map(\.ownedRecord), preferences: preferences,
            display_calendar_ids: displayCalendarIDs), completion: completion)
      } catch { completion(.failure(error)) }
    }
  }
  func agenda(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(AgendaSyncArgs.self)
    synchronizeAgenda(
      records: args.records.map(NativeCalendarRecord.init), preferences: args.preferences,
      displayCalendarIDs: args.display_calendar_ids ?? []
    ) { result in
      switch result {
      case .success(let value): Self.resolveAgenda(value, for: invoke)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func enableReminders(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(ReminderPreferences.self)
    self.agendaService.activate(args) { result in
      switch result {
      case .success(let value): Self.resolveAgenda(value, for: invoke)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  private static func resolveAgenda(_ value: NativeAgendaStatus, for invoke: ServiceRequest) {
    do { invoke.resolve(try value.legacyValue) } catch { invoke.reject(error) }
  }
  // Compatibility adapters preserve the previous wire format.
  func requestReminderPermission(_ invoke: ServiceRequest) {
    requestReminderPermission { result in
      switch result {
      case .success(let value): Self.resolveAgenda(value, for: invoke)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func reminderStatus(_ invoke: ServiceRequest) {
    reminderStatus { result in
      switch result {
      case .success(let value): Self.resolveAgenda(value, for: invoke)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func pendingEventOpen(_ invoke: ServiceRequest) throws {
    struct Args: Decodable { var acknowledge: String? }
    let args = try invoke.parseArgs(Args.self)
    calendarQueue.async {
      do {
        invoke.resolve(try self.agendaService.pendingOpen(acknowledge: args.acknowledge))
      } catch { invoke.reject(error) }
    }
  }
  func testReminder(_ invoke: ServiceRequest) {
    testReminder { result in
      switch result {
      case .success(let value): invoke.resolve(value.legacyValue)
      case .failure(let error): invoke.reject(error)
      }
    }
  }
  func decodePhoto(_ invoke: ServiceRequest) throws {
    let args = try invoke.parseArgs(PhotoArgs.self)
    guard args.base64.utf8.count <= ((NativePhoto.maximumBytes + 2) / 3) * 4,
      let data = Data(base64Encoded: args.base64)
    else { throw NativeServiceError.invalidInput("Foto nicht lesbar oder zu groß.") }
    invoke.resolve(["base64": try NativePhoto.decode(data).base64EncodedString()])
  }
  func recognize(_ invoke: ServiceRequest) throws {
    struct Args: Decodable {
      let base64: String
      // swift-format-ignore: AlwaysUseLowerCamelCase
      let budget_ms: Double?
    }
    let args = try invoke.parseArgs(Args.self)
    guard let data = Data(base64Encoded: args.base64), let image = UIImage(data: data)?.cgImage
    else {
      invoke.reject("Bild für Vision fehlt.")
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let started = Date()
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["de-DE", "en-US"]
      request.usesLanguageCorrection = false
      let timeout = DispatchWorkItem { request.cancel() }
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + min(60, max(0.001, (args.budget_ms ?? 60000) / 1000)), execute: timeout)
      defer { timeout.cancel() }
      do {
        try VNImageRequestHandler(cgImage: image).perform([request])
        var regions: [[String: Any]] = []
        var observations: [[String: Any]] = []
        for (index, observation) in (request.results ?? []).enumerated() {
          let candidates = observation.topCandidates(3)
          let bounds = observation.boundingBox
          let x = bounds.minX * Double(image.width)
          let y = (1 - bounds.maxY) * Double(image.height)
          let w = bounds.width * Double(image.width)
          let h = bounds.height * Double(image.height)
          let id = String(format: "region-%04d", index)
          regions.append([
            "id": id,
            "polygon": [
              ["x": x, "y": y], ["x": x + w, "y": y], ["x": x + w, "y": y + h],
              ["x": x, "y": y + h],
            ], "frame": "page", "kind": "text", "parent": "page", "children": [],
          ])
          observations.append([
            "id": "obs-\(id)", "text": candidates.first?.string ?? "", "region_ids": [id],
            "engine": "Apple Vision", "score": candidates.first?.confidence ?? 0,
            "alternatives": candidates.dropFirst().map(\.string),
          ])
        }
        invoke.resolve([
          "regions": regions, "observations": observations,
          "duration_ms": Int(Date().timeIntervalSince(started) * 1000),
          "manifest": [
            "engine": "Apple Vision", "revision": request.revision,
            "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "language_correction": false,
          ],
        ])
      } catch { invoke.reject("Lokale Vision-Erkennung fehlgeschlagen.") }
    }
  }
  func protectStorage(_ invoke: ServiceRequest) throws {
    let root = try AppStorage.prepare()
    invoke.resolve(["path": root.path, "excluded_from_backup": true])
  }
}
