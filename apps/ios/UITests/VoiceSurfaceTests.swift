import XCTest

@MainActor final class VoiceSurfaceTests: XCTestCase {
  private var app: XCUIApplication!
  private var state: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "voice-state").firstMatch
  }
  private var waveform: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "microphone-waveform").firstMatch
  }
  private func launch(
    dark: Bool = false, large: Bool = false, input: Bool = false, silent: Bool = false
  ) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", "one"]
      + (dark ? ["--preview-dark"] : [])
      + (large
        ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
      + (input ? ["--preview-microphone"] : [])
      + (silent ? ["--preview-microphone-silent"] : [])
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Sprechen"].waitForExistence(timeout: 25))
    app.tabBars.buttons["Sprechen"].tap()
  }
  override func tearDown() async throws {
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    app.terminate()
  }
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func edgeTap(_ button: XCUIElement) {
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
  }
  func testMicrophoneLevelsDriveWaveformAndStopEndsSession() {
    for (dark, large) in [(false, false), (true, false), (true, true)] {
      launch(dark: dark, large: large, input: true)
      let mode = large ? "large" : dark ? "dark" : "light"
      let start = app.buttons["speak"]
      XCTAssertEqual(start.label, "Gespräch starten")
      XCTAssertEqual(start.images.count, 0)
      XCTAssertFalse(app.buttons["stop-speech"].exists)
      capture("voice-start-\(mode)")
      edgeTap(start)
      XCTAssertTrue(waveform.waitForExistence(timeout: 5))
      expectation(for: NSPredicate(format: "value == %@", "Ton erkannt"), evaluatedWith: waveform)
      waitForExpectations(timeout: 5)
      XCTAssertEqual(state.value as? String, "recording")
      XCTAssertFalse(start.exists)
      let stop = app.buttons["stop-speech"]
      XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
      XCTAssertGreaterThan(stop.frame.minX, waveform.frame.maxX)
      XCTAssertEqual(stop.frame.midY, waveform.frame.midY, accuracy: 1)
      let first = waveform.screenshot().pngRepresentation
      Thread.sleep(forTimeInterval: 1)
      XCTAssertNotEqual(first, waveform.screenshot().pngRepresentation)
      capture("voice-input-\(mode)")
      edgeTap(stop)
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertFalse(waveform.exists)
      XCTAssertEqual(state.value as? String, "idle")
      capture("voice-stopped-\(mode)")
      start.tap()
      XCTAssertTrue(waveform.waitForExistence(timeout: 5))
      XCUIDevice.shared.press(.home)
      app.activate()
      XCTAssertTrue(start.waitForExistence(timeout: 5))
      XCTAssertFalse(waveform.exists)
      app.terminate()
    }
  }
  func testSilentMicrophoneStaysFlat() {
    launch(input: true, silent: true)
    app.buttons["speak"].tap()
    XCTAssertTrue(waveform.waitForExistence(timeout: 5))
    XCTAssertEqual(waveform.value as? String, "Still")
    let first = waveform.screenshot().pngRepresentation
    Thread.sleep(forTimeInterval: 1)
    XCTAssertEqual(first, waveform.screenshot().pngRepresentation)
    capture("voice-silence")
    edgeTap(app.buttons["stop-speech"])
    XCTAssertTrue(app.buttons["speak"].exists)
  }
  func testRealSpokenResponseStaysCenteredAndInputDoesNotFollowPlayback() {
    for large in [false, true] {
      launch(dark: large, large: large)
      app.buttons["voice-details"].tap()
      app.buttons["voice-next"].tap()
      app.navigationBars["Gesprächsdetails"].buttons.firstMatch.tap()
      expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: state)
      waitForExpectations(timeout: 45)
      let response = app.staticTexts["voice-response"]
      XCTAssertTrue(response.waitForExistence(timeout: 5))
      for _ in 0..<2 {
        XCTAssertEqual(response.frame.midX, state.frame.midX, accuracy: 1)
        XCTAssertEqual(response.frame.midY, state.frame.midY, accuracy: 1)
        XCTAssertEqual(waveform.value as? String, "Still")
        Thread.sleep(forTimeInterval: 1)
      }
      capture(large ? "voice-answer-large" : "voice-answer-center")
      edgeTap(app.buttons["stop-speech"])
      XCTAssertTrue(app.buttons["speak"].exists)
      XCTAssertFalse(response.exists)
      app.terminate()
    }
  }
}
