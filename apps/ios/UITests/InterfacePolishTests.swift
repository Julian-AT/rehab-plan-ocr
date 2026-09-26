import XCTest

@MainActor final class InterfacePolishTests: XCTestCase {
  private var app: XCUIApplication!
  private func launch(dark: Bool = false, large: Bool = false) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "axis"]
      + (dark ? ["--preview-dark"] : [])
      + (large
        ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 25))
  }
  override func tearDown() async throws {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    app.terminate()
  }
  private func show(_ element: XCUIElement) {
    for _ in 0..<10 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.isHittable)
  }
  private func edgeTap(_ element: XCUIElement) {
    show(element)
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
  }
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testCompactActionsTooltipsAndWhiteSelections() throws {
    for dark in [false, true] {
      launch(dark: dark)
      let mode = dark ? "dark" : "light"
      capture("polish-calendar-\(mode)")
      app.tabBars.buttons["Sprechen"].tap()
      capture("polish-orb-\(mode)")
      app.buttons["voice-settings"].tap()
      let preview = app.buttons["preview-voice"]
      XCTAssertTrue(preview.waitForExistence(timeout: 5))
      XCTAssertTrue((44...56).contains(preview.frame.height))
      let actionHeight = preview.frame.height
      let help = app.buttons["info-Spracherkennung"]
      let text = app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Gespräch starten und Mikrofon")
      ).firstMatch
      XCTAssertFalse(text.exists)
      edgeTap(help)
      XCTAssertTrue(text.waitForExistence(timeout: 3))
      capture("polish-tooltip-\(mode)")
      edgeTap(app.buttons["close-info"])
      XCTAssertFalse(text.exists)
      capture("polish-voice-settings-\(mode)")
      // Hit the empty trailing part of the label, not its text.
      edgeTap(preview)
      expectation(for: NSPredicate(format: "value == %@", "playing"), evaluatedWith: preview)
      waitForExpectations(timeout: 45)
      edgeTap(preview)
      XCTAssertEqual(preview.value as? String, "idle")
      app.tabBars.buttons["Mehr"].tap()
      app.buttons["Kalender"].tap()
      // Native Toggle exposes both its full row and the smaller visual switch.
      for toggle in app.switches.allElementsBoundByIndex
      where toggle.isHittable && toggle.frame.width > 200 {
        XCTAssertLessThanOrEqual(toggle.frame.height, 64)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
      }
      capture("polish-calendar-settings-\(mode)")
      app.navigationBars["Kalender"].buttons.firstMatch.tap()
      show(app.buttons["Kalenderstatus"])
      app.buttons["Kalenderstatus"].tap()
      let refresh = app.buttons["refresh-calendar-status"]
      show(refresh)
      XCTAssertEqual(refresh.frame.height, actionHeight, accuracy: 1)
      edgeTap(refresh)
      capture("polish-calendar-status-\(mode)")
      app.terminate()
    }
  }
  func testInlineSendAndReconcileAtTrailingEdge() {
    launch()
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-details"].tap()
    let field = app.textFields["voice-message"]
    let send = app.buttons["voice-send"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(send.frame.height, 44, accuracy: 1)
    XCTAssertLessThan(abs(send.frame.midY - field.frame.midY), 12)
    field.tap()
    field.typeText("Was habe ich heute?")
    let keyboardIntro = app.buttons["Continue"]
    if keyboardIntro.exists { keyboardIntro.tap() }
    capture("polish-inline-send")
    edgeTap(send)
    XCTAssertTrue(app.staticTexts["voice-response-details"].waitForExistence(timeout: 20))
    XCTAssertNotEqual(field.value as? String, "Was habe ich heute?")
    app.swipeUp()
    let history = app.buttons["Verlauf und Rückgängig"]
    show(history)
    history.tap()
    let reconcile = app.buttons["Schreibstatus abgleichen"]
    XCTAssertTrue(reconcile.waitForExistence(timeout: 5))
    XCTAssertTrue((44...56).contains(reconcile.frame.height))
    edgeTap(reconcile)
    XCTAssertTrue(app.staticTexts["reconcile-complete"].waitForExistence(timeout: 10))
    capture("polish-reconcile")
  }
  func testLargeTypeHelpUsesScrollableNativeSheet() throws {
    launch(dark: true, large: true)
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Sprache"].tap()
    let help = app.buttons["info-Spracherkennung"]
    show(help)
    help.tap()
    XCTAssertTrue(app.buttons["close-info"].waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(app.buttons["close-info"].frame.height, 44)
    capture("polish-large-help")
    app.scrollViews.firstMatch.swipeUp()
    capture("polish-large-help-scrolled")
    XCTAssertTrue(app.buttons["close-info"].isHittable)
    try app.performAccessibilityAudit(for: [
      .elementDetection, .sufficientElementDescription, .trait,
    ])
    // The fixed header remains reachable after scrolling. Exercise the edge
    // of its full 44-point touch target as well as the accessibility frame.
    let close = app.buttons["close-info"]
    close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - 21 / close.frame.height))
      .tap()
    XCTAssertFalse(close.exists)
    XCTAssertTrue(app.navigationBars["Sprache"].exists)
  }
  func testTracingShowsRealEvidenceAndLeavesArchiveUnchanged() {
    launch()
    app.tabBars.buttons["Archiv"].tap()
    let plans = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "plan-"))
    let before = plans.allElementsBoundByIndex.map(\.identifier).sorted()
    app.tabBars.buttons["Mehr"].tap()
    show(app.buttons["open-tracing"])
    app.buttons["open-tracing"].tap()
    edgeTap(app.buttons["trace-photos"])
    XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
    app.buttons["Abbrechen"].tap()
    edgeTap(app.buttons["trace-files"])
    XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
    let browse = app.buttons["Durchsuchen"]
    if browse.waitForExistence(timeout: 20), browse.isHittable { browse.tap() }
    let local = app.staticTexts["Auf meinem iPhone"]
    if local.waitForExistence(timeout: 3) { local.tap() }
    let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Testplan,"))
      .firstMatch
    XCTAssertTrue(file.waitForExistence(timeout: 8))
    file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    let open = app.buttons["Öffnen"]
    if open.waitForExistence(timeout: 3) { open.tap() }
    XCTAssertTrue(app.buttons["trace-step-decode"].waitForExistence(timeout: 90))
    capture("tracing-steps")
    for stage in [
      "decode", "preprocessing", "detection", "recognition", "layout_and_fields",
      "selective_reread",
    ] {
      let step = app.buttons["trace-step-\(stage)"]
      if stage == "selective_reread" && !step.exists { continue }
      show(step)
      step.tap()
      let image = app.buttons["trace-image"]
      XCTAssertTrue(image.waitForExistence(timeout: 8))
      if stage == "detection" || stage == "recognition" {
        XCTAssertFalse(image.label.contains("mit 0 Markierungen"))
      }
      capture("tracing-\(stage)")
      if stage == "detection" {
        image.tap()
        XCTAssertTrue(app.navigationBars["Bild und Markierungen"].waitForExistence(timeout: 5))
        capture("tracing-zoom")
        app.navigationBars["Bild und Markierungen"].buttons["Fertig"].tap()
      }
      if stage == "recognition" {
        let evidence = app.buttons.matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "trace-evidence-")
        ).firstMatch
        show(evidence)
        evidence.tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(image.label.contains("mit 1 Markierung"))
        XCTAssertTrue(image.isHittable)
        capture("tracing-selected-text")
      }
      if stage == "layout_and_fields" {
        let appointment = app.buttons["Frühstück"]
        show(appointment)
        appointment.tap()
        let room = app.buttons.matching(
          NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "trace-evidence-",
            "Speisesaal")
        ).firstMatch
        show(room)
        room.tap()
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(image.isHittable)
        XCTAssertFalse(image.label.contains("mit 0 Markierungen"))
        capture("tracing-selected-field")
      }
      if stage == "selective_reread" {
        let disclosure = app.buttons["Ergebnis des Ausschnitts"].firstMatch
        show(disclosure)
        disclosure.tap()
        let crop = app.images.matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "trace-crop-region-reread-")
        ).firstMatch
        XCTAssertTrue(crop.waitForExistence(timeout: 8))
        show(crop)
        capture("tracing-reread-crop")
      }
      app.navigationBars.buttons["Fertig"].tap()
      XCTAssertTrue(app.navigationBars["Tracing"].waitForExistence(timeout: 5))
    }
    app.navigationBars["Tracing"].buttons.firstMatch.tap()
    app.buttons["open-tracing"].tap()
    XCTAssertFalse(app.buttons["trace-step-decode"].exists)
    app.navigationBars["Tracing"].buttons.firstMatch.tap()
    app.tabBars.buttons["Archiv"].tap()
    XCTAssertEqual(plans.allElementsBoundByIndex.map(\.identifier).sorted(), before)
  }
  func testTracePhotoCanBeCancelledAndReopened() {
    launch()
    app.tabBars.buttons["Mehr"].tap()
    show(app.buttons["open-tracing"])
    app.buttons["open-tracing"].tap()
    app.buttons["trace-photos"].tap()
    let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
    XCTAssertTrue(image.waitForExistence(timeout: 15))
    image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let cancel = app.buttons["trace-cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10))
    cancel.tap()
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
    waitForExpectations(timeout: 60)
    XCTAssertTrue(app.buttons["trace-files"].isEnabled)
    capture("tracing-cancelled")
    app.navigationBars["Tracing"].buttons.firstMatch.tap()
    app.buttons["open-tracing"].tap()
    XCTAssertFalse(app.buttons["trace-step-decode"].exists)
    XCTAssertTrue(app.buttons["trace-files"].isEnabled)
  }
}
