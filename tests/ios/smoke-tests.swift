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
      guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications
      else {
        throw XCTSkip("Simulator has no writable default calendar.")
      }
      let start = ISO8601DateFormatter().date(from: "2026-09-09T00:00:00Z")!
      let end = ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")!
      func owned() -> [EKEvent] {
        store.reset()
        return store.events(
          matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        ).filter { $0.url?.scheme == "reha-calendar" }
      }
      let baseline = Set(owned().compactMap(\.eventIdentifier))
      defer {
        for event in owned() where !baseline.contains(event.eventIdentifier) {
          try? store.remove(event, span: .thisEvent, commit: true)
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
      tap("Connect EventKit", in: app)
      for _ in 0..<2 {
        tap("Prepare calendar operations", in: app)
        tap("Approve and apply", in: app)
        let predicate = NSPredicate { _, _ in
          owned().filter { !baseline.contains($0.eventIdentifier) }.count == 7
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
        XCTAssertEqual(owned().filter { !baseline.contains($0.eventIdentifier) }.count, 7)
      }
    #else
      throw XCTSkip("Calendar writes are restricted to simulator tests.")
    #endif
  }
}
