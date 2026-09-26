import EventKit
import SwiftUI
import UserNotifications
import WidgetKit
import XCTest

/// Counts attempted network-source synchronization without initiating one.
/// The service owns EventKit access; the counter has its own lock for assertions.
private final class LocalOnlyEventStore: EKEventStore {
  private let lock = NSLock()
  private var attempts = 0
  var remoteSyncAttempts: Int {
    lock.lock()
    defer { lock.unlock() }
    return attempts
  }
  override func refreshSourcesIfNecessary() {
    lock.lock()
    attempts += 1
    lock.unlock()
  }
}

final class AgendaNativeTests: XCTestCase {
  func testLocalCalendarQueriesRepairAndMaintenanceDoNotRequestRemoteSync() async throws {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      throw XCTSkip("Simulator runner calendar access required")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LocalOnlyEventStore()
    let service = AgendaService(storageRoot: root, widgetRoot: root, eventStore: store)
    service.start(registerBackground: false)
    let native = NativeServices(agenda: service)
    let query = NativeCalendarQuery(
      calendarIDs: [], startUTC: "2026-09-20T00:00:00Z", endUTC: "2026-09-21T00:00:00Z",
      timezone: "Europe/Vienna", selectionRevision: 1, records: [])
    let read: NativeCalendarReadResult = try await withCheckedThrowingContinuation { done in
      native.queryCalendar(query) { done.resume(with: $0) }
    }
    XCTAssertTrue(read.events.isEmpty)
    XCTAssertEqual(store.remoteSyncAttempts, 0, "Calendar reads requested a remote source sync")
    let links: NativeCalendarLinkInspection = try await withCheckedThrowingContinuation { done in
      native.inspectCalendarLinks([]) { done.resume(with: $0) }
    }
    XCTAssertTrue(links.results.isEmpty)
    XCTAssertEqual(store.remoteSyncAttempts, 0, "Link inspection requested a remote source sync")
    let _: NativeAgendaStatus = try await withCheckedThrowingContinuation { done in
      native.synchronizeAgenda(
        records: [], preferences: ReminderPreferences(), displayCalendarIDs: []
      ) { done.resume(with: $0) }
    }
    XCTAssertEqual(
      store.remoteSyncAttempts, 0, "Local calendar work requested a remote source sync")
  }

  private static func pendingOpen(_ service: AgendaService, acknowledge: String? = nil)
    async throws -> String?
  {
    let native = NativeServices(agenda: service)
    return try await withCheckedThrowingContinuation { continuation in
      native.pendingEventOpen(acknowledge: acknowledge) { continuation.resume(with: $0) }
    }
  }
  private static func legacyPendingOpen(_ service: AgendaService, acknowledge: String? = nil)
    async throws -> String?
  {
    let native = NativeServices(agenda: service)
    let arguments = try JSONSerialization.data(
      withJSONObject: acknowledge.map { ["acknowledge": $0] } ?? [:])
    let response: Data = try await withCheckedThrowingContinuation { continuation in
      native.perform("pendingEventOpen", arguments: arguments) {
        continuation.resume(with: $0)
      }
    }
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
    XCTAssertEqual(Set(value.keys), ["id"])
    XCTAssertTrue(value["id"] is String || value["id"] is NSNull)
    return value["id"] as? String
  }

