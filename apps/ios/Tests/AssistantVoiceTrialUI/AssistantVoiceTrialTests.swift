import XCTest

/// An isolated experimental target. These five tests are not part of the normal UI suite.
@MainActor final class AssistantVoiceTrialTests: XCTestCase {
  private var app: XCUIApplication!
  private var signal: AssistantVoiceTrialSignal!
  private func launch(_ scenario: String) throws {
    continueAfterFailure = false
    let environment = ProcessInfo.processInfo.environment
    let run = try XCTUnwrap(environment["REHA_ASSISTANT_VOICE_RUN_ID"])
    let model = try XCTUnwrap(environment["REHA_ASSISTANT_VOICE_MODEL"])
    XCTAssertNotNil(UUID(uuidString: run))
    XCTAssertTrue(model.hasPrefix("assistant-development-002/"))
    signal = try XCTUnwrap(AssistantVoiceTrialSignal(runID: run.lowercased(), scenario: scenario))
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments = [
      "-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--assistant-model-trial",
      "--assistant-voice-trial", scenario, "--assistant-voice-run", run,
      "--assistant-voice-model", model, "--audio-evidence",
    ]
    if scenario == "live-confirm" {
      app.launchArguments += [
        "--agenda-fixture", "voice-answers", "--preview-now", "2031-05-15T06:00:00Z",
      ]
    }
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Sprechen"].waitForExistence(timeout: 30))
    expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: app.tabBars.buttons["Sprechen"])
    waitForExpectations(timeout: 20)
    app.tabBars.buttons["Sprechen"].tap()
    wait("ready", timeout: 10)
    app.buttons["speak"].tap()
  }
  private func wait(_ status: String, timeout: TimeInterval = 120) {
    let signal = self.signal!
    expectation(for: NSPredicate { _, _ in signal.matches(status) }, evaluatedWith: nil)
    waitForExpectations(timeout: timeout)
  }
  private func capture(_ label: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = label
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func cancelProposalAndRestart() {
    wait("proposal")
    XCTAssertTrue(app.navigationBars["Termin prüfen"].exists)
    XCTAssertTrue(app.buttons["confirm-event"].isHittable)
    capture("actual-proposal-before-cancel")
    app.navigationBars["Termin prüfen"].buttons["Abbrechen"].tap()
    wait("cancelled")
    XCTAssertFalse(app.buttons["confirm-event"].exists)
    XCTAssertTrue(app.buttons["speak"].waitForExistence(timeout: 5))
    capture("proposal-cancelled-without-confirmation")
    app.buttons["speak"].tap()
  }
  private func confirmVisibleProposal() {
    wait("proposal")
    let button = app.buttons["confirm-event"]
    XCTAssertTrue(button.isHittable)
    XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    capture("actual-proposal-before-button")
    button.tap()
    wait("confirmed-audio-finished")
    XCTAssertFalse(button.exists)
    capture("actual-button-confirmed-and-spoken")
  }
  func testNativeProviderCalendarFollowupsAndAudio() throws {
    try launch("calendar-audio")
    wait("flow-finished")
    capture("native-provider-follow-up-and-real-audio")
    app.buttons["stop-speech"].tap()
    wait("cancelled")
    XCTAssertTrue(app.buttons["speak"].exists)
  }
  func testMinimalCreatePreservesSpokenFieldsAndRequiresButton() throws {
    try launch("minimal-create")
    // Field retention and unjustified clarification are scored from the app's
    // observations even if its predefined recovery turn reaches this proposal.
    confirmVisibleProposal()
  }
  func testNativeAnswerThenTitleOnlyChangeCancelAndButton() throws {
    try launch("rename-confirm")
    cancelProposalAndRestart()
    confirmVisibleProposal()
  }
  func testLateNativeReplyAfterCancelCannotReachViewOrCalendar() throws {
    try launch("late-cancel")
    wait("native-return-held")
    XCTAssertFalse(app.buttons["confirm-event"].exists)
    capture("actual-native-return-awaits-delivery")
    app.buttons["stop-speech"].tap()
    wait("late-drained")
    XCTAssertTrue(app.buttons["speak"].exists)
    XCTAssertFalse(app.buttons["confirm-event"].exists)
    XCTAssertFalse(app.staticTexts["voice-response"].exists)
    capture("late-native-return-discarded")
  }
  func testLiveFixtureWriteAppearsOnlyAfterVisibleButton() throws {
    try launch("live-confirm")
    cancelProposalAndRestart()
    confirmVisibleProposal()
    app.tabBars.buttons["Termine"].tap()
    // The same fixed preview clock seeded tomorrow's owned EventKit events.
    app.swipeLeft()
    let event = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", "Gymnastik")
    ).firstMatch
    XCTAssertTrue(event.waitForExistence(timeout: 10))
    capture("owned-live-calendar-title-after-confirmation")
  }
  override func tearDown() async throws {
    guard let app else { return }
    app.terminate()
    // Cleanup only IDs recorded by PreviewFixtures; private observation files remain.
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 25))
    app.terminate()
  }
}
