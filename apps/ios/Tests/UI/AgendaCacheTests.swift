import XCTest

@MainActor final class AgendaCacheTests: XCTestCase {
  private var app: XCUIApplication!
  private var pager: XCUIElement { app.scrollViews["agenda-days"].firstMatch }
  private var refreshState: XCUIElement { app.buttons["agenda-today"] }

  override func tearDown() async throws {
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

  func testTimelinePullToRefreshWaitsForReloadAndKeepsDay() {
    checkPullToRefresh(list: false)
  }

  func testListPullToRefreshWaitsForReloadAndKeepsDay() {
    checkPullToRefresh(list: true)
  }

  private func checkPullToRefresh(list: Bool) {
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
    let appointment = event("Therapie Tag 1, 8 Uhr")
    XCTAssertTrue(appointment.waitForExistence(timeout: 8))
    if list {
      app.tabBars.buttons["Mehr"].tap()
      app.buttons["Darstellung"].tap()
      let toggle = app.switches["agenda-list-setting"]
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      XCTAssertEqual(toggle.value as? String, "1")
      app.tabBars.buttons["Termine"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].waitForExistence(timeout: 8))
    }
    state("settled")
    let scroll =
      list
      ? app.descendants(matching: .any)["agenda-accessible-list"]
      : app.scrollViews["day-timeline"].firstMatch
    if !list {
      // The initial timeline anchor is 07:30. Reach 06:00 before a distinct
      // refresh gesture, allowing any refresh caused by that first drag to finish.
      scroll.swipeDown()
      state("settled")
    }
    XCTAssertTrue(appointment.isHittable)
    let restingY = appointment.frame.minY
    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(
      forDuration: 0.1,
      thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    state("refreshing")
    noVisibleLoader()
    XCTAssertTrue(appointment.isHittable)
    XCTAssertTrue(app.activityIndicators.allElementsBoundByIndex.contains(where: \.isHittable))
    // Each calendar read is delayed by three seconds. An increment-and-return
    // refresh handler would stop its indicator before this interval completes.
    let prematureCompletion = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "settled"), object: refreshState)
    prematureCompletion.isInverted = true
    wait(for: [prematureCompletion], timeout: 1)
    XCTAssertTrue(app.activityIndicators.allElementsBoundByIndex.contains(where: \.isHittable))
    state("settled")
    expectation(
      for: NSPredicate { _, _ in abs(appointment.frame.minY - restingY) <= 1 },
      evaluatedWith: appointment)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(appointment.isHittable)
    noVisibleLoader()
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
