import EventKit
import UserNotifications
import XCTest

private final class ControlledNotifications: NotificationAdapter, @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [String: UNNotificationRequest] = [:]
  private var held: [CheckedContinuation<Void, Never>] = []
  private var hold = false
  private var failure = false
  private var installBeforeHolding = false
  private var onHold: (() -> Void)?
  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
  func suspendAdds(installed: Bool = false, _ callback: @escaping () -> Void) {
    locked {
      hold = true
      installBeforeHolding = installed
      onHold = callback
    }
  }
  func allowNewAdds() { locked { hold = false } }
  func failAdds() { locked { failure = true } }
  func resumeAdds() {
    let callbacks = locked {
      let result = held
      held = []
      hold = false
      return result
    }
    for callback in callbacks { callback.resume() }
  }
  func snapshot() async -> NotificationSnapshot {
    locked {
      NotificationSnapshot(
        authorization: .authorized, pending: Array(requests.values), delivered: [])
    }
  }
  func add(_ request: UNNotificationRequest) async throws {
    await withCheckedContinuation { continuation in
      let callback: (() -> Void)? = locked {
        if hold {
          if installBeforeHolding { requests[request.identifier] = request }
          held.append(continuation)
          return onHold
        }
        continuation.resume()
        return nil
      }
      callback?()
    }
    try locked {
      if failure { throw AgendaError.message("Simulierter Planungsfehler") }
      requests[request.identifier] = request
    }
  }
  func removePending(_ ids: [String]) {
    locked { for id in ids { requests.removeValue(forKey: id) } }
  }
  func removeDelivered(_ ids: [String]) {}
}

