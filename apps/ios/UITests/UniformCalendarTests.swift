import XCTest

@MainActor final class UniformCalendarTests: XCTestCase {
  private var app: XCUIApplication!
  private let language = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
  private func launch(_ mode: String, extra: [String] = []) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments = language + ["--agenda-fixture", mode] + extra
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
  }
  override func tearDown() {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 15))
    app.terminate()
  }
  private var pager: XCUIElement { app.scrollViews["agenda-days"].firstMatch }
  private var timeline: XCUIElement { app.scrollViews["day-timeline"].firstMatch }
  private func event(_ title: String) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
    ).firstMatch
  }
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func appearance() {
    app.tabBars.buttons["Mehr"].tap()
    if !app.buttons["agenda-density"].exists { app.buttons["Darstellung"].tap() }
    XCTAssertTrue(app.buttons["agenda-density"].waitForExistence(timeout: 5))
  }
  /// Measure the actual rendered axis, including UIKit's preserved scroll offset.
  private func checkScale(_ points: Double) throws -> Double {
    let hours = (6...18).compactMap { hour -> (Int, XCUIElement)? in
      guard
        let element = pager.staticTexts.matching(identifier: "timeline-hour-\(hour)")
          .allElementsBoundByIndex.first(where: \.isHittable)
      else { return nil }
      return (hour, element)
    }
    XCTAssertGreaterThanOrEqual(hours.count, 3)
    for (a, b) in zip(hours, hours.dropFirst()) {
      XCTAssertEqual(b.1.frame.minY - a.1.frame.minY, Double(b.0 - a.0) * points, accuracy: 1)
    }
    let first = try XCTUnwrap(hours.first)
    return Double(first.0 - 6) * 60 - (first.1.frame.minY - timeline.frame.minY) * 60 / points
  }
  func testScaleChangesKeepVisibleTimeAndAllCategoriesPersist() throws {
    launch("axis")
    pager.swipeLeft()
    XCTAssertTrue(event("Therapie Tag 1, 9 Uhr").waitForExistence(timeout: 8))
    let anchor = try checkScale(112)
    XCTAssertTrue(
      (4.5...6.5).contains(timeline.frame.height / 112),
      "Visible hours: \(timeline.frame.height / 112)")
    capture("uniform-01-standard")
    appearance()
    XCTAssertEqual(app.buttons["agenda-density"].value as? String, "Standard")
    for (name, points) in [("Übersicht", 72.0), ("Standard", 112.0), ("Großzügig", 160.0)] {
      app.buttons["agenda-density"].tap()
      app.buttons[name].tap()
      app.tabBars.buttons["Termine"].tap()
      XCTAssertTrue(event("Therapie Tag 1, 9 Uhr").waitForExistence(timeout: 8))
      XCTAssertEqual(try checkScale(points), anchor, accuracy: 1)
      capture("uniform-size-\(Int(points))")
      app.terminate()
      app.launchArguments = language
      app.launch()
      XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 20))
      appearance()
      XCTAssertEqual(app.buttons["agenda-density"].value as? String, name)
      app.tabBars.buttons["Termine"].tap()
      pager.swipeLeft()
      XCTAssertTrue(event("Therapie Tag 1, 9 Uhr").waitForExistence(timeout: 8))
      _ = try checkScale(points)
      appearance()
    }
    capture("uniform-02-persisted-size")
  }
  func testLongTitleDetailsAndVisualCollisionFallback() throws {
    launch("long-title")
    let title =
      "Physiotherapie mit ausführlicher Befundbesprechung und individuellen Übungen für den Alltag"
    let short = event(title)
    XCTAssertTrue(short.waitForExistence(timeout: 10))
    XCTAssertEqual(short.frame.height, 44, accuracy: 0.1)
    XCTAssertTrue(short.label.contains("Anna Beispiel"))
    XCTAssertTrue(short.label.contains("Raum 2.14"))
    XCTAssertFalse(short.frame.intersects(event("Bewegungstraining").frame))
    capture("uniform-03-long-title")
    short.tap()
    XCTAssertTrue(app.textFields["Bezeichnung"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields["Bezeichnung"].value as? String, title)
    capture("uniform-04-complete-details")
    app.terminate()
    launch("crowded")
    XCTAssertTrue(
      app.descendants(matching: .any)["agenda-accessible-list"].waitForExistence(timeout: 8))
    for minute in [0, 2, 4] { XCTAssertTrue(event("Kurztermin \(minute)").isHittable) }
    try app.performAccessibilityAudit(for: [
      .elementDetection, .sufficientElementDescription, .trait,
    ])
    capture("uniform-05-collision-list")
  }
  private func auditVisibleControls() throws {
    let contentTop = app.navigationBars.firstMatch.frame.maxY
    let contentBottom = app.tabBars.firstMatch.frame.minY - 44
    try app.performAccessibilityAudit(for: [
      .contrast, .elementDetection, .sufficientElementDescription, .trait,
    ]) { issue in
      // iOS 26.4 also returns stale contrast nodes from pushed-off screens
      // and content in the tab bar’s 44-point scroll-edge fade. Audit only
      // fully visible text; screenshots also retain the native edge effect.
      guard issue.auditType == .contrast, let element = issue.element else { return false }
      guard element.exists, element.isHittable else { return true }
      return element.frame.minY < contentTop || element.frame.maxY > contentBottom
    }
  }
  func testGreenControlsInBothAppearances() throws {
    for dark in [false, true] {
      launch("empty", extra: dark ? ["--preview-dark"] : [])
      continueAfterFailure = true
      let mode = dark ? "dark" : "light"
      app.tabBars.buttons["Mehr"].tap()
      for title in ["Kalender", "Darstellung", "Erinnerungen", "Sprache"] {
        XCTAssertGreaterThanOrEqual(app.buttons[title].frame.height, 44)
      }
      capture("green-more-\(mode)")
      try auditVisibleControls()
      app.buttons["Darstellung"].tap()
      let toggle = app.switches["agenda-list-setting"]
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      XCTAssertEqual(toggle.value as? String, "1")
      capture("green-appearance-\(mode)")
      app.buttons["agenda-density"].tap()
      capture("green-selection-\(mode)")
      app.buttons["Standard"].tap()
      if app.navigationBars["Kalendergröße"].exists {
        app.navigationBars["Kalendergröße"].buttons.firstMatch.tap()
      }
      app.navigationBars["Darstellung"].buttons.firstMatch.tap()
      app.buttons["Sprache"].tap()
      XCTAssertGreaterThanOrEqual(app.buttons["preview-voice"].frame.height, 44)
      let slider = app.sliders.firstMatch
      slider.adjust(toNormalizedSliderPosition: 0.5)
      let initial = try XCTUnwrap(slider.value as? String)
      let rate = try XCTUnwrap(Double(initial.replacingOccurrences(of: ",", with: ".")))
      let thumbX = (rate - 0.75) / 0.5
      XCTAssertGreaterThanOrEqual(slider.frame.height, 44)
      // Start 21 points above the center, at the edge of the minimum hit area.
      let edgeY = 0.5 - 21 / slider.frame.height
      slider.coordinate(withNormalizedOffset: CGVector(dx: thumbX, dy: edgeY)).press(
        forDuration: 0.1,
        thenDragTo: slider.coordinate(
          withNormalizedOffset: CGVector(dx: thumbX < 0.65 ? 0.9 : 0.1, dy: edgeY)))
      XCTAssertNotEqual(slider.value as? String, initial)
      slider.adjust(toNormalizedSliderPosition: 0.4)
      try auditVisibleControls()
      capture("green-voice-settings-\(mode)")
      app.navigationBars["Sprache"].buttons.firstMatch.tap()
      app.buttons["Speicher"].tap()
      capture("green-destructive-\(mode)")
      app.tabBars.buttons["Sprechen"].tap()
      XCTAssertGreaterThanOrEqual(app.buttons["speak"].frame.height, 44)
      capture("green-primary-\(mode)")
      app.terminate()
    }
  }
  func testLargeTypeListAndSettings() throws {
    for dark in [false, true] {
      launch(
        "short",
        extra: [
          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ] + (dark ? ["--preview-dark"] : []))
      let mode = dark ? "dark" : "light"
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].waitForExistence(timeout: 8))
      XCTAssertTrue(event("Kurztermin").label.contains("Anna Beispiel"))
      capture("green-large-list-\(mode)")
      app.tabBars.buttons["Mehr"].tap()
      capture("green-large-more-\(mode)")
      app.buttons["Sprache"].tap()
      XCTAssertTrue(app.sliders.firstMatch.isHittable)
      XCTAssertGreaterThanOrEqual(app.buttons["preview-voice"].frame.height, 44)
      try app.performAccessibilityAudit(for: [
        .elementDetection, .sufficientElementDescription, .trait,
      ])
      capture("green-large-voice-\(mode)")
      app.navigationBars["Sprache"].buttons.firstMatch.tap()
      app.buttons["Darstellung"].tap()
      let toggle = app.switches["agenda-list-setting"]
      for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
      XCTAssertTrue(toggle.isHittable)
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      XCTAssertEqual(toggle.value as? String, "1")
      capture("green-large-settings-\(mode)")
      app.terminate()
    }
  }
}
