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
    expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: app.tabBars.buttons["Mehr"])
    waitForExpectations(timeout: 20)
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
  private func showEditorField(_ element: XCUIElement, towardEarlier: Bool = false) {
    // A large swipe can put a field behind the navigation bar while XCTest
    // still calls it hittable. Keep its tap point inside the visible form.
    func viewport() -> CGRect {
      let top = app.navigationBars["Termin bearbeiten"].frame.maxY + 12
      let keyboard = app.keyboards.firstMatch
      let bottom = keyboard.exists ? keyboard.frame.minY - 12 : app.frame.maxY - 44
      return CGRect(x: 16, y: top, width: app.frame.width - 32, height: bottom - top)
    }
    for _ in 0..<20 {
      let visible = viewport()
      if element.exists, element.isHittable,
        visible.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
      {
        return
      }
      // Lazy form rows outside the viewport may have no accessibility frame.
      // Returning to an earlier field must still move toward the form's start.
      let scrollBack = element.exists ? element.frame.midY < visible.minY : towardEarlier
      let origin = app.coordinate(withNormalizedOffset: .zero).withOffset(
        CGVector(dx: visible.midX, dy: visible.midY))
      origin.press(
        forDuration: 0.05,
        thenDragTo: origin.withOffset(CGVector(dx: 0, dy: scrollBack ? 100 : -100)))
    }
    XCTAssertTrue(element.isHittable)
    XCTAssertTrue(viewport().contains(CGPoint(x: element.frame.midX, y: element.frame.midY)))
  }
  private var photoPickerCancel: XCUIElement {
    // PUPickerUnavailableView briefly exposes another "Abbrechen" with an
    // infinite frame. Wait for the loaded Photos navigation bar's real control.
    app.navigationBars["Fotos"].buttons["Cancel"]
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
        NSPredicate(format: "label BEGINSWITH %@", "Nach einer Sprechpause antwortet die App.")
      ).firstMatch
      XCTAssertFalse(text.exists)
      edgeTap(help)
      XCTAssertTrue(text.waitForExistence(timeout: 3))
      XCTAssertFalse(app.staticTexts["Spracherkennung"].isHittable)
      capture("polish-tooltip-\(mode)")
      edgeTap(app.buttons["close-info"])
      XCTAssertFalse(text.exists)
      capture("polish-voice-settings-\(mode)")
      // Hit the empty trailing part of the label, not its text.
      edgeTap(preview)
      let playing = app.buttons.matching(
        NSPredicate(format: "identifier == %@ AND value == %@", "preview-voice", "playing")
      ).firstMatch
      XCTAssertTrue(playing.waitForExistence(timeout: 45))
      edgeTap(preview)
      let idle = app.buttons.matching(
        NSPredicate(format: "identifier == %@ AND value == %@", "preview-voice", "idle")
      ).firstMatch
      XCTAssertTrue(idle.waitForExistence(timeout: 5))
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
    XCTAssertEqual(send.frame.midY, field.frame.midY, accuracy: 1)
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
  func testLargeTypeControlsRemainUsable() {
    launch(dark: true, large: true)
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-details"].tap()
    let field = app.textFields["voice-message"]
    let send = app.buttons["voice-send"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.frame.midY, send.frame.midY, accuracy: 1)
    capture("simple-large-message")
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Kalender"].tap()
    let destination = app.buttons["calendar-destination"]
    show(destination)
    capture("simple-large-calendar-settings")
    edgeTap(destination)
    let choice = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "destination-")
    ).firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: 8))
    edgeTap(choice)
    XCTAssertTrue(choice.isSelected)
    capture("simple-large-destination")
    app.navigationBars["Speicherziel"].buttons.firstMatch.tap()
    app.navigationBars["Kalender"].buttons.firstMatch.tap()
    show(app.buttons["open-tracing"])
    app.buttons["open-tracing"].tap()
    capture("simple-large-tracing")
    edgeTap(app.buttons["trace-photos"])
    XCTAssertTrue(photoPickerCancel.waitForExistence(timeout: 15))
    photoPickerCancel.tap()
    edgeTap(app.buttons["trace-files"])
    XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 15))
    app.buttons["Abbrechen"].tap()
  }
  func testLargestTypeArchiveReviewRetainsDraftAndOriginal() throws {
    launch(dark: true, large: true)
    app.tabBars.buttons["Archiv"].tap()
    // The public UI fixture is also used by NativeFlowTests. No calendar write
    // is needed to exercise the editor and the retained document at large type.
    let plan = app.buttons["plan-11111111-1111-4111-8111-111111111111"]
    XCTAssertTrue(plan.waitForExistence(timeout: 10))
    show(plan)
    capture("large-type-archive")
    plan.tap()
    let actions = app.buttons["plan-actions"]
    XCTAssertTrue(actions.waitForExistence(timeout: 10))
    actions.tap()
    app.buttons["Termin ergänzen"].tap()
    let title = app.textFields["Bezeichnung"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    title.tap()
    title.typeText("Entwurf bei größter Schrift")
    let room = app.textFields["Raum"]
    showEditorField(room)
    room.tap()
    room.typeText("Langer Flur 2")
    showEditorField(app.switches["In diesen Plan aufnehmen"].firstMatch)
    capture("large-type-review-lower-fields")
    app.buttons["Abbrechen"].tap()
    XCTAssertTrue(app.buttons["Weiter bearbeiten"].waitForExistence(timeout: 5))
    app.buttons["Weiter bearbeiten"].tap()
    showEditorField(title, towardEarlier: true)
    XCTAssertTrue(title.isHittable)
    XCTAssertEqual(title.value as? String, "Entwurf bei größter Schrift")
    showEditorField(room)
    XCTAssertEqual(room.value as? String, "Langer Flur 2")
    app.buttons["Abbrechen"].tap()
    XCTAssertTrue(app.buttons["Änderungen verwerfen"].waitForExistence(timeout: 5))
    app.buttons["Änderungen verwerfen"].tap()
    XCTAssertTrue(actions.waitForExistence(timeout: 5))
    actions.tap()
    app.buttons["Originale"].tap()
    let original = app.buttons["Originaldatei"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    show(original)
    original.tap()
    XCTAssertTrue(app.navigationBars["Quellfoto"].waitForExistence(timeout: 5))
    capture("large-type-retained-original")
  }
  func testSimpleDestinationPersistsAndCanBeCancelled() {
    launch()
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Kalender"].tap()
    let destination = app.buttons["calendar-destination"]
    XCTAssertTrue(destination.waitForExistence(timeout: 8))
    XCTAssertTrue((44...56).contains(destination.frame.height))
    edgeTap(destination)
    let choices = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "destination-"))
    XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Neue Termine speichern in"].exists)
    XCTAssertFalse(app.buttons["Kalenderzugriff erlauben"].exists)
    XCTAssertFalse(app.buttons["Laßnitzhöhe-Kalender verwenden"].exists)
    XCTAssertFalse(app.buttons["info-Speicherziel"].exists)
    let choice = choices.allElementsBoundByIndex.first { !$0.isSelected }!
    let selectedID = choice.identifier
    XCTAssertTrue((44...56).contains(choice.frame.height))
    edgeTap(choice)
    XCTAssertTrue(choice.isSelected)
    capture("simple-destination-selection")
    app.buttons["save-calendar-destination"].tap()
    XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
    capture("simple-calendar-settings")
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 25))
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Kalender"].tap()
    edgeTap(app.buttons["calendar-destination"])
    XCTAssertTrue(app.buttons[selectedID].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons[selectedID].isSelected)
    let alternative = choices.allElementsBoundByIndex.first { !$0.isSelected }!
    edgeTap(alternative)
    app.navigationBars["Speicherziel"].buttons.firstMatch.tap()
    edgeTap(app.buttons["calendar-destination"])
    XCTAssertTrue(app.buttons[selectedID].isSelected)
    capture("simple-destination-after-restart")
  }
  func testTracingActionsAndDiagnosticsAreConsistent() throws {
    for dark in [false, true] {
      launch(dark: dark)
      let mode = dark ? "dark" : "light"
      app.tabBars.buttons["Mehr"].tap()
      show(app.buttons["open-tracing"])
      app.buttons["open-tracing"].tap()
      let photos = app.buttons["trace-photos"]
      let files = app.buttons["trace-files"]
      XCTAssertTrue(photos.waitForExistence(timeout: 5))
      XCTAssertEqual(photos.frame.height, files.frame.height, accuracy: 1)
      XCTAssertTrue((44...56).contains(photos.frame.height))
      XCTAssertEqual(
        photos.staticTexts.firstMatch.frame.minX, files.staticTexts.firstMatch.frame.minX,
        accuracy: 1)
      capture("simple-tracing-\(mode)")
      for (button, cancel) in [(photos, photoPickerCancel), (files, app.buttons["Abbrechen"])] {
        edgeTap(button)
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        expectation(
          for: NSPredicate(format: "hittable == true"), evaluatedWith: cancel)
        waitForExpectations(timeout: 10)
        cancel.tap()
        expectation(
          for: NSPredicate(format: "hittable == true"), evaluatedWith: app.navigationBars["Tracing"]
        )
        waitForExpectations(timeout: 15)
      }
      app.navigationBars["Tracing"].buttons.firstMatch.tap()
      show(app.buttons["Diagnose"])
      app.buttons["Diagnose"].tap()
      XCTAssertTrue(
        app.staticTexts["Gesprächsmodell, Apple Intelligence"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.staticTexts.matching(identifier: "Gesprächsmodell").count, 1)
      XCTAssertFalse(app.buttons["info-Gesprächsmodell"].exists)
      capture("simple-diagnostics-\(mode)")
      app.terminate()
    }
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
    XCTAssertTrue(photoPickerCancel.waitForExistence(timeout: 8))
    photoPickerCancel.tap()
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
