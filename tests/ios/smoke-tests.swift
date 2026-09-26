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
    let fixedActions = ["Heute", "Pläne", "Einstellungen", "Importieren", "Einstellungen speichern", "Auswahl geprüft – weiter", "Im Kalender speichern", "Auswahl als ICS exportieren", "Termin bestätigen", "Angaben speichern", "Schließen"]
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
      XCTAssertTrue(app.buttons["Heute"].waitForExistence(timeout: 15))
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

  /// Opens the same scheme used by every WidgetKit family, with the app stopped
  /// and already running. An absent import must lead back to the day overview.
  func testColdAndWarmAgendaLinks() {
    continueAfterFailure = false
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.alerts.buttons["Cancel"].exists { springboard.alerts.buttons["Cancel"].tap() }
    let app = XCUIApplication(bundleIdentifier: bundle)
    app.terminate()
    for index in 0..<2 {
      app.open(URL(string: "reha-calendar://event/11111111-2222-3333-4444-555555555555")!)
      XCTAssertTrue(app.buttons["Zur Tagesübersicht"].waitForExistence(timeout: 15), app.debugDescription)
      let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "030-native-link-\(index == 0 ? "cold" : "warm")"; shot.lifetime = .keepAlways; add(shot)
      app.buttons["Zur Tagesübersicht"].tap()
      XCTAssertTrue(app.buttons["Heute"].waitForExistence(timeout: 10), app.debugDescription)
    }
  }

  func testSimulatorExpandedTestNotification() throws {
    try exerciseTestNotification(coldStart: false)
  }

  func testSimulatorColdTestNotification() throws {
    try exerciseTestNotification(coldStart: true)
  }

  func testSimulatorWidgetGallery() throws {
    #if targetEnvironment(simulator)
      continueAfterFailure = false
      XCUIApplication(bundleIdentifier: bundle).launch()
      XCUIDevice.shared.press(.home)
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(forDuration: 2)
      let edit = springboard.buttons["Edit"]
      XCTAssertTrue(edit.waitForExistence(timeout: 10), springboard.debugDescription)
      edit.tap()
      let addWidget = springboard.buttons["Add Widget"]
      XCTAssertTrue(addWidget.waitForExistence(timeout: 10), springboard.debugDescription)
      addWidget.tap()
      let search = springboard.searchFields.firstMatch
      XCTAssertTrue(search.waitForExistence(timeout: 10), springboard.debugDescription)
      search.tap(); search.typeText("Termine")
      let result = springboard.cells["Termine"].firstMatch
      XCTAssertTrue(result.waitForExistence(timeout: 10), springboard.debugDescription)
      result.tap()
      XCTAssertTrue(springboard.staticTexts["Deine Termine"].waitForExistence(timeout: 15), springboard.debugDescription)
      // SpringBoard exposes the archived widget preview as a single button;
      // its rendered text is inspected in the screenshot, not separate AX nodes.
      let widgetPreview = springboard.buttons["Termine, Deine Termine"].firstMatch
      XCTAssertTrue(widgetPreview.waitForExistence(timeout: 15), springboard.debugDescription)
      let shot = XCTAttachment(screenshot: springboard.screenshot()); shot.name = "030-system-widget-gallery"; shot.lifetime = .keepAlways; add(shot)
    #else
      throw XCTSkip("Widget placement on a personal phone remains the user's choice")
    #endif
  }

  private func exerciseTestNotification(coldStart: Bool) throws {
    #if targetEnvironment(simulator)
      continueAfterFailure = false
      let app = XCUIApplication(bundleIdentifier: bundle)
      app.launch()
      tap("Einstellungen", in: app)
      let activation = app.buttons["Erinnerungen aktivieren"]
      if activation.exists {
        scrollTo(activation, in: app); activation.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Erlauben"])).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
      }
      let test = app.buttons["Testmitteilung in 15 Sekunden"]
      XCTAssertTrue(test.waitForExistence(timeout: 10)); scrollTo(test, in: app)
      XCTAssertTrue(test.isEnabled); test.tap()
      let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Testmitteilung in 15 Sekunden. Du kannst dein iPhone jetzt sperren.")).firstMatch
      XCTAssertTrue(notice.waitForExistence(timeout: 15), app.debugDescription)
      XCUIDevice.shared.press(.home)
      if coldStart { app.terminate() }
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let notification = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Test: Physiotherapie")).firstMatch
      XCTAssertTrue(notification.waitForExistence(timeout: 25), springboard.debugDescription)
      notification.press(forDuration: 1.5)
      XCTAssertTrue(springboard.buttons["Termin öffnen"].waitForExistence(timeout: 10), springboard.debugDescription)
      XCTAssertTrue(springboard.staticTexts["DEIN NÄCHSTER TERMIN"].waitForExistence(timeout: 15), springboard.debugDescription)
      let shot = XCTAttachment(screenshot: springboard.screenshot()); shot.name = "030-system-expanded-notification-\(coldStart ? "cold" : "warm")"; shot.lifetime = .keepAlways; add(shot)
      springboard.buttons["Termin öffnen"].tap()
      XCTAssertTrue(app.staticTexts["Das war eine Testmitteilung mit einem erfundenen Termin."].waitForExistence(timeout: 15))
    #else
      throw XCTSkip("Use the separately coordinated physical lock-screen test")
    #endif
  }

  /// Run explicitly on the connected phone when the user is ready to lock it.
  /// This schedules only the app's invented test message; regular reminders are
  /// enabled only through the app's existing activation control.
  func testPhysicalTestReminder() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Physical lock-screen acceptance is a separate check")
    #else
      continueAfterFailure = false
      let app = XCUIApplication(bundleIdentifier: bundle)
      app.launch()
      tap("Einstellungen", in: app)
      let activation = app.buttons["Erinnerungen aktivieren"]
      if activation.exists {
        scrollTo(activation, in: app)
        activation.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Erlauben"])).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
      }
      let test = app.buttons["Testmitteilung in 15 Sekunden"]
      XCTAssertTrue(test.waitForExistence(timeout: 10))
      scrollTo(test, in: app)
      XCTAssertTrue(test.isEnabled, "iOS notification permission is required")
      test.tap()
      let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Testmitteilung in 15 Sekunden. Du kannst dein iPhone jetzt sperren.")).firstMatch
      XCTAssertTrue(notice.waitForExistence(timeout: 10))
      let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "030-physical-test-scheduled"; shot.lifetime = .keepAlways; add(shot)
      XCUIDevice.shared.press(.home)
      // The user now locks the phone. iOS presents the app's actual notification.
    #endif
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
