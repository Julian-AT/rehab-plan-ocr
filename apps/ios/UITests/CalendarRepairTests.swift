import XCTest

@MainActor final class CalendarRepairTests: XCTestCase {
  func testVoiceSettingsPreparationPreview() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.tabBars.buttons["Sprechen"].waitForExistence(timeout: 25))
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-settings"].tap()
    let preview = app.buttons["preview-voice"]
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    preview.tap()
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "voice-preparation-row"
    attachment.lifetime = .keepAlways
    add(attachment)
    expectation(for: NSPredicate(format: "value == %@", "playing"), evaluatedWith: preview)
    waitForExpectations(timeout: 45)
    preview.tap()
    XCTAssertEqual(preview.value as? String, "idle")
  }

  func testUnavailableCalendarOffersRepairWithoutClaimingKnownDays() {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments = [
      "-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "repair",
    ]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    let status = app.buttons["Status prüfen"]
    XCTAssertTrue(status.waitForExistence(timeout: 10))
    status.tap()
    let repair = app.buttons["calendar-repair"]
    XCTAssertTrue(repair.waitForExistence(timeout: 10))
    repair.tap()
    XCTAssertTrue(app.buttons["Kalenderauswahl bearbeiten"].waitForExistence(timeout: 20))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "Betroffene Tage lassen sich deshalb")
      ).firstMatch.exists)
    XCTAssertFalse(app.staticTexts["Keine offenen Terminzuordnungen gefunden."].exists)
    let remove = app.buttons["confirm-calendar-repair"]
    if remove.exists { XCTAssertFalse(remove.isEnabled) }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "calendar-repair-preview"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