final class NotificationRaceTests: XCTestCase {
  private func fixture(_ adapter: ControlledNotifications, timeout: TimeInterval = 3) throws -> (
    AgendaService, URL
  ) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let service = AgendaService(
      storageRoot: root, widgetRoot: root, notifications: adapter, notificationTimeout: timeout)
    service.start(registerBackground: false)
    return (service, root)
  }
  private static func testNotification(_ service: AgendaService) async throws
    -> NativeNotificationReceipt
  {
    try await withCheckedThrowingContinuation { continuation in
      service.queue.async {
        service.testNotification { continuation.resume(with: $0) }
      }
    }
  }
  private static func sync(_ service: AgendaService, records: [OwnedRecord], enabled: Bool)
    async throws -> NativeAgendaStatus
  {
    try await withCheckedThrowingContinuation { continuation in
      service.queue.async {
        do {
          try service.sync(
            AgendaSyncArgs(records: records, preferences: ReminderPreferences(enabled: enabled))
          ) { continuation.resume(with: $0) }
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  func testTypedStatusAndCompatibilityDoNotEnableReminders() async throws {
    let (service, root) = try fixture(ControlledNotifications())
    defer { try? FileManager.default.removeItem(at: root) }
    let native = NativeServices(agenda: service)
    let stateURL = root.appendingPathComponent("agenda-private-v1.json")
    let before = try? Data(contentsOf: stateURL)
    let status: NativeAgendaStatus = try await withCheckedThrowingContinuation { continuation in
      native.reminderStatus { continuation.resume(with: $0) }
    }
    XCTAssertEqual(status.reminders.authorization, .authorized)
    XCTAssertFalse(status.reminders.enabled)
    XCTAssertEqual(status.reminders.confirmedPending, 0)
    XCTAssertEqual(status.reminders.observedDelivered, 0)
    let legacy: Data = try await withCheckedThrowingContinuation { continuation in
      native.perform("reminderStatus", arguments: Data("{}".utf8)) {
        continuation.resume(with: $0)
      }
    }
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
    let reminders = try XCTUnwrap(object["reminders"] as? [String: Any])
    XCTAssertEqual(reminders["authorization"] as? String, "authorized")
    XCTAssertEqual(reminders["enabled"] as? Bool, false)
    XCTAssertTrue(reminders["error"] is NSNull)
    XCTAssertEqual(try? Data(contentsOf: stateURL), before)
  }
  func testFiveSecondAcceptanceAndImmediateFailure() async throws {
    let adapter = ControlledNotifications()
    let (service, root) = try fixture(adapter)
    defer { try? FileManager.default.removeItem(at: root) }
    let result = try await NotificationRaceTests.testNotification(service)
    XCTAssertEqual(result.delaySeconds, 5)
    XCTAssertEqual(result.confirmedPending, true)
    XCTAssertEqual(result.observedDelivered, false)
    adapter.failAdds()
    do {
      _ = try await NotificationRaceTests.testNotification(service)
      XCTFail("Failed add was accepted")
    } catch {}
  }
  func testTimeoutRecoversAndLateAddCannotSurviveForget() async throws {
    let adapter = ControlledNotifications()
    let (service, root) = try fixture(adapter, timeout: 0.15)
    defer { try? FileManager.default.removeItem(at: root) }
    let held = expectation(description: "Add suspended")
    adapter.suspendAdds { held.fulfill() }
    let pending = Task { _ = try await NotificationRaceTests.testNotification(service) }
    await fulfillment(of: [held], timeout: 2)
    do {
      _ = try await pending.value
      XCTFail("Stalled add did not time out")
    } catch {}
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      service.queue.async { continuation.resume(with: Result { try service.forget() }) }
    }
    adapter.resumeAdds()
    // Queue barrier is insufficient because completion includes an async snapshot.
    try await Task.sleep(for: .milliseconds(100))
    let snapshot = await adapter.snapshot()
    XCTAssertFalse(snapshot.pending.contains { $0.identifier.hasPrefix("reha.test") })
    let retry = try await NotificationRaceTests.testNotification(service)
    XCTAssertEqual(retry.accepted, true)
  }
  func testLateTimedOutTestCannotRemoveItsSuccessfulReplacement() async throws {
    let adapter = ControlledNotifications()
    let (service, root) = try fixture(adapter, timeout: 0.15)
    defer { try? FileManager.default.removeItem(at: root) }
    let held = expectation(description: "First test suspended")
    adapter.suspendAdds { held.fulfill() }
    let first = Task { _ = try await NotificationRaceTests.testNotification(service) }
    await fulfillment(of: [held], timeout: 2)
    do {
      _ = try await first.value
      XCTFail("Expected timeout")
    } catch {}
    adapter.allowNewAdds()
    let replacement = try await NotificationRaceTests.testNotification(service)
    XCTAssertEqual(replacement.confirmedPending, true)
    let before = await adapter.snapshot().pending.map(\.identifier)
    adapter.resumeAdds()
    try await Task.sleep(for: .milliseconds(100))
    let after = await adapter.snapshot().pending.map(\.identifier)
    XCTAssertEqual(after, before)
    XCTAssertEqual(after.count, 1)
  }
  func testUnresolvedBatchCannotLoseCalendarReserveDuringRetry() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let adapter = ControlledNotifications()
      let (service, root) = try fixture(adapter, timeout: 0.15)
      let store = service.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundene verzögerte Erinnerung"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer {
        try? store.removeCalendar(calendar, commit: true)
        try? FileManager.default.removeItem(at: root)
      }
      let id = UUID().uuidString
      let event = EKEvent(eventStore: store)
      event.calendar = calendar
      event.title = "Erfundener Termin"
      event.startDate = Date().addingTimeInterval(7200)
      event.endDate = event.startDate.addingTimeInterval(1800)
      event.url = URL(string: "reha-calendar://event/\(id)")
      event.timeZone = TimeZone(identifier: "Europe/Vienna")
      event.alarms = [EKAlarm(relativeOffset: -600)]
      try store.save(event, span: .thisEvent)
      let iso = ISO8601DateFormatter()
      let record = OwnedRecord(
        status: "saved", id: id, calendar_id: calendar.calendarIdentifier,
        external_id: event.eventIdentifier,
        approved: Values(
          title: event.title, start_utc: iso.string(from: event.startDate),
          end_utc: iso.string(from: event.endDate), timezone: "Europe/Vienna", location: "",
          notes: "", reminder_minutes: 10))
      let held = expectation(description: "OS installed request before stalled callback")
      adapter.suspendAdds(installed: true) { held.fulfill() }
      let first = Task {
        _ = try await NotificationRaceTests.sync(service, records: [record], enabled: true)
      }
      await fulfillment(of: [held], timeout: 2)
      _ = try await first.value
      adapter.allowNewAdds()
      _ = try await NotificationRaceTests.sync(service, records: [record], enabled: true)
      XCTAssertEqual(
        store.event(withIdentifier: event.eventIdentifier)?.alarms?.first?.relativeOffset, -600)
      adapter.resumeAdds()
      try await Task.sleep(for: .milliseconds(200))
      _ = try await NotificationRaceTests.sync(service, records: [record], enabled: true)
      let snapshot = await adapter.snapshot()
      XCTAssertEqual(snapshot.pending.filter { $0.identifier.hasPrefix("reha.event.") }.count, 1)
      XCTAssertTrue(store.event(withIdentifier: event.eventIdentifier)?.alarms?.isEmpty ?? true)
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
  func testSnoozeReservationsAndDisableDuringAdd() async throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator calendar access required")
      }
      let adapter = ControlledNotifications()
      let (service, root) = try fixture(adapter)
      let store = service.store
      let calendar = EKCalendar(for: .event, eventStore: store)
      calendar.title = "Erfundene Erinnerungstests"
      calendar.source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
      try store.saveCalendar(calendar, commit: true)
      defer {
        try? store.removeCalendar(calendar, commit: true)
        try? FileManager.default.removeItem(at: root)
      }
      let iso = ISO8601DateFormatter()
      var records: [OwnedRecord] = []
      for index in 0..<4 {
        let id = UUID().uuidString
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "Erfundener Termin \(index)"
        event.startDate = Date().addingTimeInterval(7200 + Double(index) * 3600)
        event.endDate = event.startDate.addingTimeInterval(1800)
        event.timeZone = TimeZone(identifier: "Europe/Vienna")
        event.url = URL(string: "reha-calendar://event/\(id)")
        event.alarms = [EKAlarm(relativeOffset: -600)]
        try store.save(event, span: .thisEvent, commit: true)
        records.append(
          OwnedRecord(
            status: "saved", id: id, calendar_id: calendar.calendarIdentifier,
            external_id: event.eventIdentifier,
            approved: Values(
              title: event.title, start_utc: iso.string(from: event.startDate),
              end_utc: iso.string(from: event.endDate), timezone: "Europe/Vienna", location: "",
              notes: "", reminder_minutes: 10)))
      }
      _ = try await NotificationRaceTests.sync(service, records: records, enabled: true)
      let held = expectation(description: "Three snoozes reserved")
      held.expectedFulfillmentCount = 3
      adapter.suspendAdds { held.fulfill() }
      func snooze(_ id: String) async throws -> NativeNotificationReceipt {
        try await withCheckedThrowingContinuation { continuation in
          service.queue.async {
            service.snooze(id: id) { continuation.resume(with: $0) }
          }
        }
      }
      let first = records.prefix(3).map { record in Task { _ = try await snooze(record.id) } }
      await fulfillment(of: [held], timeout: 2)
      do {
        _ = try await snooze(records[3].id)
        XCTFail("Fourth snooze exceeded reserved capacity")
      } catch {}
      _ = try await NotificationRaceTests.sync(service, records: records, enabled: false)
      adapter.resumeAdds()
      for task in first {
        do {
          _ = try await task.value
          XCTFail("Disabled snooze was accepted")
        } catch {}
      }
      let snapshot = await adapter.snapshot()
      XCTAssertFalse(snapshot.pending.contains { $0.identifier.hasPrefix("reha.snooze.") })
      for record in records {
        XCTAssertEqual(
          store.event(withIdentifier: record.external_id!)?.alarms?.first?.relativeOffset, -600)
      }
    #else
      throw XCTSkip("EventKit mutation tests use simulator data only")
    #endif
  }
}
