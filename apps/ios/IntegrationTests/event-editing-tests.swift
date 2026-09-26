import CoreLocation
import EventKit
import XCTest

final class EventEditingTests: XCTestCase {
  private var editing = EventEditingService(isForeground: { true })
  private func call(_ command: String, _ args: [String: Any]) async throws -> [String: Any] {
    let data = try JSONSerialization.data(withJSONObject: args)
    let response: Data = try await withCheckedThrowingContinuation { continuation in
      let request = ServiceRequest(arguments: data) { continuation.resume(with: $0) }
      editing.perform(command, request)
    }
    return try JSONSerialization.jsonObject(with: response) as? [String: Any] ?? [:]
  }
  func testTypedSystemEditorResolvesOnlyTheSelectedOccurrence() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let agenda = AgendaService(storageRoot: root, widgetRoot: root)
      agenda.start(registerBackground: false)
      let store = agenda.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundene Systembearbeitung"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let event = EKEvent(eventStore: store)
      event.calendar = calendar
      event.title = "Erfundene Serie"
      event.startDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 7200)
      event.endDate = event.startDate.addingTimeInterval(1800)
      event.timeZone = TimeZone(identifier: "Europe/Vienna")
      event.notes = "Unveränderte fremde Notiz"
      event.url = URL(string: "https://example.org/original")
      event.recurrenceRules = [
        EKRecurrenceRule(
          recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))
      ]
      try store.save(event, span: .thisEvent, commit: true)
      let iso = ISO8601DateFormatter()
      editing = EventEditingService(isForeground: { true }, agenda: agenda)
      let query: [String: Any] = [
        "calendar_ids": [calendar.calendarIdentifier],
        "start_utc": iso.string(from: event.startDate.addingTimeInterval(-3600)),
        "end_utc": iso.string(from: event.startDate.addingTimeInterval(4 * 86400)), "records": [],
      ]
      let before = try await call("queryEvents", query)
      let events = try XCTUnwrap(before["events"] as? [[String: Any]])
      XCTAssertEqual(events.count, 3)
      let selected = try XCTUnwrap(events.dropFirst().first)
      let reference = try NativeCalendarReference(legacy: selected)
      let expectedOccurrence = try XCTUnwrap(iso.date(from: reference.occurrence))
      let expectedStart = try XCTUnwrap(iso.date(from: reference.expectedStartUTC))
      for action in [NativeSystemEventEditAction.cancelled, .saved, .deleted] {
        editing = EventEditingService(
          isForeground: { true }, agenda: agenda,
          presentEditor: { resolved, done in
            XCTAssertEqual(resolved.calendarID, reference.calendarID)
            XCTAssertEqual(resolved.externalID, reference.externalID)
            XCTAssertEqual(resolved.occurrence, expectedOccurrence)
            XCTAssertEqual(resolved.start, expectedStart)
            done(.success(action))
          })
        let received: NativeSystemEventEditAction = try await withCheckedThrowingContinuation {
          continuation in
          editing.editSystemEvent(reference) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(received, action)
        let legacy = try await call("editSystemEvent", ["event": selected])
        XCTAssertEqual(legacy["reload"] as? Bool, true)
        XCTAssertEqual(legacy.count, 1)
      }
      editing = EventEditingService(
        isForeground: { true }, agenda: agenda,
        presentEditor: { _, done in
          done(.failure(NativeServiceError.permissionDenied))
        })
      do {
        let _: NativeSystemEventEditAction = try await withCheckedThrowingContinuation {
          continuation in
          editing.editSystemEvent(reference) { continuation.resume(with: $0) }
        }
        XCTFail("Presentation error must retain its type")
      } catch { XCTAssertEqual(error as? NativeServiceError, .permissionDenied) }
      editing = EventEditingService(
        isForeground: { true }, agenda: agenda,
        presentEditor: { _, done in
          XCTFail("An unavailable occurrence must never open an editor")
          done(.success(.cancelled))
        })
      var missing = reference
      missing.externalID = UUID().uuidString
      do {
        let _: NativeSystemEventEditAction = try await withCheckedThrowingContinuation {
          continuation in
          editing.editSystemEvent(missing) { continuation.resume(with: $0) }
        }
        XCTFail("Missing occurrence must fail")
      } catch {
        guard case .invalidInput = error as? NativeServiceError else {
          XCTFail("Unexpected failure: \(error)")
          return
        }
      }
      let after = try await call("queryEvents", query)
      XCTAssertTrue(
        NSDictionary(dictionary: before).isEqual(to: after),
        "Opening and interpreting the system editor must not write or adopt a calendar event")
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testTypedImportRecoveryCannotCreateMissingEvents() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let agenda = AgendaService(storageRoot: root, widgetRoot: root)
      agenda.start(registerBackground: false)
      let native = NativeServices(agenda: agenda)
      let store = agenda.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundener typisierter Import"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let calendarID = calendar.calendarIdentifier
      let id = UUID().uuidString
      let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 7200)
      let iso = ISO8601DateFormatter()
      let values = NativeImportValues(
        title: "Erfundene Therapie", startUTC: iso.string(from: start),
        endUTC: iso.string(from: start.addingTimeInterval(1800)), timezone: "Europe/Vienna",
        location: "Raum 3", notes: "Nur synthetische Notiz", reminderMinutes: 10)
      func apply(_ kind: NativeImportKind, recovery: Bool, externalID: String? = nil)
        async throws -> NativeImportWriteResult
      {
        let operation = NativeImportOperation(
          kind: kind, id: id, calendarID: calendarID, externalID: externalID,
          before: values, after: values, requiresResolution: false)
        return try await withCheckedThrowingContinuation { continuation in
          native.applyImport(operation, recoveryOnly: recovery) {
            continuation.resume(with: $0)
          }
        }
      }
      func events() -> [EKEvent] {
        store.events(
          matching: store.predicateForEvents(
            withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(3600),
            calendars: [calendar]))
      }
      let missing = try await apply(.create, recovery: true)
      XCTAssertEqual(missing.status, .uncertain)
      XCTAssertTrue(events().isEmpty, "Recovery is not authorization to create")
      let saved = try await apply(.create, recovery: false)
      XCTAssertEqual(saved.status, .saved)
      let externalID = try XCTUnwrap(saved.externalID)
      let recovered = try await apply(.create, recovery: true)
      XCTAssertEqual(recovered.status, .saved)
      XCTAssertEqual(recovered.externalID, externalID)
      let repeated = try await apply(.create, recovery: false)
      XCTAssertEqual(repeated.status, .saved)
      XCTAssertEqual(events().count, 1, "A repeated create must not duplicate the owned event")
      let removal = try await apply(.remove, recovery: true, externalID: externalID)
      XCTAssertEqual(removal.status, .uncertain)
      XCTAssertEqual(events().count, 1, "Recovery never retries an uncertain deletion")
      let record = NativeCalendarRecord(
        id: id, calendarID: calendarID, externalID: externalID, status: "saved",
        title: values.title, startUTC: values.startUTC, endUTC: values.endUTC,
        timezone: values.timezone, location: values.location, notes: values.notes,
        reminderMinutes: values.reminderMinutes)
      let snapshot: NativeImportSnapshot = try await withCheckedThrowingContinuation {
        continuation in
        native.importSnapshot([record]) { continuation.resume(with: $0) }
      }
      XCTAssertEqual(snapshot.current[id], values)
      XCTAssertTrue(snapshot.protectedIDs.isEmpty)
      let overlaps: [NativeImportOverlap] = try await withCheckedThrowingContinuation {
        continuation in
        native.importOverlaps(events: [id: values], exclude: [id]) {
          continuation.resume(with: $0)
        }
      }
      XCTAssertFalse(overlaps.contains { $0.externalID == externalID })
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testImportProtectsMetadataOutsideApprovedValues() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let agenda = AgendaService(storageRoot: root, widgetRoot: root)
      agenda.start(registerBackground: false)
      let native = NativeServices(agenda: agenda)
      func invoke(_ command: String, _ args: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: args)
        let response: Data = try await withCheckedThrowingContinuation { continuation in
          native.perform(command, arguments: data) { continuation.resume(with: $0) }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
      }
      let store = agenda.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundener Metadatenschutz"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let iso = ISO8601DateFormatter()
      let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
      for allDay in [false, true] {
        let id = UUID().uuidString
        let values: [String: Any] = [
          "title": "Erfundene Therapie", "start_utc": iso.string(from: start),
          "end_utc": iso.string(from: start.addingTimeInterval(86400)),
          "timezone": TimeZone.current.identifier, "location": "Raum 1", "notes": "",
          "reminder_minutes": NSNull(),
        ]
        var operation: [String: Any] = [
          "kind": "create", "id": id, "calendar_id": calendar.calendarIdentifier,
          "requires_resolution": false, "after": values,
        ]
        let saved = try await invoke("apply", ["operation": operation, "recovery_only": false])
        XCTAssertEqual(saved["status"] as? String, "saved")
        let external = try XCTUnwrap(saved["external_id"] as? String)
        let record: [String: Any] = [
          "id": id, "status": "saved", "calendar_id": calendar.calendarIdentifier,
          "external_id": external, "approved": values,
        ]
        let baseline = try await invoke("snapshot", ["records": [record]])
        XCTAssertEqual(baseline["protected_ids"] as? [String], [])
        let event = try XCTUnwrap(store.event(withIdentifier: external))
        if allDay {
          event.isAllDay = true
        } else {
          let place = EKStructuredLocation(title: "Raum 1")
          place.geoLocation = CLLocation(latitude: 0, longitude: 0)
          place.radius = 25
          event.structuredLocation = place
        }
        try store.save(event, span: .thisEvent, commit: true)
        let snapshot = try await invoke("snapshot", ["records": [record]])
        XCTAssertEqual(snapshot["protected_ids"] as? [String], [id])
        // Even a fresh compact preview cannot authorize deletion of metadata
        // that it cannot show or restore. Revision and import undo use this route.
        let current = try XCTUnwrap((snapshot["current"] as? [String: Any])?[id])
        operation["before"] = current
        operation["external_id"] = external
        for kind in ["update", "remove"] {
          operation["kind"] = kind
          let result = try await invoke("apply", ["operation": operation, "recovery_only": false])
          XCTAssertEqual(
            result["status"] as? String, "conflict", "Protected \(kind), allDay=\(allDay)")
        }
        let retained = try XCTUnwrap(store.event(withIdentifier: external))
        XCTAssertEqual(retained.isAllDay, allDay)
        if !allDay { XCTAssertNotNil(retained.structuredLocation?.geoLocation) }
      }
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testImportProtectionRetainsUnsupportedAvailability() {
    // Local simulator calendars expose no availability choices. Exercise the
    // account-independent policy with values supported by other account types.
    for availability in [EKEventAvailability.busy, .notSupported] {
      XCTAssertFalse(
        CalendarEventProtection.protectsImportMetadata(
          allDay: false, locationGeometry: false, availability: availability))
    }
    for availability in [EKEventAvailability.free, .tentative, .unavailable] {
      XCTAssertTrue(
        CalendarEventProtection.protectsImportMetadata(
          allDay: false, locationGeometry: false, availability: availability))
    }
  }
  func testCommittedWritesSurviveAlarmJournalFailure() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let agenda = AgendaService(storageRoot: root, widgetRoot: root)
      agenda.start(registerBackground: false)
      // Deterministic disk failure after startup: the journal destination is a directory.
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent("agenda-private-v1.json"),
        withIntermediateDirectories: false)
      editing = EventEditingService(isForeground: { true }, agenda: agenda)
      let native = NativeServices(agenda: agenda)
      let store = agenda.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundener Wartungsfehlertest"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let start = Date(
        timeIntervalSince1970: floor(Date().addingTimeInterval(7200).timeIntervalSince1970))
      let iso = ISO8601DateFormatter()
      let patch: [String: Any] = [
        "title": "Erfundene Therapie", "start_utc": iso.string(from: start),
        "end_utc": iso.string(from: start.addingTimeInterval(1800)), "timezone": "Europe/Vienna",
        "location": "", "reminder_minutes": 10,
      ]
      let proposal: [String: Any] = [
        "token": UUID().uuidString, "kind": "create", "owned_id": UUID().uuidString,
        "calendar_id": calendar.calendarIdentifier, "patch": patch,
      ]
      let saved = try await call("mutateEvent", ["proposal": proposal])
      XCTAssertEqual(saved["status"] as? String, "saved")
      XCTAssertEqual(saved["maintenance_warnings"] as? [String], [CalendarMaintenance.alarmWarning])
      XCTAssertNotNil(saved["event"] as? [String: Any])
      // A fresh service reads the durable receipt; it must not execute the write again.
      editing = EventEditingService(isForeground: { true }, agenda: agenda)
      let replay = try await call("mutateEvent", ["proposal": proposal, "recovery_only": true])
      XCTAssertTrue(NSDictionary(dictionary: replay).isEqual(to: saved))

      // Import values include notes; the deliberately narrower manual mutation
      // contract does not permit changing them.
      var importValues = patch
      importValues["notes"] = ""
      let operation: [String: Any] = [
        "kind": "create", "id": UUID().uuidString, "calendar_id": calendar.calendarIdentifier,
        "requires_resolution": false, "after": importValues,
      ]
      let data = try JSONSerialization.data(withJSONObject: [
        "operation": operation, "recovery_only": false,
      ])
      let response: Data = try await withCheckedThrowingContinuation { continuation in
        native.perform("apply", arguments: data) { continuation.resume(with: $0) }
      }
      let imported = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
      XCTAssertEqual(imported["status"] as? String, "saved")
      XCTAssertEqual(
        imported["maintenance_warnings"] as? [String], [CalendarMaintenance.alarmWarning])
      XCTAssertNotNil(imported["external_id"] as? String)
      let events = store.events(
        matching: store.predicateForEvents(
          withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(3600),
          calendars: [calendar]))
      XCTAssertEqual(events.count, 2, "Receipt replay duplicated an already committed event")
      XCTAssertTrue(events.allSatisfy { $0.alarms?.first?.relativeOffset == -600 })
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testRepairFindsExactMarkersAndPreservesCalendarEvents() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator runner calendar access required")
      }
      let store = AgendaService.shared.store
      let source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundene Kalenderbereinigung"
      calendar.source = source
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let id = UUID().uuidString
      let missingID = UUID().uuidString
      let ambiguousID = UUID().uuidString
      let date = Date(
        timeIntervalSince1970: floor(Date().addingTimeInterval(86400).timeIntervalSince1970))
      let iso = ISO8601DateFormatter()
      func makeEvent(_ marker: String) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "Erfundene Therapie"
        event.startDate = date
        event.endDate = date.addingTimeInterval(1800)
        event.notes = "Original bleibt erhalten"
        event.url = URL(string: marker)
        event.alarms = [EKAlarm(relativeOffset: -600)]
        try store.save(event, span: .thisEvent, commit: true)
        return event
      }
      let event = try makeEvent("reha-calendar://event/\(id)")
      _ = try makeEvent("https://example.org/unrelated")
      _ = try makeEvent("reha-calendar://event/\(ambiguousID)")
      _ = try makeEvent("reha-calendar://event/\(ambiguousID)")
      let records = [id, missingID, ambiguousID].map { value in
        [
          "id": value, "status": "saved", "calendar_id": "old-calendar",
          "external_id": "old-event",
          "approved": [
            "title": "Erfundene Therapie", "start_utc": iso.string(from: date),
            "end_utc": iso.string(from: date.addingTimeInterval(1800)),
            "timezone": "Europe/Vienna", "location": "", "notes": "", "reminder_minutes": 10,
          ],
        ] as [String: Any]
      }
      let inspected = try await call("inspectCalendarLinks", ["records": records])
      let results = try XCTUnwrap(inspected["results"] as? [[String: Any]])
      XCTAssertEqual(results.count, 3)
      XCTAssertEqual(results[0]["status"] as? String, "found")
      XCTAssertEqual(
        (results[0]["event"] as? [String: Any])?["calendar_id"] as? String,
        calendar.calendarIdentifier)
      XCTAssertEqual(
        results[1]["status"] as? String, "unavailable",
        "Same title and time must not adopt unrelated events")
      XCTAssertEqual(results[2]["reason"] as? String, "ambiguous")
      let typedRecords = try JSONDecoder().decode(
        [OwnedRecord].self, from: JSONSerialization.data(withJSONObject: records)
      ).map(NativeCalendarRecord.init)
      let typed: NativeCalendarLinkInspection = try await withCheckedThrowingContinuation { c in
        NativeServices.shared.inspectCalendarLinks(typedRecords) { c.resume(with: $0) }
      }
      XCTAssertTrue(typed.calendarIDs.contains(calendar.calendarIdentifier))
      XCTAssertEqual(typed.results.map(\.id), [id, missingID, ambiguousID])
      XCTAssertEqual(
        typed.results[0].state,
        .found(
          calendarID: calendar.calendarIdentifier,
          externalID: event.eventIdentifier ?? event.calendarItemIdentifier,
          ownershipURL: "reha-calendar://event/\(id)"))
      XCTAssertEqual(typed.results[1].state, .unavailable(reason: "calendar_missing"))
      XCTAssertEqual(typed.results[2].state, .unavailable(reason: "ambiguous"))
      let refreshed = try XCTUnwrap(store.event(withIdentifier: event.eventIdentifier))
      XCTAssertEqual(refreshed.notes, "Original bleibt erhalten")
      XCTAssertEqual(refreshed.alarms?.first?.relativeOffset, -600)
      XCTAssertEqual(refreshed.url, event.url)
      let query = try await call(
        "queryEvents",
        [
          "calendar_ids": [calendar.calendarIdentifier, "old-calendar"],
          "records": [records[1]], "start_utc": iso.string(from: date.addingTimeInterval(-3600)),
          "end_utc": iso.string(from: date.addingTimeInterval(3600)),
        ])
      XCTAssertEqual((query["events"] as? [Any])?.count, 4)
      let gaps = try XCTUnwrap(query["unavailable_events"] as? [[String: Any]])
      XCTAssertEqual(gaps.count, 1)
      XCTAssertEqual(gaps[0]["id"] as? String, missingID)
      XCTAssertEqual(gaps[0]["start_utc"] as? String, iso.string(from: date))

      var linked = records[0]
      linked["calendar_id"] = calendar.calendarIdentifier
      linked["external_id"] = event.eventIdentifier
      var selection: [String: Any] = [
        "calendar_ids": [], "records": [linked, records[1]],
        "start_utc": iso.string(from: date.addingTimeInterval(-3600)),
        "end_utc": iso.string(from: date.addingTimeInterval(3600)),
      ]
      let hidden = try await call("queryEvents", selection)
      XCTAssertEqual(
        (hidden["events"] as? [Any])?.count, 0,
        "Imported events must obey the display/read selection")
      XCTAssertEqual(hidden["unavailable_calendar_ids"] as? [String], [])
      XCTAssertEqual((hidden["unavailable_events"] as? [Any])?.count, 0)
      selection["calendar_ids"] = [calendar.calendarIdentifier]
      let visible = try await call("queryEvents", selection)
      let visibleEvents = try XCTUnwrap(visible["events"] as? [[String: Any]])
      XCTAssertEqual(visibleEvents.count, 4)
      XCTAssertEqual(visibleEvents.filter { $0["import_id"] as? String == id }.count, 1)
      XCTAssertEqual((visible["unavailable_events"] as? [Any])?.count, 0)
      let originalEvents = try XCTUnwrap(query["events"] as? [[String: Any]])
      for var value in visibleEvents {
        let original = try XCTUnwrap(
          originalEvents.first { $0["id"] as? String == value["id"] as? String })
        value.removeValue(forKey: "import_id")
        XCTAssertEqual(
          NSDictionary(dictionary: value), NSDictionary(dictionary: original),
          "Deduplicating an owned occurrence must preserve its metadata and fingerprint")
      }
      let repeatedRecord = try JSONDecoder().decode(
        OwnedRecord.self, from: JSONSerialization.data(withJSONObject: linked))
      let typedQuery = NativeCalendarQuery(
        calendarIDs: [calendar.calendarIdentifier],
        startUTC: iso.string(from: date.addingTimeInterval(-3600)),
        endUTC: iso.string(from: date.addingTimeInterval(3600)), timezone: "Europe/Vienna",
        selectionRevision: 0,
        records: [NativeCalendarRecord(repeatedRecord), NativeCalendarRecord(repeatedRecord)])
      let typedResult: NativeCalendarReadResult = try await withCheckedThrowingContinuation { c in
        editing.readQuery(typedQuery) { c.resume(with: $0) }
      }
      let typedEvents = try typedResult.events.map { try $0.legacyValue }
      XCTAssertEqual(typedEvents.count, visibleEvents.count)
      for value in typedEvents {
        let expected = try XCTUnwrap(
          visibleEvents.first { $0["id"] as? String == value["id"] as? String })
        XCTAssertEqual(NSDictionary(dictionary: value), NSDictionary(dictionary: expected))
      }
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testExternalMetadataOccurrenceAndUndo() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator runner calendar access required")
      }
      let store = AgendaService.shared.store
      let source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundener Bearbeitungstest \(UUID().uuidString)"
      calendar.source = source
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let event = EKEvent(eventStore: store)
      event.calendar = calendar
      event.title = "Erfundene Einzeltherapie"
      event.location = "Raum 1"
      event.notes = "Diese fremde Notiz muss bleiben."
      event.url = URL(string: "https://example.org/original")
      event.startDate = Date(
        timeIntervalSince1970: floor(Date().addingTimeInterval(86400).timeIntervalSince1970))
      event.endDate = event.startDate.addingTimeInterval(1800)
      event.timeZone = TimeZone(identifier: "Europe/Vienna")
      event.alarms = [
        EKAlarm(relativeOffset: -600),
        EKAlarm(absoluteDate: event.startDate.addingTimeInterval(-3600)),
      ]
      event.recurrenceRules = [
        EKRecurrenceRule(
          recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))
      ]
      try store.save(event, span: .thisEvent, commit: true)
      let iso = ISO8601DateFormatter()
      let query: [String: Any] = [
        "calendar_ids": [calendar.calendarIdentifier],
        "start_utc": iso.string(from: event.startDate.addingTimeInterval(-3600)),
        "end_utc": iso.string(from: event.startDate.addingTimeInterval(4 * 86400)), "records": [],
      ]
      let initialResponse = try await call("queryEvents", query)
      let initial = try XCTUnwrap(initialResponse["events"] as? [[String: Any]])
      XCTAssertEqual(initial.count, 3)
      let target = initial[1]
      let missing = UUID().uuidString
      var partialQuery = query
      var approved = try XCTUnwrap(target["values"] as? [String: Any])
      approved["notes"] = ""
      partialQuery["calendar_ids"] = [calendar.calendarIdentifier, missing]
      partialQuery["records"] = [
        [
          "id": UUID().uuidString, "status": "saved", "calendar_id": missing,
          "external_id": UUID().uuidString, "approved": approved,
        ]
      ]
      let partial = try await call("queryEvents", partialQuery)
      XCTAssertEqual((partial["events"] as? [[String: Any]])?.count, 3)
      XCTAssertEqual(partial["unavailable_calendar_ids"] as? [String], [missing])
      partialQuery["calendar_ids"] = [missing]
      let unavailableOnly = try await call("queryEvents", partialQuery)
      XCTAssertEqual((unavailableOnly["events"] as? [[String: Any]])?.count, 0)
      XCTAssertEqual(unavailableOnly["unavailable_calendar_ids"] as? [String], [missing])
      let checked = try await call("getEvent", ["event": target])
      XCTAssertNotNil(checked["event"] as? [String: Any], "Occurrence could not be resolved")
      if let current = checked["event"] as? [String: Any] {
        XCTAssertTrue(
          NSDictionary(dictionary: current).isEqual(to: target),
          "Unchanged snapshot must remain stable across repeated occurrence lookup")
      }
      XCTAssertEqual(target["system_only"] as? Bool, false)
      let token = UUID().uuidString
      let proposal: [String: Any] = [
        "token": token, "kind": "update", "calendar_id": calendar.calendarIdentifier,
        "before": target, "patch": ["location": "Raum 2"],
      ]
      let saved = try await call("mutateEvent", ["proposal": proposal, "recovery_only": false])
      XCTAssertEqual(saved["status"] as? String, "saved")
      let repeated = try await call("mutateEvent", ["proposal": proposal, "recovery_only": false])
      XCTAssertEqual(repeated["status"] as? String, "saved")
      let queried = try await call("queryEvents", query)
      let current = try XCTUnwrap(queried["events"] as? [[String: Any]])
      XCTAssertEqual(current.count, 3)
      let locations = current.compactMap {
        ($0["values"] as? [String: Any])?["location"] as? String
      }
      XCTAssertEqual(locations, ["Raum 1", "Raum 2", "Raum 1"])
      for item in current {
        let metadata = try XCTUnwrap(item["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["notes"] as? String, event.notes)
        XCTAssertEqual(metadata["url"] as? String, "https://example.org/original")
        XCTAssertEqual((metadata["alarms"] as? [Any])?.count, 2)
      }
      let stale: [String: Any] = [
        "token": UUID().uuidString, "kind": "remove", "calendar_id": calendar.calendarIdentifier,
        "before": target, "patch": [:],
      ]
      let conflict = try await call("mutateEvent", ["proposal": stale, "recovery_only": false])
      XCTAssertEqual(conflict["status"] as? String, "conflict")
      let after = try XCTUnwrap(saved["event"] as? [String: Any])
      let undo: [String: Any] = [
        "token": UUID().uuidString, "kind": "update", "calendar_id": calendar.calendarIdentifier,
        "before": after, "patch": ["location": "Raum 1"], "undo_of": token,
      ]
      let undone = try await call("mutateEvent", ["proposal": undo, "recovery_only": false])
      XCTAssertEqual(undone["status"] as? String, "saved")
      let deleteToken = UUID().uuidString
      let removal: [String: Any] = [
        "token": deleteToken, "kind": "remove", "calendar_id": calendar.calendarIdentifier,
        "before": try XCTUnwrap(undone["event"]), "patch": [:],
      ]
      let removed = try await call("mutateEvent", ["proposal": removal, "recovery_only": false])
      XCTAssertEqual(removed["status"] as? String, "saved")
      let afterRemoval = try await call("queryEvents", query)
      XCTAssertEqual((afterRemoval["events"] as? [Any])?.count, 2)
      let restored: [String: Any] = [
        "token": UUID().uuidString, "kind": "create", "calendar_id": calendar.calendarIdentifier,
        "patch": try XCTUnwrap(target["values"]), "undo_of": deleteToken,
      ]
      let restoration = try await call(
        "mutateEvent", ["proposal": restored, "recovery_only": false])
      XCTAssertEqual(restoration["status"] as? String, "saved")
      let final = try await call("queryEvents", query)
      XCTAssertEqual((final["events"] as? [Any])?.count, 3)
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testManagedAlarmHandoffKeepsUndoSnapshotStable() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      try await requireTestNotificationAuthorization()
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let agenda = AgendaService(storageRoot: root, widgetRoot: root)
      agenda.start(registerBackground: false)
      editing = EventEditingService(isForeground: { true }, agenda: agenda)
      let store = agenda.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundener Rücknahmetest"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer { try? store.removeCalendar(calendar, commit: true) }
      let id = UUID().uuidString
      let iso = ISO8601DateFormatter()
      let start = Date(
        timeIntervalSince1970: floor(Date().addingTimeInterval(7200).timeIntervalSince1970))
      let token = UUID().uuidString
      let patch: [String: Any] = [
        "title": "Erfundene Therapie", "start_utc": iso.string(from: start),
        "end_utc": iso.string(from: start.addingTimeInterval(1800)), "timezone": "Europe/Vienna",
        "location": "", "reminder_minutes": 10,
      ]
      let saved = try await call(
        "mutateEvent",
        [
          "proposal": [
            "token": token, "kind": "create", "owned_id": id,
            "calendar_id": calendar.calendarIdentifier, "patch": patch,
          ]
        ])
      XCTAssertEqual(saved["status"] as? String, "saved")
      let after = try XCTUnwrap(saved["event"] as? [String: Any])
      let values = Values(
        title: "Erfundene Therapie", start_utc: iso.string(from: start),
        end_utc: iso.string(from: start.addingTimeInterval(1800)), timezone: "Europe/Vienna",
        location: "", notes: "", reminder_minutes: 10)
      let record = OwnedRecord(
        status: "saved", id: id, calendar_id: calendar.calendarIdentifier,
        external_id: try XCTUnwrap(after["external_id"] as? String), approved: values)
      let _: Void = try await withCheckedThrowingContinuation { continuation in
        agenda.queue.async {
          do {
            try agenda.sync(
              AgendaSyncArgs(records: [record], preferences: ReminderPreferences(enabled: true))
            ) { continuation.resume(with: $0.map { _ in () }) }
          } catch { continuation.resume(throwing: error) }
        }
      }
      XCTAssertTrue((store.event(withIdentifier: record.external_id!)?.alarms ?? []).isEmpty)
      let readBack = try await call("getEvent", ["event": after])
      XCTAssertTrue(
        NSDictionary(dictionary: try XCTUnwrap(readBack["event"] as? [String: Any])).isEqual(
          to: after))
      let recordJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
      let resolved = try await call("resolveOwnedEvent", ["record": recordJSON])
      XCTAssertEqual(resolved["status"] as? String, "found")
      func typed(_ value: NativeCalendarRecord) async throws -> NativeOwnedEventResolution {
        try await withCheckedThrowingContinuation { continuation in
          editing.resolveOwnedEvent(value) { continuation.resume(with: $0) }
        }
      }
      let nativeRecord = NativeCalendarRecord(record)
      let nativeResolved = try await typed(nativeRecord)
      XCTAssertTrue(NSDictionary(dictionary: try nativeResolved.legacyValue).isEqual(to: resolved))
      guard case .found(let nativeEvent) = nativeResolved else {
        return XCTFail("Typed lookup lost the saved owned event")
      }
      XCTAssertEqual(nativeEvent.importID, id)
      XCTAssertEqual(nativeEvent.externalID, record.external_id)
      var missingExternal = nativeRecord
      missingExternal.externalID = nil
      let recoveredIdentity = try await typed(missingExternal)
      XCTAssertTrue(
        NSDictionary(dictionary: try recoveredIdentity.legacyValue).isEqual(to: resolved))
      var missingCalendar = missingExternal
      missingCalendar.calendarID = UUID().uuidString
      if case .unavailable = try await typed(missingCalendar) {
      } else {
        XCTFail("Missing calendar was classified as deletion")
      }
      let ownedEvent = try XCTUnwrap(store.event(withIdentifier: record.external_id!))
      let marker = ownedEvent.url
      ownedEvent.url = URL(string: "https://example.invalid/foreign-event")
      try store.save(ownedEvent, span: .thisEvent, commit: true)
      if case .unavailable = try await typed(nativeRecord) {
      } else {
        XCTFail("A foreign ownership marker was accepted")
      }
      ownedEvent.url = marker
      try store.save(ownedEvent, span: .thisEvent, commit: true)
      let removal = try await call(
        "mutateEvent",
        [
          "proposal": [
            "token": UUID().uuidString, "kind": "remove", "owned_id": id,
            "calendar_id": calendar.calendarIdentifier, "before": after, "patch": [:],
            "undo_of": token,
          ]
        ])
      XCTAssertEqual(removal["status"] as? String, "saved")
      let deleted = try await call("resolveOwnedEvent", ["record": recordJSON])
      XCTAssertEqual(deleted["status"] as? String, "deleted")
      let nativeDeleted = try await typed(nativeRecord)
      XCTAssertTrue(NSDictionary(dictionary: try nativeDeleted.legacyValue).isEqual(to: deleted))
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        agenda.queue.async { continuation.resume(with: Result { try agenda.forget() }) }
      }
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }

}
