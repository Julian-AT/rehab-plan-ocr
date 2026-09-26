import XCTest

@MainActor final class CalmCalendarTests: XCTestCase {
  private var app: XCUIApplication!
  private func launch(dark: Bool = false, large: Bool = false) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      [
        "-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "colors",
        "--preview-now", "2026-09-14T13:56:00Z",
      ]
      + (dark ? ["--preview-dark"] : [])
      + (large
        ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: app.tabBars.buttons["Termine"])
    waitForExpectations(timeout: 20)
    app.scrollViews["agenda-days"].firstMatch.swipeLeft()
  }
  private func event(_ title: String) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
    ).firstMatch
  }
  private func settledFrame(_ element: XCUIElement) -> CGRect {
    var previous: CGRect?
    var repeated = 0
    expectation(
      for: NSPredicate { object, _ in
        guard let element = object as? XCUIElement, element.exists else { return false }
        let current = element.frame
        guard !current.isEmpty, !current.isInfinite, !current.isNull else { return false }
        repeated = current == previous ? repeated + 1 : 0
        previous = current
        return repeated >= 2
      }, evaluatedWith: element)
    waitForExpectations(timeout: 10)
    return element.frame
  }
  @discardableResult private func dragList(by points: CGFloat) -> CGFloat {
    let viewport = app.scrollViews["day-timeline"].firstMatch.frame
      .intersection(
        CGRect(x: 0, y: 0, width: app.frame.width, height: app.tabBars.firstMatch.frame.minY))
    let limit = viewport.height * 0.3
    let movement = min(limit, max(-limit, points))
    let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: viewport.minX + 8, dy: viewport.midY - movement / 2))
    start.press(
      forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: movement)),
      withVelocity: .slow, thenHoldForDuration: 0.1)
    return movement
  }
  private func position(_ row: XCUIElement, topPixel: Int) {
    // This contract belongs to the retained iPhone 17 / 3x originals. A changed
    // device must fail instead of quietly rescaling the expected screenshot.
    XCTAssertEqual(app.frame.size, CGSize(width: 402, height: 874))
    // The native List button includes its 15-point top inset. The retained
    // contract measures the colored card, not the surrounding white list row.
    let target = CGFloat(topPixel) / 3 - 15
    for _ in 0..<16 where !row.exists { dragList(by: -200) }
    XCTAssertTrue(row.exists)
    var top = settledFrame(row).minY
    var lostUpwardTravel: CGFloat = 16
    var lostDownwardTravel: CGFloat = 16
    for _ in 0..<16 {
      if abs(top - target) < 1.0 / 6 {
        XCTAssertTrue(row.isHittable)
        return
      }
      let difference = target - top
      // Measure the gesture travel consumed by pan recognition separately for
      // each direction. Small corrections otherwise oscillate around the target.
      let down = difference > 0
      let loss = down ? lostDownwardTravel : lostUpwardTravel
      let correction = difference + (down ? loss : -loss)
      // Very short drags can become taps. Deliberately pass the target with a
      // recognized gesture, then approach from the other direction next time.
      let requested = dragList(by: abs(correction) < 32 ? (down ? 64 : -64) : correction)
      let next = settledFrame(row).minY
      let actual = next - top
      let measuredLoss =
        actual * requested > 0 ? abs(requested) - abs(actual) : loss + 8
      if down {
        lostDownwardTravel = min(64, max(0, measuredLoss))
      } else {
        lostUpwardTravel = min(64, max(0, measuredLoss))
      }
      top = next
    }
    XCTAssertEqual(settledFrame(row).minY, target, accuracy: 1.0 / 6)
  }
  private func capture(
    _ name: String, anchor: XCUIElement? = nil, topPixel: Int? = nil, settle: Bool = true
  ) {
    let before = anchor.map { settle ? settledFrame($0) : $0.frame }
    let screenshot = app.screenshot()
    XCTAssertEqual(screenshot.image.cgImage?.width, 1206)
    XCTAssertEqual(screenshot.image.cgImage?.height, 2622)
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let anchor, let before {
      XCTAssertEqual(anchor.frame, before, "Capture moved after geometry settled")
      if let topPixel { XCTAssertEqual(before.minY * 3 + 45, CGFloat(topPixel), accuracy: 0.5) }
      let position: [String: Any] = [
        "contract": "retained-calendar-positions-v2",
        "anchor": anchor.label,
        "frame_points": [before.minX, before.minY, before.width, before.height],
        "expected_top_pixel": topPixel as Any? ?? NSNull(),
        "card_inset_pixels": topPixel.map { _ in 45 } as Any? ?? NSNull(),
        "scale": 3,
      ]
      do {
        let evidence = XCTAttachment(
          data: try JSONSerialization.data(withJSONObject: position, options: [.sortedKeys]),
          uniformTypeIdentifier: "public.json")
        evidence.name = "position-\(name).json"
        evidence.lifetime = .keepAlways
        add(evidence)
      } catch { XCTFail("Could not record capture position: \(error)") }
    }
  }
  override func tearDown() async throws {
    app?.terminate()
  }
  func testMutedPaletteCardsListAndLegend() {
    for dark in [false, true] {
      let mode = dark ? "dark" : "light"
      launch(dark: dark)
      XCTAssertTrue(
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Frühstück I")).firstMatch
          .waitForExistence(timeout: 10))
      capture("calm-cards-\(mode)", anchor: event("Frühstück I"))
      app.tabBars.buttons["Mehr"].tap()
      app.buttons["Darstellung"].tap()
      let list = app.switches["agenda-list-setting"]
      if list.value as? String != "1" { list.switches.firstMatch.tap() }
      app.swipeUp()
      XCTAssertTrue(app.staticTexts["Terminfarben"].exists)
      capture("calm-legend-\(mode)", anchor: app.staticTexts["Terminfarben"])
      app.tabBars.buttons["Termine"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].firstMatch.waitForExistence(
          timeout: 10))
      capture("calm-list-\(mode)", anchor: event("Frühstück I"))
      app.swipeUp()
      // These originals include the transient native scroll indicator. Observe
      // the frame across the actual capture, without waiting for it to fade.
      capture("calm-list-lower-\(mode)", anchor: event("Freier Termin"), settle: false)
      app.terminate()
    }
  }
  func testLargeCalendarText() {
    for dark in [false, true] {
      launch(dark: dark, large: true)
      XCTAssertTrue(
        app.descendants(matching: .any)["agenda-accessible-list"].firstMatch.waitForExistence(
          timeout: 10))
      // Measured from original PNGs, before taking a new candidate; see
      // docs/product/visual-baseline/capture-contract.md. The partly clipped
      // rows intentionally reproduce their original viewport positions.
      let anchors: [(String, Int)] = [
        ("Frühstück I", 1169), ("Ärztliches Gespräch", 1338),
        ("Physiotherapie kurz", dark ? 774 : 782), ("Anmeldung", dark ? 1484 : 1467),
        ("Freier Termin", dark ? 686 : 669),
      ]
      for (index, entry) in anchors.enumerated() {
        let (title, top) = entry
        let row = event(title)
        position(row, topPixel: top)
        if index == 0 {
          capture(dark ? "calm-large-dark" : "calm-large-light", anchor: row, topPixel: top)
        }
        capture("calm-large-\(dark ? "dark" : "light")-\(index)", anchor: row, topPixel: top)
      }
      app.terminate()
    }
  }
  func testVisualFinishedDay() {
    for dark in [false, true] {
      continueAfterFailure = false
      app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
      app.launchArguments =
        [
          "-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "complete",
          "--preview-now", "2026-09-14T13:56:00Z",
        ] + (dark ? ["--preview-dark"] : [])
      app.launch()
      XCTAssertTrue(app.buttons["past-events"].waitForExistence(timeout: 25))
      XCTAssertTrue(app.staticTexts["Zeit zum Erholen"].exists)
      capture(
        "calm-past-events-\(dark ? "dark" : "light")", anchor: app.buttons["past-events"])
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
    // Submitting the lower form keeps its scroll position. The response row is
    // virtualized above the viewport until it is brought back into view.
    for _ in 0..<8 where !answer.isHittable { app.swipeDown() }
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
