import EventKit
import SwiftUI
import UserNotifications
import WidgetKit
import XCTest

final class AgendaNativeTests: XCTestCase {
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
      func sync(_ preferences: ReminderPreferences) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
          service.queue.async {
            do {
              continuation.resume(
                returning: try service.sync(
                  AgendaSyncArgs(records: [record, rejected], preferences: preferences)))
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
      let permission = expectation(description: "Notification authorization")
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
        permission.fulfill()
      }
      let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
      if allow.waitForExistence(timeout: 3) { allow.tap() }
      await fulfillment(of: [permission], timeout: 10)
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      XCTAssertEqual(settings.authorizationStatus, .authorized)
      let activated = try await sync(ReminderPreferences(enabled: true))
      XCTAssertNil((activated["reminders"] as? [String: Any])?["error"] as? String)
      let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
      XCTAssertEqual(requests.filter { $0.identifier == "reha.event.\(id)" }.count, 1)
      XCTAssertTrue((store.event(withIdentifier: event.eventIdentifier)?.alarms ?? []).isEmpty)
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        service.queue.async {
          do {
            try service.snooze(id: id)
            continuation.resume()
          } catch { continuation.resume(throwing: error) }
        }
      }
      let snoozed = await UNUserNotificationCenter.current().pendingNotificationRequests()
      XCTAssertTrue(snoozed.contains { $0.identifier == "reha.snooze.\(id)" })
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
