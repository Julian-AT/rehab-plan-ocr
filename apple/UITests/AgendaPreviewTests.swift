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
    private var voiceState: XCUIElement { app.descendants(matching: .any).matching(identifier: "voice-state").firstMatch }
    // SwiftUI exposes a switch row and its actual trailing switch. Target the
    // visible switch, since tapping the center of the row can hit only its label.
    private func toggle(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
    private func back(_ title: String) { app.navigationBars[title].buttons.firstMatch.tap() }

    func testEmptyAndNoSelectionAreDistinct() {
        launch("empty")
        XCTAssertTrue(app.staticTexts["Heute keine Termine"].waitForExistence(timeout: 8))
        capture("01-keine-termine")
        app.terminate(); launch("no-selection")
        XCTAssertTrue(app.staticTexts["Kalender auswählen"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Heute keine Termine"].exists)
        capture("02-kalenderauswahl-fehlt")
    }
    func testWeekNavigationAndTimeline() {
        launch("timeline")
        XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
        XCTAssertTrue(row("Physiotherapie").isHittable)
        capture("03-termine-hell")
        let timeline = app.scrollViews["day-timeline"]
        XCTAssertFalse(app.staticTexts["timeline-hour-5"].exists)
        XCTAssertFalse(app.staticTexts["timeline-hour-19"].exists)
        for _ in 0..<8 where !app.staticTexts["timeline-hour-6"].isHittable { timeline.swipeDown() }
        XCTAssertTrue(app.staticTexts["timeline-hour-6"].isHittable)
        capture("31-kalender-ab-sechs")
        for _ in 0..<8 where !app.staticTexts["timeline-hour-18"].isHittable { timeline.swipeUp() }
        XCTAssertTrue(app.staticTexts["timeline-hour-18"].isHittable)
        capture("32-kalender-bis-achtzehn")

        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")).firstMatch
        let selectedID = selected.identifier
        app.buttons["next-week"].tap()
        XCTAssertTrue(app.staticTexts["Keine Termine"].waitForExistence(timeout: 8))
        app.buttons["previous-week"].tap()
        XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
        XCTAssertEqual(selected.identifier, selectedID)
        // Rapid week changes must not let the previous query replace the final week.
        app.buttons["next-week"].tap(); app.buttons["next-week"].tap(); app.buttons["previous-week"].tap()
        XCTAssertTrue(app.staticTexts["Keine Termine"].waitForExistence(timeout: 8))
        app.buttons["agenda-today"].tap()
        XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
        row("Physiotherapie").tap()
        XCTAssertTrue(app.navigationBars["Termin bearbeiten"].waitForExistence(timeout: 5))
        capture("04-terminformular")
    }
    func testFinishedDayAndAutomaticCompletion() {
        launch("complete")
        XCTAssertTrue(app.staticTexts["Zeit zum Erholen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Für heute stehen keine weiteren Termine an."].exists)
        capture("05-zeit-zum-erholen")
        app.buttons["past-events"].tap()
        XCTAssertTrue(row("Erholung nach Physiotherapie").waitForExistence(timeout: 5))
        XCTAssertTrue(row("Erholung nach Physiotherapie").label.contains("Vorbei"))
        capture("06-tagesverlauf")
        app.terminate(); launch("finishing")
        XCTAssertTrue(app.staticTexts["Zeit zum Erholen"].waitForExistence(timeout: 25))
        capture("07-automatischer-tagesabschluss")
    }
    func testShortEventsHaveSeparateHitAreas() {
        launch("short")
        let first = row("Kurztermin"), second = row("Kontrolle")
        XCTAssertTrue(first.waitForExistence(timeout: 8)); XCTAssertTrue(second.exists)
        XCTAssertGreaterThanOrEqual(first.frame.height, 43.99); XCTAssertGreaterThanOrEqual(second.frame.height, 43.99)
        XCTAssertFalse(first.frame.intersects(second.frame))
        first.tap(); XCTAssertTrue(app.navigationBars["Termin bearbeiten"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap(); second.tap()
        XCTAssertTrue(app.textFields["Bezeichnung"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Bezeichnung"].value as? String, "Kontrolle")
        app.buttons["Fertig"].tap(); capture("08-kurze-termine")
    }
    func testOverlapsAllDayAndDarkAppearance() {
        launch("full", extra: ["--preview-dark"])
        XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
        XCTAssertTrue(row("Übernacht-Beobachtung").exists)
        XCTAssertTrue(row("Aufenthalt Laßnitzhöhe").exists)
        XCTAssertFalse(row("Physiotherapie").frame.intersects(row("Ärztliches Gespräch").frame))
        capture("09-ueberlappung-dunkel")
        app.tabBars.buttons["Sprechen"].tap(); capture("10-sprechen-dunkel")
        XCTAssertEqual(voiceState.value as? String, "idle")
    }
    func testLargestTypeUsesDayListAndNativeSettings() throws {
        launch("full", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--preview-dark"])
        XCTAssertTrue(app.collectionViews["agenda-accessible-list"].waitForExistence(timeout: 8) || app.descendants(matching: .any)["agenda-accessible-list"].exists)
        capture("11-tagesliste-groesste-schrift")
        app.tabBars.buttons["Sprechen"].tap()
        XCTAssertTrue(app.buttons["speak"].isHittable)
        XCTAssertTrue(app.buttons["stop-speech"].isHittable)
        capture("12-sprechen-groesste-schrift")
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .trait])
        app.tabBars.buttons["Mehr"].tap(); capture("13-mehr-groesste-schrift")
        app.tabBars.buttons["Archiv"].tap(); capture("14-archiv-groesste-schrift")
    }
    func testMoreNavigationImmediateSettingsAndRestart() {
        launch("empty")
        app.tabBars.buttons["Mehr"].tap(); capture("15-mehr-hell")
        app.buttons["Erinnerungen"].tap()
        XCTAssertTrue(app.navigationBars["Erinnerungen"].waitForExistence(timeout: 5))
        let sound = app.switches["reminder-sound"], preview = app.switches["reminder-preview"]
        let soundBefore = sound.value as? String, previewBefore = preview.value as? String
        toggle(sound); toggle(preview); toggle(sound)
        let expectedPreview = preview.value as? String
        XCTAssertNotEqual(expectedPreview, previewBefore)
        XCTAssertEqual(sound.value as? String, soundBefore)
        capture("16-erinnerungen-sofort-gespeichert")
        back("Erinnerungen")
        app.buttons["Erkennung"].tap(); app.buttons["Vorgabe hinzufügen"].tap()
        XCTAssertFalse(app.buttons["Übernehmen"].isEnabled)
        capture("17-neue-vorgabe-validierung")
        app.buttons["Abbrechen"].tap(); back("Erkennung")
        app.buttons["Kalender"].tap(); app.buttons["Speicherziel ändern"].tap()
        XCTAssertTrue(app.navigationBars["Speicherziel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Abbrechen"].exists)
        capture("18-speicherziel-native-navigation")
        back("Speicherziel"); back("Kalender")
        app.swipeUp(); app.buttons["Diagnose"].tap()
        XCTAssertTrue(app.navigationBars["Diagnose"].waitForExistence(timeout: 5)); back("Diagnose")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Version 0.3.0"].isHittable)
        capture("30-mehr-version")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 15)); app.tabBars.buttons["Mehr"].tap()
        app.buttons["Erinnerungen"].tap()
        XCTAssertEqual(sound.value as? String, soundBefore); XCTAssertEqual(preview.value as? String, expectedPreview)
        if expectedPreview != previewBefore { toggle(preview) }
        capture("19-einstellungen-nach-neustart")
    }
    func testSettingsFailureShowsSavedValueAndRetry() {
        launch("empty", extra: ["--preview-settings-failure"])
        app.tabBars.buttons["Mehr"].tap(); app.buttons["Erinnerungen"].tap()
        let sound = app.switches["reminder-sound"]
        let before = sound.value as? String
        toggle(sound)
        let retry = app.buttons["retry-settings"]
        for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertEqual(sound.value as? String, before)
        capture("27-einstellungen-speicherfehler")
        retry.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: retry)
        waitForExpectations(timeout: 8)
        for _ in 0..<4 where !sound.isHittable { app.swipeDown() }
        XCTAssertNotEqual(sound.value as? String, before)
        toggle(sound)
    }
    func testVoiceIdleDetailsCancelAndUnavailableRecognition() {
        launch("one")
        app.tabBars.buttons["Sprechen"].tap()
        XCTAssertEqual(voiceState.value as? String, "idle")
        XCTAssertFalse(app.staticTexts["voice-response"].exists)
        XCTAssertFalse(app.buttons["voice-next"].exists)
        XCTAssertTrue(app.buttons["speak"].isHittable)
        capture("20-sprechen-ruhe")
        app.buttons["voice-details"].tap()
        XCTAssertTrue(app.buttons["voice-next"].waitForExistence(timeout: 5))
        capture("21-gespraechsdetails")
        back("Gesprächsdetails")
        app.buttons["speak"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            let allow = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Erlauben", "Allow", "OK"])).firstMatch
            if allow.exists { allow.tap() }
        }
        // This simulator does not support Apple's on-device SpeechTranscriber.
        expectation(for: NSPredicate(format: "value == %@", "error"), evaluatedWith: voiceState)
        waitForExpectations(timeout: 15)
        capture("22-spracherkennung-nativer-hinweis")
        if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
        app.buttons["stop-speech"].tap()
        XCTAssertEqual(voiceState.value as? String, "idle")
        XCTAssertTrue(app.buttons["speak"].isEnabled)
        app.buttons["voice-settings"].tap(); capture("23-spracheinstellungen")
    }
    func testVoiceCreationRequiresExplicitConfirmation() {
        launch("one")
        app.tabBars.buttons["Sprechen"].tap(); app.buttons["voice-details"].tap(); app.buttons["voice-create"].tap()
        let title = app.textFields["Bezeichnung"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        for _ in 0..<4 where !title.isHittable { app.swipeUp() }
        title.tap(); title.typeText("Test Gespräch bestätigt")
        for label in ["Bezeichnung übernehmen", "Datum übernehmen", "Uhrzeit übernehmen"] {
            let button = app.buttons[label]
            for _ in 0..<5 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 8)); button.tap()
        }
        let duration = app.textFields["Dauer in Minuten"]
        for _ in 0..<5 where !duration.isHittable { app.swipeUp() }
        duration.tap(); duration.typeText("30")
        let accept = app.buttons["Dauer übernehmen"]
        for _ in 0..<5 where !accept.isHittable { app.swipeUp() }
        accept.tap()
        XCTAssertTrue(app.navigationBars["Termin prüfen"].waitForExistence(timeout: 10))
        let confirm = app.buttons["confirm-event"]
        XCTAssertTrue(confirm.exists)
        capture("28-sprachvorschlag-vor-bestaetigung")
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: confirm)
        waitForExpectations(timeout: 10)
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Gespeichert in")).firstMatch
        for _ in 0..<5 where !saved.isHittable { app.swipeDown() }
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        capture("29-sprachvorschlag-gespeichert")
        app.tabBars.buttons["Termine"].tap()
        XCTAssertTrue(row("Test Gespräch bestätigt").waitForExistence(timeout: 8))
    }
    func testRealAudioDrivesOrbAndStopEndsIt() {
        launch("one", extra: ["--audio-evidence"])
        app.tabBars.buttons["Sprechen"].tap(); app.buttons["voice-details"].tap(); app.buttons["voice-next"].tap()
        back("Gesprächsdetails")
        expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: voiceState)
        waitForExpectations(timeout: 45)
        // Keep genuine playback visible long enough to review the recorded motion.
        Thread.sleep(forTimeInterval: 3)
        capture("24-sprechen-echte-wiedergabe")
        app.buttons["stop-speech"].tap()
        XCTAssertEqual(voiceState.value as? String, "idle")
        XCTAssertFalse(app.staticTexts["voice-response"].exists)
        app.buttons["voice-details"].tap(); app.buttons["voice-next"].tap()
        XCTAssertTrue(app.buttons["repeat-speech"].waitForExistence(timeout: 10))
        app.buttons["repeat-speech"].tap(); back("Gesprächsdetails")
        expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: voiceState)
        waitForExpectations(timeout: 30)
        app.tabBars.buttons["Mehr"].tap(); app.tabBars.buttons["Sprechen"].tap()
        XCTAssertEqual(voiceState.value as? String, "idle")
        capture("25-abgebrochene-wiedergabe")
    }
    func testReducedMotionSystemSettingKeepsVoiceUsable() throws {
        guard UIAccessibility.isReduceMotionEnabled else { throw XCTSkip("Enable ReduceMotionEnabled on the preview simulator") }
        launch("one")
        app.tabBars.buttons["Sprechen"].tap()
        XCTAssertTrue(app.buttons["speak"].isHittable)
        XCTAssertEqual(voiceState.value as? String, "idle")
        capture("26-bewegung-reduziert")
    }
}
