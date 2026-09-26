import XCTest

@MainActor final class ContinuousCalendarTests: XCTestCase {
  private var app: XCUIApplication!
  private func launch(_ mode: String = "readable", extra: [String] = []) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", mode] + extra
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: app.tabBars.buttons["Termine"])
    waitForExpectations(timeout: 20)
  }
  override func tearDown() async throws {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    // The shell appears only after PreviewFixtures.prepare has restored the
    // original preferences and removed the synthetic calendars.
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    app.terminate()
  }
  private var pager: XCUIElement { app.scrollViews["agenda-days"].firstMatch }
  private var week: XCUIElement { app.descendants(matching: .any)["agenda-week"].firstMatch }
  private var state: XCUIElement { app.descendants(matching: .any)["voice-state"].firstMatch }
  private func event(_ title: String) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
    ).firstMatch
  }
  private func visible(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: element)
    waitForExpectations(timeout: 10)
  }
  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
  func testNativePagesWeeksAndCancelledDrag() {
    launch()
    pager.swipeLeft()
    visible(event("Physiotherapie Tag 1"))
    let firstY = event("Physiotherapie Tag 1").frame.minY
    capture("01-native-tagesseite")
    // Short drag returns to the same page; recording retains the intermediate state.
    let origin = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    origin.press(
      forDuration: 0.1,
      thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)),
      withVelocity: .slow, thenHoldForDuration: 0.5)
    visible(event("Physiotherapie Tag 1"))
    XCTAssertEqual(event("Physiotherapie Tag 1").frame.minY, firstY, accuracy: 2)
    week.swipeLeft()
    visible(event("Physiotherapie Tag 1"))  // browsing weeks must not select a day
    capture("02-wochenblaettern-getrennt")
    pager.swipeLeft()
    visible(event("Physiotherapie Tag 2"))
    pager.swipeRight()
    visible(event("Physiotherapie Tag 1"))
    for _ in 0..<6 { pager.swipeLeft() }
    visible(event("Physiotherapie Tag 7"))
    capture("03-wochengrenze")
    app.buttons["agenda-today"].tap()
    XCTAssertTrue(
      app.buttons["past-events"].waitForExistence(timeout: 5)
        || event("Physiotherapie Tag 0").exists)
  }
  func testColoursDarkAndLegend() {
    launch("colors", extra: ["--preview-dark"])
    pager.swipeLeft()
    visible(event("Frühstück I"))
    capture("04-kalender-dunkel")
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Darstellung"].tap()
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Terminfarben"].exists)
    XCTAssertTrue(app.staticTexts["Mahlzeiten"].exists)
    capture("05-farblegende")
  }
  func testTypedCalendarToolsKeepChangesAsDrafts() {
    launch("tool-probe")  // startup executes real tool/service integration assertions
    capture("06-gepruefte-kalenderwerkzeuge")
  }
  func testTimedRealPlaybackAndCancel() {
    launch("one", extra: ["--audio-evidence"])
    app.tabBars.buttons["Sprechen"].tap()
    XCTAssertEqual(app.buttons["speak"].label, "Gespräch starten")
    app.buttons["voice-details"].tap()
    app.buttons["voice-next"].tap()
    app.navigationBars["Gesprächsdetails"].buttons.firstMatch.tap()
    expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: state)
    waitForExpectations(timeout: 50)
    let response = app.staticTexts["voice-response"]
    expectation(
      for: NSPredicate { object, _ in
        MainActor.assumeIsolated {
          guard let response = object as? XCUIElement else { return false }
          return (Int(response.value as? String ?? "") ?? -1) >= 0
        }
      },
      evaluatedWith: response)
    waitForExpectations(timeout: 10)
    capture("07-text-waehrend-sprachausgabe")
    let firstWord = Int(response.value as? String ?? "") ?? -1
    expectation(
      for: NSPredicate { object, _ in
        MainActor.assumeIsolated {
          guard let response = object as? XCUIElement else { return false }
          return (Int(response.value as? String ?? "") ?? -1) > firstWord
        }
      },
      evaluatedWith: response)
    waitForExpectations(timeout: 10)
    capture("08-text-folgt-audio")
    XCTAssertEqual(state.value as? String, "playback")
    app.buttons["stop-speech"].tap()
    XCTAssertEqual(state.value as? String, "idle")
    XCTAssertFalse(app.staticTexts["voice-response"].exists)
    app.buttons["voice-details"].tap()
    app.buttons["voice-next"].tap()
    app.tabBars.buttons["Mehr"].tap()
    app.tabBars.buttons["Sprechen"].tap()
    if app.navigationBars["Gesprächsdetails"].exists {
      app.navigationBars["Gesprächsdetails"].buttons.firstMatch.tap()
    }
    XCTAssertEqual(state.value as? String, "idle")
    capture("09-audio-beendet")
  }
}
