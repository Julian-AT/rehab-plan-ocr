import EventKit
import XCTest

/// Exercises the packaged webview and native runtime using invented data only.
final class SmokeTests: XCTestCase {
  private let bundle = "at.rehakalender.personal"

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<12 {
      if element.isHittable && element.frame.midY > 100 && element.frame.midY < 740 { return }
      if element.frame.midY < 100 { app.swipeDown() } else { app.swipeUp() }
    }
  }

  private func tap(_ label: String, in app: XCUIApplication) {
    let element = app.buttons[label].firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
    scrollTo(element, in: app)
    element.tap()
  }

  /// Safe on a physical phone: no scans or calendar entries are changed.
  func testLaunchAndResume() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundle)
    for _ in 0..<2 {
      app.launch()
      XCTAssertTrue(app.buttons["Load fixture"].waitForExistence(timeout: 15))
      tap("History", in: app)
      tap("Run", in: app)
      XCUIDevice.shared.press(.home)
      app.activate()
      XCTAssertTrue(app.buttons["Load fixture"].waitForExistence(timeout: 15))
      XCTAssertEqual(app.state, .runningForeground)
      app.terminate()
    }
  }

  func testNativePortableRecognitionAndPersistence() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundle)
    app.launch()
    tap("Load fixture", in: app)
    let selected = app.staticTexts["synthetic-day.png"]
    XCTAssertTrue(selected.waitForExistence(timeout: 90), app.debugDescription)
    XCTAssertEqual(
      app.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "Title row")).count, 8)
    XCTAssertEqual(app.textFields["Title row 4"].value as? String, "Entspannung")
    XCTAssertEqual(app.textFields["Title row 5"].value as? String, "Entspannung")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Next.js workbench with portable OCR"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    tap("Trace", in: app)
    XCTAssertTrue(app.staticTexts["Engine scores are uncalibrated."].waitForExistence(timeout: 5))
    tap("History", in: app)
    XCTAssertTrue(app.buttons["Open"].firstMatch.waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    tap("History", in: app)
    tap("Open", in: app)
    XCTAssertTrue(selected.waitForExistence(timeout: 10))
  }

  func testNativeCalendarRoundTripAndDuplicatePrevention() throws {
    #if targetEnvironment(simulator)
      continueAfterFailure = false
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator test runner requires full calendar access.")
      }
      let store = EKEventStore()
      guard let defaultCalendar = store.defaultCalendarForNewEvents,
        defaultCalendar.allowsContentModifications
      else {
        throw XCTSkip("Simulator has no writable default calendar.")
      }
      let start = ISO8601DateFormatter().date(from: "2026-09-09T00:00:00Z")!
      let end = ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")!
      let originalCalendarIDs = Set(store.calendars(for: .event).map(\.calendarIdentifier))
      let defaultID = defaultCalendar.calendarIdentifier
      var dedicatedID: String?
      func owned() -> [EKEvent] {
        store.reset()
        return store.events(
          matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)
        ).filter { $0.url?.scheme == "reha-calendar" }
      }
      let baseline = Set(owned().compactMap(\.eventIdentifier))
      defer {
        for event in owned() where !baseline.contains(event.eventIdentifier) {
          try? store.remove(event, span: .thisEvent, commit: true)
        }
        if let dedicatedID, !originalCalendarIDs.contains(dedicatedID),
          let calendar = store.calendar(withIdentifier: dedicatedID)
        {
          try? store.removeCalendar(calendar, commit: true)
        }
      }
      let app = XCUIApplication(bundleIdentifier: bundle)
      app.launch()
      tap("History", in: app)
      tap("Delete all app data", in: app)
      tap("Confirm", in: app)
      tap("Run", in: app)
      tap("Load fixture", in: app)
      XCTAssertTrue(app.staticTexts["synthetic-day.png"].waitForExistence(timeout: 90))
      let missing = app.switches["Include row 6"]
      scrollTo(missing, in: app)
      missing.tap()
      let reviewed = app.switches["Review confirmed, including unassigned observations"]
      scrollTo(reviewed, in: app)
      reviewed.tap()
      tap("Calendar", in: app)
      tap("Set up Reha Calendar", in: app)
      let setup = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          store.reset()
          return store.calendars(for: .event).contains { $0.title == "Reha Calendar" }
        }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [setup], timeout: 15), .completed)
      let calendar = try XCTUnwrap(
        store.calendars(for: .event).first { $0.title == "Reha Calendar" })
      dedicatedID = calendar.calendarIdentifier
      XCTAssertNotEqual(dedicatedID, defaultID)
      let calendarCount = store.calendars(for: .event).count
      for _ in 0..<2 {
        tap("Prepare calendar operations", in: app)
        tap("Approve and apply", in: app)
        let predicate = NSPredicate { _, _ in
          owned().filter { !baseline.contains($0.eventIdentifier) }.count == 7
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        XCTAssertEqual(owned().filter { !baseline.contains($0.eventIdentifier) }.count, 7)
        XCTAssertTrue(
          owned().filter { !baseline.contains($0.eventIdentifier) }.allSatisfy {
            $0.calendar.calendarIdentifier == dedicatedID
          })
      }

      // Reconnect after a relaunch and a user rename: the same calendar is reused.
      app.terminate()
      let renamed = try XCTUnwrap(store.calendar(withIdentifier: try XCTUnwrap(dedicatedID)))
      let originalTitle = renamed.title
      renamed.title = "Reha Calendar renamed"
      try store.saveCalendar(renamed, commit: true)
      defer {
        if let calendar = store.calendar(withIdentifier: renamed.calendarIdentifier) {
          calendar.title = originalTitle
          try? store.saveCalendar(calendar, commit: true)
        }
      }
      app.launch()
      tap("History", in: app)
      tap("Open", in: app)
      tap("Calendar", in: app)
      tap("Set up Reha Calendar", in: app)
      let prepare = app.buttons["Prepare calendar operations"]
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in prepare.isEnabled }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
      store.reset()
      XCTAssertEqual(store.calendars(for: .event).count, calendarCount)
      XCTAssertEqual(
        store.calendar(withIdentifier: try XCTUnwrap(dedicatedID))?.title, "Reha Calendar renamed")
      XCTAssertEqual(store.defaultCalendarForNewEvents?.calendarIdentifier, defaultID)
    #else
      throw XCTSkip("Calendar writes are restricted to simulator tests.")
    #endif
  }
}
