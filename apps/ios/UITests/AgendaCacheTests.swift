import XCTest

@MainActor final class AgendaCacheTests: XCTestCase {
  private var app: XCUIApplication!
  private var pager: XCUIElement { app.scrollViews["agenda-days"].firstMatch }
  private var refreshState: XCUIElement { app.buttons["agenda-today"] }

  override func tearDown() {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    app.terminate()
  }

  private func state(_ value: String) {
    expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: refreshState)
    waitForExpectations(timeout: 25)
  }

  private func event(_ title: String) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
    ).firstMatch
  }

  private func noVisibleLoader() {
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "agenda-loading")
        .allElementsBoundByIndex.contains(where: \.isHittable))
  }

  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }

  func testCachedDaysStayVisibleDuringDelayedRefresh() {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments = [
      "-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "axis",
      "--preview-agenda-delay",
    ]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    state("settled")
    pager.swipeLeft()
    let appointment = event("Therapie Tag 1, 9 Uhr")
    XCTAssertTrue(appointment.waitForExistence(timeout: 8))
    XCTAssertTrue(appointment.isHittable)
    let y = appointment.frame.minY
    capture("cache-01-loaded")

    app.tabBars.buttons["Mehr"].tap()
    app.tabBars.buttons["Termine"].tap()
    state("refreshing")
    XCTAssertTrue(appointment.isHittable)
    noVisibleLoader()
    XCTAssertEqual(appointment.frame.minY, y, accuracy: 1)
    capture("cache-02-refresh-with-content")

    // The cached empty day also stays resolved during the delayed refresh.
    pager.swipeLeft()
    XCTAssertTrue(app.staticTexts["Keine Termine"].waitForExistence(timeout: 5))
    noVisibleLoader()
    app.tabBars.buttons["Mehr"].tap()
    app.tabBars.buttons["Termine"].tap()
    state("refreshing")
    XCTAssertTrue(app.staticTexts["Keine Termine"].isHittable)
    noVisibleLoader()
    capture("cache-03-empty-during-refresh")

    pager.swipeRight()
    XCTAssertTrue(appointment.isHittable)
    noVisibleLoader()
    XCTAssertEqual(appointment.frame.minY, y, accuracy: 1)
    state("settled")
    noVisibleLoader()
    capture("cache-04-refreshed")
  }
}
