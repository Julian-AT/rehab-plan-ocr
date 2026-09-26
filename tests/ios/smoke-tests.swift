import EventKit
import XCTest

/// Exercises the packaged webview and native runtime using invented data only.
final class SmokeTests: XCTestCase {
  private let bundle = "at.rehakalender.personal"

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<12 {
      if element.isHittable && element.frame.midY > 60 && element.frame.midY < min(740, app.frame.height - 160) { return }
      if element.frame.midY < 60 { app.swipeDown() } else { app.swipeUp() }
    }
  }

  private func tap(_ label: String, in app: XCUIApplication) {
    let element = app.buttons[label].firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
    let fixedActions = ["Einstellungen speichern", "Auswahl geprüft – weiter", "Im Kalender speichern", "Auswahl als ICS exportieren", "Termin bestätigen", "Angaben speichern", "Schließen"]
    if !fixedActions.contains(label) || !element.isHittable {
      scrollTo(element, in: app)
    }
    element.tap()
  }

  private func openWorkbench(in app: XCUIApplication) {
    tap("Einstellungen", in: app)
    tap("Entwickleransicht öffnen", in: app)
  }

  /// Safe on a physical phone: no scans or calendar entries are changed.
  func testLaunchAndResume() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundle)
    for _ in 0..<2 {
      app.launch()
      XCTAssertTrue(app.buttons["Foto aufnehmen"].waitForExistence(timeout: 15))
      XCTAssertFalse(app.buttons["Load fixture"].exists)
      tap("Einstellungen", in: app)
      tap("Schließen", in: app)
      XCUIDevice.shared.press(.home)
      app.activate()
      XCTAssertTrue(app.buttons["Importieren"].waitForExistence(timeout: 15))
      XCTAssertEqual(app.state, .runningForeground)
      app.terminate()
    }
  }

  func testNativePortableRecognitionAndPersistence() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: bundle)
    app.launch()
    openWorkbench(in: app)
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
    openWorkbench(in: app)
    tap("History", in: app)
    tap("Open", in: app)
    XCTAssertTrue(selected.waitForExistence(timeout: 10))
  }

  /// Run after `simctl privacy revoke calendar at.rehakalender.personal`.
  /// Normal suites skip this check when the target app already has access.
  func testDeniedCalendarAccess() throws {
    #if targetEnvironment(simulator)
      continueAfterFailure = false
      let app = XCUIApplication(bundleIdentifier: bundle)
      app.launch()
      openWorkbench(in: app)
      tap("Load fixture", in: app)
      XCTAssertTrue(app.staticTexts["synthetic-day.png"].waitForExistence(timeout: 90))
      tap("Zurück zu Terminen", in: app)
      tap("In Kalender übernehmen", in: app)
      tap("Kalender verbinden", in: app)
      let denied = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Kalenderzugriff abgelehnt")).firstMatch
      guard denied.waitForExistence(timeout: 5) else {
        throw XCTSkip("Revoke calendar access for the target app before running this check.")
      }
      XCTAssertTrue(app.buttons["Auswahl als ICS exportieren"].isEnabled)
      XCTAssertFalse(app.buttons["Auswahl geprüft – weiter"].isEnabled)
      tap("Schließen", in: app)
      XCTAssertTrue(app.buttons["11:15 Übungen im Wasser bearbeiten"].exists)
      app.terminate()
      app.launch()
      XCTAssertTrue(app.buttons["Plan öffnen"].firstMatch.waitForExistence(timeout: 15))
    #else
      throw XCTSkip("Permission mutations are restricted to the simulator.")
    #endif
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
      openWorkbench(in: app)
      tap("History", in: app)
      tap("Delete all app data", in: app)
      tap("Confirm", in: app)
      tap("Run", in: app)
      tap("Load fixture", in: app)
      XCTAssertTrue(app.staticTexts["synthetic-day.png"].waitForExistence(timeout: 90))
      tap("Zurück zu Terminen", in: app)
      tap("In Kalender übernehmen", in: app)
      tap("Kalender verbinden", in: app)
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
        tap("Auswahl geprüft – weiter", in: app)
        tap("Im Kalender speichern", in: app)
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

      tap("Schließen", in: app)
      // The missing-duration appointment stays pending and can be saved later.
      tap("11:15 Übungen im Wasser bearbeiten", in: app)
      let duration = app.textFields["Dauer (Minuten)"]
      scrollTo(duration, in: app)
      duration.tap()
      duration.typeText("30")
      tap("Termin bestätigen", in: app)
      tap("In Kalender übernehmen", in: app)
      tap("Kalender verbinden", in: app)
      tap("Auswahl geprüft – weiter", in: app)
      tap("Im Kalender speichern", in: app)
      let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        owned().filter { !baseline.contains($0.eventIdentifier) }.count == 8
      }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)

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
      openWorkbench(in: app)
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