  func testPendingNotificationLinkSurvivesFailedAcknowledgement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("agenda-private-v1.json")
    let id = UUID().uuidString
    let original = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1, "records": [], "journal": [:], "migrationVersion": 0,
      "preferences": ["enabled": false, "minutes": 10, "sound": true, "preview": true],
      "pendingOpen": id, "displayCalendarIDs": [],
    ])
    try original.write(to: file, options: .atomic)
    let service = AgendaService(storageRoot: root, widgetRoot: root)
    service.start(registerBackground: false)
    let unacknowledged = try await Self.pendingOpen(service, acknowledge: "another-link")
    XCTAssertEqual(unacknowledged, id)
    XCTAssertEqual(try Data(contentsOf: file), original)
    let legacy = try await Self.legacyPendingOpen(service)
    XCTAssertEqual(legacy, id)

    // Block only this isolated journal destination, without relying on permissions.
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do {
      _ = try await Self.pendingOpen(service, acknowledge: id)
      XCTFail("A failed durable acknowledgement was reported as successful")
    } catch {}
    let retained = try await Self.pendingOpen(service)
    XCTAssertEqual(retained, id, "Failed acknowledgement lost the current notification link")
    do {
      _ = try await Self.legacyPendingOpen(service, acknowledge: id)
      XCTFail("Legacy acknowledgement hid the storage error")
    } catch {}
    let legacyRetained = try await Self.legacyPendingOpen(service)
    XCTAssertEqual(legacyRetained, id)

    try FileManager.default.removeItem(at: file)
    try original.write(to: file, options: .atomic)
    let reopened = AgendaService(storageRoot: root, widgetRoot: root)
    reopened.start(registerBackground: false)
    let recovered = try await Self.pendingOpen(reopened)
    XCTAssertEqual(recovered, id)
    let acknowledged = try await Self.pendingOpen(service, acknowledge: id)
    XCTAssertNil(acknowledged)
    let final = AgendaService(storageRoot: root, widgetRoot: root)
    final.start(registerBackground: false)
    let completed = try await Self.pendingOpen(final)
    XCTAssertNil(completed, "Durably acknowledged notification reappeared after reopening")
    let legacyCompleted = try await Self.legacyPendingOpen(final)
    XCTAssertNil(legacyCompleted)
  }

  func testLocalErasureDoesNotRequireAnAccessibleCalendar() async throws {
    #if targetEnvironment(simulator)
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let service = AgendaService(storageRoot: root, widgetRoot: root)
      service.start(registerBackground: false)
      let record = OwnedRecord(
        status: "saved", id: UUID().uuidString,
        calendar_id: "inaccessible-calendar", external_id: "missing-event",
        approved: Values(
          title: "Erfundener Termin", start_utc: "2026-09-17T09:00:00Z",
          end_utc: "2026-09-17T09:30:00Z", timezone: "Europe/Vienna", location: "",
          notes: "", reminder_minutes: 10))
      let _: Void = try await withCheckedThrowingContinuation { continuation in
        service.queue.async {
          do {
            try service.sync(AgendaSyncArgs(records: [record], preferences: ReminderPreferences()))
            {
              continuation.resume(with: $0.map { _ in () })
            }
          } catch { continuation.resume(throwing: error) }
        }
      }
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        service.queue.async {
          do {
            try service.forget()
            continuation.resume()
          } catch { continuation.resume(throwing: error) }
        }
      }
      let privateState =
        try JSONSerialization.jsonObject(
          with: Data(
            contentsOf:
              root.appendingPathComponent("agenda-private-v1.json"))) as? [String: Any]
      XCTAssertEqual((privateState?["records"] as? [Any])?.count, 0)
      XCTAssertTrue(AgendaSnapshot.read(from: root).events.isEmpty)
    #else
      throw XCTSkip("Erasure regression uses isolated simulator data")
    #endif
  }
  @MainActor
  func testRenderActualWidgetAndNotificationViews() throws {
    let now = Date()
    let event = AgendaEvent(
      id: UUID().uuidString, start: now.addingTimeInterval(600).timeIntervalSince1970,
      end: now.addingTimeInterval(2400).timeIntervalSince1970, timezone: "Europe/Vienna",
      title: "Physiotherapie", room: "Raum 204")
    let events = [
      event,
      AgendaEvent(
        id: UUID().uuidString, start: event.start + 3600, end: event.end + 3600,
        timezone: event.timezone, title: "Bewegung & Balance", room: "Turnsaal"),
      AgendaEvent(
        id: UUID().uuidString, start: event.start + 7200, end: event.end + 7200,
        timezone: event.timezone, title: "Entspannung", room: ""),
    ]
    let entry = AgendaEntry(
      date: now,
      snapshot: AgendaSnapshot(
        updatedAt: now.timeIntervalSince1970, access: "available", events: events))
    for (name, family, width, height) in [
      ("small", WidgetFamily.systemSmall, 170.0, 170.0),
      ("medium", .systemMedium, 364.0, 180.0), ("lockscreen", .accessoryRectangular, 160.0, 76.0),
    ] {
      for dark in [false, true] {
        let view = AgendaWidgetContent(entry: entry, family: family)
          .environment(\.colorScheme, dark ? .dark : .light).environment(
            \.locale, Locale(identifier: "de_AT")
          )
          .padding(family == .accessoryRectangular ? 4 : 16).frame(width: width, height: height)
          .background(dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "030-widget-\(name)-\(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
    let renderer = ImageRenderer(
      content: NotificationCard(event: event, preview: true).frame(width: 350))
    renderer.scale = 3
    let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
    attachment.name = "030-notification-card"
    attachment.lifetime = .keepAlways
    add(attachment)
    let large = ImageRenderer(
      content: AgendaEventCard(event: event, date: now).environment(
        \.dynamicTypeSize, .accessibility2
      ).padding(24).frame(width: 350))
    let largeAttachment = XCTAttachment(image: try XCTUnwrap(large.uiImage))
    largeAttachment.name = "030-native-large-type"
    largeAttachment.lifetime = .keepAlways
    add(largeAttachment)
  }

  func testEventKitAgendaAndAlarmIsolation() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Grant simulator runner calendar access first")
      }
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let service = AgendaService(storageRoot: root, widgetRoot: root)
      service.start(registerBackground: false)
      let store = service.store
      let calendar = try XCTUnwrap(store.defaultCalendarForNewEvents)
      var event = EKEvent(eventStore: store)
      let id = UUID().uuidString
      event.calendar = calendar
      event.title = "Erfundene Agenda-Testtherapie"
      event.location = "Raum 204"
      event.notes = "Private Testnotiz: darf nicht im App Group Datensatz erscheinen"
      event.timeZone = TimeZone(identifier: "Europe/Vienna")
      event.startDate = Date().addingTimeInterval(7200)
      event.endDate = event.startDate.addingTimeInterval(1800)
      event.url = URL(string: "reha-calendar://event/\(id)")
      event.alarms = [EKAlarm(relativeOffset: -600)]
      try store.save(event, span: .thisEvent, commit: true)
      defer {
        try? store.remove(event, span: .thisEvent, commit: true)
        try? FileManager.default.removeItem(at: root)
      }
      let iso = ISO8601DateFormatter()
      let approved = Values(
        title: event.title, start_utc: iso.string(from: event.startDate),
        end_utc: iso.string(from: event.endDate), timezone: "Europe/Vienna",
        location: event.location!, notes: event.notes!, reminder_minutes: 10)
      let record = OwnedRecord(
        status: "saved", id: id, calendar_id: calendar.calendarIdentifier,
        external_id: event.eventIdentifier, approved: approved)
      let rejected = OwnedRecord(
        status: "uncertain", id: UUID().uuidString, calendar_id: calendar.calendarIdentifier,
        external_id: event.eventIdentifier, approved: approved)
      func sync(_ preferences: ReminderPreferences, visible: [String]? = nil) async throws
        -> NativeAgendaStatus
      {
        let visibleIDs = visible ?? [calendar.calendarIdentifier]
        return try await withCheckedThrowingContinuation { continuation in
          service.queue.async {
            do {
              try service.sync(
                AgendaSyncArgs(
                  records: [record, rejected], preferences: preferences,
                  display_calendar_ids: visibleIDs)
              ) { continuation.resume(with: $0) }
            } catch { continuation.resume(throwing: error) }
          }
        }
      }
      _ = try await sync(ReminderPreferences())
      var snapshot = AgendaSnapshot.read(from: root)
      XCTAssertEqual(snapshot.events.map(\.id), [id])
      XCTAssertEqual(snapshot.events.first?.title, approved.title)
      XCTAssertEqual(event.alarms?.count, 1)
      let json = try String(
        contentsOf: root.appendingPathComponent(AgendaSnapshot.filename), encoding: .utf8)
      XCTAssertFalse(json.contains("Private Testnotiz"))
      XCTAssertFalse(json.contains(calendar.calendarIdentifier))
      _ = try await sync(ReminderPreferences(), visible: [])
      XCTAssertTrue(
        AgendaSnapshot.read(from: root).events.isEmpty,
        "An owned save must not implicitly select its calendar for widgets")
      let foreign = EKEvent(eventStore: store)
      foreign.calendar = calendar
      foreign.title = "Sichtbarer externer Termin"
      foreign.startDate = event.endDate.addingTimeInterval(600)
      foreign.endDate = foreign.startDate.addingTimeInterval(1800)
      try store.save(foreign, span: .thisEvent, commit: true)
      _ = try await sync(ReminderPreferences())
      let external = try XCTUnwrap(
        AgendaSnapshot.read(from: root).events.first { $0.title == foreign.title })
      XCTAssertEqual(external.url.absoluteString, "reha-calendar://today")
      XCTAssertNotEqual(external.id, foreign.eventIdentifier)
      try store.remove(foreign, span: .thisEvent, commit: true)
      let permission = Task {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
      }
      let permissionDismissed = await MainActor.run {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons[
          "Allow"]
        let visible = XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == true AND hittable == true"), object: allow)
        guard XCTWaiter.wait(for: [visible], timeout: 10) == .completed else { return false }
        allow.tap()
        return allow.waitForNonExistence(timeout: 5)
      }
      guard permissionDismissed else {
        permission.cancel()
        XCTFail("Notification permission dialog could not be accepted")
        return
      }
      let allowed = try await permission.value
      XCTAssertTrue(allowed)
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      XCTAssertEqual(settings.authorizationStatus, .authorized)
      let activated = try await sync(ReminderPreferences(enabled: true))
      XCTAssertNil(activated.reminders.error)
      let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
      XCTAssertEqual(requests.filter { $0.identifier == "reha.event.\(id)" }.count, 1)
      XCTAssertTrue((store.event(withIdentifier: event.eventIdentifier)?.alarms ?? []).isEmpty)
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        service.queue.async {
          service.snooze(id: id) { result in continuation.resume(with: result.map { _ in () }) }
        }
      }
      let snoozed = await UNUserNotificationCenter.current().pendingNotificationRequests()
      XCTAssertTrue(snoozed.contains { $0.identifier.hasPrefix("reha.snooze.\(id).") })
      _ = try await sync(ReminderPreferences())
      let disabled = await UNUserNotificationCenter.current().pendingNotificationRequests()
      XCTAssertFalse(disabled.contains { $0.identifier.contains(id) })
      XCTAssertEqual(
        store.event(withIdentifier: event.eventIdentifier)?.alarms?.first?.relativeOffset, -600)
      // Re-fetch as the Calendar app would, after the service changed alarms.
      event = try XCTUnwrap(store.event(withIdentifier: event.eventIdentifier))
      // Manual calendar corrections must be read, never overwritten.
      event.title = "Manuell korrigierte Therapie"
      event.location = "Raum 303"
      event.startDate = event.startDate.addingTimeInterval(900)
      event.endDate = event.endDate.addingTimeInterval(900)
      event.alarms = [EKAlarm(relativeOffset: -300), EKAlarm(relativeOffset: -900)]
      try store.save(event, span: .thisEvent, commit: true)
      _ = try await sync(ReminderPreferences(enabled: true))
      snapshot = AgendaSnapshot.read(from: root)
      XCTAssertEqual(snapshot.events.first?.title, "Manuell korrigierte Therapie")
      XCTAssertEqual(snapshot.events.first?.room, "Raum 303")
      XCTAssertEqual(event.alarms?.count, 2)
      XCTAssertEqual(record.approved, approved)
      // Confirmed deletion removes both the visible event and any alerts.
      try store.remove(event, span: .thisEvent, commit: true)
      _ = try await sync(ReminderPreferences())
      snapshot = AgendaSnapshot.read(from: root)
      XCTAssertEqual(snapshot.deletedIDs, [id])
      XCTAssertTrue(snapshot.events.isEmpty)
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
}
