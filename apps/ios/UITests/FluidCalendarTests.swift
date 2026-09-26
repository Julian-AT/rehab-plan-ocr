import XCTest

@MainActor final class FluidCalendarTests: XCTestCase {
  private var app: XCUIApplication!
  private func launch(_ mode: String = "axis", extra: [String] = []) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", mode] + extra
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
  }
  override func tearDown() async throws {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    app.terminate()
  }
  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
  func testSyntheticAudioFormatsMeterAndFailure() {
    launch("audio-probe")
    capture("fluid-00-audiopipeline-geprueft")
  }
  func testDenseShortEventsKeepMinimumTargets() {
    launch("dense-short")
    app.scrollViews["agenda-days"].firstMatch.swipeLeft()
    let first = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Kurzer Prüftermin 1")
    ).firstMatch
    expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: first)
    waitForExpectations(timeout: 10)
    XCTAssertTrue(app.descendants(matching: .any)["agenda-accessible-list"].exists)
    XCTAssertGreaterThanOrEqual(first.frame.width, 44)
    XCTAssertGreaterThanOrEqual(first.frame.height, 44)
    capture("fluid-13-sehr-kurze-termine")
  }
  func testUniformHoursAndNoResetAfterRefreshOrEmptyPage() {
    launch()
    let pager = app.scrollViews["agenda-days"].firstMatch
    XCTAssertTrue(pager.waitForExistence(timeout: 10))
    pager.swipeLeft()
    let hour = app.staticTexts["timeline-hour-12"]
    XCTAssertTrue(hour.waitForExistence(timeout: 10))
    XCTAssertEqual(
      app.staticTexts["timeline-hour-13"].frame.minY - hour.frame.minY, 96, accuracy: 1)
    let timeline = app.scrollViews["day-timeline"].firstMatch
    let origin = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
    origin.press(
      forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 35, dy: -160)),
      withVelocity: .slow, thenHoldForDuration: 0.3)
    let y = hour.frame.minY
    let width = pager.frame.width
    capture("fluid-01-gleichmaessige-zeitachse")
    // Cross a real 15-second SwiftUI timeline refresh without any navigation.
    Thread.sleep(forTimeInterval: 16)
    XCTAssertEqual(hour.frame.minY, y, accuracy: 1)
    pager.swipeLeft()
    XCTAssertTrue(app.staticTexts["Keine Termine"].waitForExistence(timeout: 8))
    XCTAssertEqual(pager.frame.width, width, accuracy: 0.5)
    capture("fluid-02-leerer-tag-stabile-breite")
    pager.swipeLeft()
    XCTAssertTrue(hour.waitForExistence(timeout: 8))
    XCTAssertEqual(hour.frame.minY, y, accuracy: 1)
    capture("fluid-03-position-nach-blaettern")
  }
  func testColorsHelpAndPersistence() {
    launch("colors")
    app.tabBars.buttons["Mehr"].tap()
    capture("fluid-04-mehr-klinikgruen")
    app.buttons["Darstellung"].tap()
    app.buttons["Info: Kalender"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "gleichmäßigen Stundenabstand")
      ).firstMatch.waitForExistence(timeout: 5))
    capture("fluid-05-kontexthilfe")
    app.buttons["Fertig"].tap()
    app.buttons["Terminfarben"].tap()
    let slider = app.sliders["appointment-color-strength"]
    XCTAssertTrue(slider.waitForExistence(timeout: 5))
    slider.adjust(toNormalizedSliderPosition: 0.85)
    let value = slider.value as? String
    capture("fluid-06-terminfarben-vorschau")
    app.swipeUp()
    capture("fluid-12-farbvorschau")
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Darstellung"].tap()
    app.buttons["Terminfarben"].tap()
    XCTAssertEqual(slider.value as? String, value)
    app.swipeUp()
    app.buttons["reset-appointment-colors"].tap()
  }
  func testContextHelpWithLargestType() throws {
    launch(
      "full",
      extra: [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        "--preview-dark",
      ])
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Darstellung"].tap()
    let info = app.buttons["Info: Kalender"]
    for _ in 0..<5 where !info.isHittable { app.swipeUp() }
    info.tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "gleichmäßigen Stundenabstand")
      ).firstMatch.waitForExistence(timeout: 5))
    capture("fluid-10-hilfe-groesste-schrift")
    try app.performAccessibilityAudit(for: [
      .elementDetection, .sufficientElementDescription, .trait,
    ])
    let done = app.buttons["Fertig"]
    for _ in 0..<6 where !done.isHittable { app.swipeUp() }
    XCTAssertTrue(done.isHittable)
    done.tap()
  }
  func testDestinationDoneSavesAndShowsPermissionStatus() {
    launch("one")
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Kalender"].tap()
    let destination = app.buttons["Speicherziel ändern"]
    for _ in 0..<6
    where !destination.isHittable || destination.frame.maxY >= app.tabBars.firstMatch.frame.minY {
      app.swipeUp()
    }
    destination.tap()
    let access = app.descendants(matching: .any)["destination-access"].firstMatch
    XCTAssertTrue(access.waitForExistence(timeout: 10))
    XCTAssertEqual(access.value as? String, "Erlaubt")
    XCTAssertFalse(app.buttons["Kalenderzugriff erlauben"].exists)
    app.buttons["select-clinic-calendar"].tap()
    let save = app.buttons["save-calendar-destination"]
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    waitForExpectations(timeout: 15)
    capture("fluid-07-speicherziel-gewaehlt")
    save.tap()
    XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 10))
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20))
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Kalender"].tap()
    let stored = app.descendants(matching: .any)["calendar-destination"].firstMatch
    XCTAssertTrue(stored.waitForExistence(timeout: 10))
    expectation(for: NSPredicate(format: "value CONTAINS %@", "Laßnitzhöhe"), evaluatedWith: stored)
    waitForExpectations(timeout: 10)
  }
  func testTranscriptComposerKeepsFailedInputAndResumeVisible() {
    launch("one", extra: ["--preview-dark"])
    app.tabBars.buttons["Sprechen"].tap()
    capture("fluid-08-orb-bereit")
    app.buttons["voice-details"].tap()
    XCTAssertTrue(app.buttons["resume-conversation"].isHittable)
    app.buttons["voice-actions"].tap()
    app.buttons["voice-next"].tap()
    XCTAssertTrue(app.buttons["repeat-speech"].waitForExistence(timeout: 30))
    let field =
      app.textFields["voice-message"].exists
      ? app.textFields["voice-message"] : app.textViews["voice-message"]
    field.tap()
    let keyboardWelcome = app.buttons.matching(
      NSPredicate(format: "label IN %@", ["Continue", "Fortfahren"])
    ).firstMatch
    if keyboardWelcome.exists { keyboardWelcome.tap() }
    let text = "Hallo, erzähl mir einen Witz"
    field.typeText(text)
    XCTAssertGreaterThan(app.buttons["voice-send"].frame.height, 43)
    app.buttons["voice-send"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(
          format: "label CONTAINS %@ OR label CONTAINS %@", "Die Antwort konnte",
          "Apple Intelligence")
      ).firstMatch.waitForExistence(timeout: 30))
    XCTAssertEqual(field.value as? String, text)
    XCTAssertTrue(app.buttons["voice-send"].isEnabled)
    capture("fluid-09-verlauf-und-fehler-wiederholen")
    let transcript = app.scrollViews["conversation-transcript"]
    transcript.swipeDown()
    transcript.swipeDown()
    capture("fluid-11-chronologischer-verlauf")
  }
}
