import XCTest

@MainActor final class CalmCalendarTests: XCTestCase {
  private var app: XCUIApplication!
  private func launch(dark: Bool = false, large: Bool = false) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "colors"]
      + (dark ? ["--preview-dark"] : [])
      + (large
        ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    app.scrollViews["agenda-days"].firstMatch.swipeLeft()
  }
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  override func tearDown() {
    app?.terminate()
  }
  func testMutedPaletteCardsListAndLegend() {
    for dark in [false, true] {
      let mode = dark ? "dark" : "light"
      launch(dark: dark)
      XCTAssertTrue(
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Frühstück I")).firstMatch
          .waitForExistence(timeout: 10))
      capture("calm-cards-\(mode)")
      app.tabBars.buttons["Mehr"].tap()
      app.buttons["Darstellung"].tap()
      let list = app.switches["agenda-list-setting"]
      if list.value as? String != "1" { list.switches.firstMatch.tap() }
      app.swipeUp()
      XCTAssertTrue(app.staticTexts["Terminfarben"].exists)
      capture("calm-legend-\(mode)")
      app.tabBars.buttons["Termine"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].firstMatch.waitForExistence(
          timeout: 10))
      capture("calm-list-\(mode)")
      app.swipeUp()
      capture("calm-list-lower-\(mode)")
      app.terminate()
    }
  }
  func testLargeCalendarText() {
    for dark in [false, true] {
      launch(dark: dark, large: true)
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].firstMatch.waitForExistence(
          timeout: 10))
      capture(dark ? "calm-large-dark" : "calm-large-light")
      for (index, title) in [
        "Frühstück I", "Ärztliches Gespräch", "Physiotherapie", "Anmeldung", "Freier Termin",
      ].enumerated() {
        let row = app.buttons.matching(
          NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
        ).firstMatch
        for _ in 0..<16 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, title)
        // Very tall rows can become hittable while only their lower-screen edge
        // is visible. Bring the title into the screenshot before capturing it.
        for _ in 0..<8 where row.frame.minY > app.frame.height * 0.55 {
          app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(
              forDuration: 0.05,
              thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)))
        }
        capture("calm-large-\(dark ? "dark" : "light")-\(index)")
      }
      app.terminate()
    }
  }
  func testAddressPersistsAndChangesNextTemplate() {
    launch()
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-settings"].tap()
    let address = app.buttons["voice-address"]
    XCTAssertTrue(address.waitForExistence(timeout: 5))
    address.tap()
    app.buttons["Sie"].tap()
    capture("voice-address-sie")
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Sprechen"].waitForExistence(timeout: 25))
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-settings"].tap()
    XCTAssertEqual(app.buttons["voice-address"].value as? String, "Sie")
    app.navigationBars["Sprache"].buttons.firstMatch.tap()
    app.buttons["voice-details"].tap()
    app.buttons["voice-create"].tap()
    // First prompt asks for a title; submit it to reach the addressed date question.
    let field = app.textFields["Bezeichnung"]
    for _ in 0..<5 where !field.isHittable { app.swipeUp() }
    XCTAssertTrue(field.exists)
    field.tap()
    field.typeText("Testtermin")
    app.buttons["Bezeichnung übernehmen"].tap()
    let answer = app.staticTexts["voice-response-details"]
    expectation(for: NSPredicate(format: "label CONTAINS %@", "haben Sie"), evaluatedWith: answer)
    waitForExpectations(timeout: 8)
    app.tabBars.buttons["Mehr"].tap()
    app.tabBars.buttons["Sprechen"].tap()
    if app.navigationBars["Gesprächsdetails"].exists {
      app.navigationBars["Gesprächsdetails"].buttons.firstMatch.tap()
    }
    app.buttons["voice-settings"].tap()
    app.buttons["voice-address"].tap()
    app.buttons["Du"].tap()
    capture("voice-address-du")
  }
}
