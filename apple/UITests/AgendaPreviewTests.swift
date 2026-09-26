import XCTest
import UIKit

@MainActor final class AgendaPreviewTests: XCTestCase {
    private var app: XCUIApplication!
    private func launch(_ mode: String, extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", mode] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    }
    override func tearDown() async throws {
        guard let app else { return }
        app.terminate()
        app.launchArguments = ["--agenda-fixture", "cleanup"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 15))
        app.terminate()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)).firstMatch
    }
    func testEmptyCenteredAndNoSelectionAreDistinct() {
        launch("empty")
        XCTAssertTrue(app.staticTexts["Heute keine Termine"].waitForExistence(timeout: 8))
        let text = app.staticTexts["Heute keine Termine"]
        XCTAssertGreaterThan(text.frame.midY, app.frame.height * 0.3)
        XCTAssertLessThan(text.frame.midY, app.frame.height * 0.7)
        XCTAssertGreaterThan(app.buttons.matching(identifier: "Plan hinzufügen").count, 0)
        capture("01-empty-centered")
        app.terminate(); launch("no-selection")
        XCTAssertTrue(app.staticTexts["Kalender auswählen"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Heute keine Termine"].exists)
        capture("02-calendar-selection-needed")
    }
    func testSingleAndFutureEventsAppearOnce() {
        launch("one")
        XCTAssertTrue(row("Ergotherapie").waitForExistence(timeout: 8))
        XCTAssertTrue(row("Ergotherapie").label.contains("Als Nächstes"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda-event-")).count, 1)
        capture("03-one-appointment")
        app.terminate(); launch("future")
        XCTAssertTrue(app.staticTexts["Heute keine Termine"].waitForExistence(timeout: 8))
        capture("04-no-today-with-future-days")
        app.buttons["load-more-days"].tap()
        XCTAssertTrue(row("Training Tag 1").waitForExistence(timeout: 5))
        XCTAssertFalse(row("Training Tag 4").exists)
        for _ in 0..<6 where !app.buttons["load-more-days"].isHittable { app.swipeUp() }
        app.buttons["load-more-days"].tap()
        for _ in 0..<6 where !row("Training Tag 5").isHittable { app.swipeUp() }
        XCTAssertTrue(row("Training Tag 5").exists)
        XCTAssertFalse(app.buttons["load-more-days"].exists)
        capture("05-five-future-days")
    }
    func testOverlapsMidnightAndPastInLight() {
        launch("full")
        XCTAssertTrue(row("Übernacht-Beobachtung").waitForExistence(timeout: 8))
        XCTAssertTrue(row("Übernacht-Beobachtung").label.contains("Jetzt"))
        XCTAssertTrue(row("Aufenthalt Laßnitzhöhe").label.contains("Ganztägig"))
        XCTAssertTrue(row("Physiotherapie").label.contains("Jetzt"))
        XCTAssertTrue(row("Ärztliches Gespräch").exists)
        capture("06-agenda-light-overlaps")
        let past = app.buttons["past-events"]
        for _ in 0..<6 where !past.isHittable { app.swipeUp() }
        XCTAssertTrue(past.waitForExistence(timeout: 5)); past.tap()
        for _ in 0..<6 where !row("Frühgymnastik").isHittable { app.swipeUp() }
        capture("07-past-expanded-before-check")
        XCTAssertTrue(row("Frühgymnastik").waitForExistence(timeout: 5))
        XCTAssertTrue(row("Frühgymnastik").label.contains("Vorbei"))
        capture("07-past-expanded")
        app.tabBars.buttons["Mehr"].tap(); capture("08-more-light")
        app.buttons["Kalender"].tap()
        // EventKit also contains the simulator's default calendars. SwiftUI
        // exposes both the toggle row and its switch, so scope by fixture name.
        XCTAssertGreaterThanOrEqual(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Therapie")).count, 2)
        capture("09-same-name-calendars")
        app.tabBars.buttons["Sprechen"].tap(); capture("10-speaking-idle")
        XCTAssertEqual(app.staticTexts["voice-state"].value as? String, "idle")
    }
    func testLargestTypeAndDarkModeRemainUsable() throws {
        launch("full", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--preview-dark"])
        XCTAssertTrue(row("Übernacht-Beobachtung").waitForExistence(timeout: 8))
        capture("11-agenda-dark-accessibility")
        app.tabBars.buttons["Sprechen"].tap()
        let speak = app.buttons["speak"]
        for _ in 0..<8 where !speak.isHittable { app.swipeUp() }
        XCTAssertTrue(speak.isHittable)
        XCTAssertGreaterThanOrEqual(speak.frame.height, 44)
        capture("12-speaking-largest-type")
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .trait])
        app.tabBars.buttons["Archiv"].tap(); capture("13-archive-dark-accessibility")
    }
    func testRealAudioDrivesOrbAndStopEndsIt() {
        launch("one")
        app.tabBars.buttons["Sprechen"].tap()
        app.buttons["voice-next"].tap()
        let state = app.staticTexts["voice-state"]
        expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: state)
        waitForExpectations(timeout: 45)
        capture("14-speaking-real-audio")
        app.buttons["stop-speech"].tap()
        XCTAssertEqual(state.value as? String, "idle")
        XCTAssertFalse(app.buttons["stop-speech"].isEnabled)
        let response = app.staticTexts["voice-response"].label
        app.buttons["repeat-speech"].tap()
        expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: state)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(app.staticTexts["voice-response"].label, response)
        app.tabBars.buttons["Mehr"].tap(); app.tabBars.buttons["Sprechen"].tap()
        XCTAssertEqual(state.value as? String, "idle")
        capture("15-speaking-after-stop")
    }
    func testUnavailableRecognitionCanStartFreshAfterTabChange() {
        launch("empty")
        app.tabBars.buttons["Sprechen"].tap(); app.buttons["speak"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Erlauben", "Allow", "OK"])).firstMatch
            if allow.exists { allow.tap() }
        }
        // SpeechTranscriber is unavailable on this iPhone simulator runtime.
        let state = app.staticTexts["voice-state"]
        expectation(for: NSPredicate(format: "value == %@", "error"), evaluatedWith: state)
        waitForExpectations(timeout: 15)
        capture("16-recognition-unavailable")
        app.tabBars.buttons["Mehr"].tap(); app.tabBars.buttons["Sprechen"].tap()
        XCTAssertEqual(state.value as? String, "idle")
        XCTAssertTrue(app.buttons["speak"].isEnabled)
    }
    func testReducedMotionSystemSettingKeepsVoiceUsable() throws {
        guard UIAccessibility.isReduceMotionEnabled else {
            throw XCTSkip("Enable ReduceMotionEnabled on the test simulator for this acceptance check")
        }
        XCTAssertTrue(UIAccessibility.isReduceMotionEnabled)
        launch("one")
        app.tabBars.buttons["Sprechen"].tap()
        XCTAssertTrue(app.buttons["speak"].isHittable)
        XCTAssertEqual(app.staticTexts["voice-state"].value as? String, "idle")
        let automaticRecording = expectation(for: NSPredicate(format: "value == %@", "recording"), evaluatedWith: app.staticTexts["voice-state"])
        automaticRecording.isInverted = true
        waitForExpectations(timeout: 6)
        capture("17-speaking-reduced-motion")
    }
}
