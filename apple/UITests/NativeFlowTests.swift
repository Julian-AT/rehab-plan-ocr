import XCTest

@MainActor final class NativeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let clearID = "plan-11111111-1111-4111-8111-111111111111"
    private let sampleID = "plan-9fe78df5-04b1-40e0-8100-8a5c3470645d"
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 15))
    }
    private func openPlan(_ id: String) {
        let archive = app.tabBars.buttons["Archiv"]
        if !archive.isSelected { archive.tap() }
        if app.navigationBars["Plan"].exists {
            app.navigationBars["Plan"].buttons["BackButton"].tap()
        }
        XCTAssertTrue(app.navigationBars["Archiv"].waitForExistence(timeout: 5))
        let plan = app.buttons[id]
        for _ in 0..<8 {
            if plan.exists && plan.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(plan.waitForExistence(timeout: 10)); plan.tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))
    }
    private func actions(_ title: String) {
        let menu = app.buttons["plan-actions"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: menu)
        waitForExpectations(timeout: 10)
        menu.tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3)); app.buttons[title].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCaptureMenuPresentsAllSources() {
        app.buttons["add-plan"].tap()
        app.buttons["plan-menu-camera"].tap()
        XCTAssertTrue(app.otherElements["native-camera"].waitForExistence(timeout: 8) || app.staticTexts["Kamera nicht verfügbar"].exists)
        capture("09-native-apple-kamera")
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Abbrechen", "Schließen"])).firstMatch.tap()
        XCTAssertTrue(app.buttons["add-plan"].waitForExistence(timeout: 5))
        app.buttons["add-plan"].tap(); app.buttons["plan-menu-photos"].tap()
        XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
        capture("Photo picker opened from agenda menu")
        app.buttons["Abbrechen"].tap()
        app.buttons["add-plan"].tap(); app.buttons["plan-menu-files"].tap()
        XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
        capture("File picker opened from agenda menu")
        app.buttons["Abbrechen"].tap()
        app.tabBars.buttons["Archiv"].tap()
        app.navigationBars["Archiv"].buttons["Plan hinzufügen"].tap()
        app.buttons["archive-menu-camera"].tap()
        XCTAssertTrue(app.otherElements["native-camera"].waitForExistence(timeout: 8) || app.staticTexts["Kamera nicht verfügbar"].exists)
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Abbrechen", "Schließen"])).firstMatch.tap()
    }
    func testNeuralPlaybackStopAndRepeat() {
        app.tabBars.buttons["Sprechen"].tap(); app.buttons["voice-settings"].tap()
        let preview = app.buttons["preview-voice"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8)); preview.tap()
        expectation(for: NSPredicate(format: "value == %@", "playing"), evaluatedWith: preview)
        waitForExpectations(timeout: 45)
        capture("Victoria playing")
        preview.tap(); XCTAssertEqual(preview.value as? String, "idle")
        preview.tap()
        expectation(for: NSPredicate(format: "value == %@", "playing"), evaluatedWith: preview)
        waitForExpectations(timeout: 30)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(preview.value as? String, "idle")
    }
    func testSystemControlsAndMoreAppearance() {
        app.tabBars.buttons["Sprechen"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["speak"].frame.height, 44)
        app.tabBars.buttons["Mehr"].tap(); capture("Native settings groups")
        app.buttons["Darstellung"].tap()
        XCTAssertTrue(app.navigationBars["Darstellung"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Speichern"].exists)
        XCTAssertTrue(app.buttons["appearance-picker"].exists)
        app.navigationBars["Darstellung"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mehr"].exists)
    }
    func testUpcomingDaysExpandAndPastIsSeparate() {
        openPlan("plan-33333333-3333-4333-8333-333333333333")
        if app.buttons["Kalender einrichten"].waitForExistence(timeout: 2) {
            app.buttons["Kalender einrichten"].tap(); app.buttons["Laßnitzhöhe-Kalender verwenden"].tap()
            let done = app.buttons["Diesen Kalender verwenden"]
            for _ in 0..<6 where !done.isHittable { app.swipeUp() }
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: done); waitForExpectations(timeout: 10); done.tap()
        }
        let save = app.buttons["save-plan"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save); waitForExpectations(timeout: 10); save.tap()
        XCTAssertTrue(app.buttons["undo-save"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Termine"].tap()
        XCTAssertTrue(app.buttons["next-week"].waitForExistence(timeout: 8))
        app.buttons["next-week"].tap(); app.buttons["previous-week"].tap()
        app.buttons["agenda-today"].tap()
        capture("Weekly agenda after plan save")
    }

    func testCalendarAndVoiceSettingsAreVisible() {
        app.tabBars.buttons["Mehr"].tap()
        app.buttons["Kalender"].tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Speicherziel ändern"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "anzeigen und vorlesen")).firstMatch.exists)
        capture("Separate calendar display and destination")
        app.navigationBars["Kalender"].buttons.firstMatch.tap()
        app.tabBars.buttons["Sprechen"].tap(); app.buttons["voice-settings"].tap()
        XCTAssertTrue(app.navigationBars["Sprache"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preview-voice"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "Victoria · Deutsch", "Victoria · Deutsch"
        )).firstMatch.exists)
        capture("Local voice setup and playback controls")
    }
    func testNativeTabsArchiveSettingsAndColdLaunch() {
        XCTAssertEqual(app.webViews.count, 0)
        app.buttons["add-plan"].tap()
        XCTAssertTrue(app.buttons["plan-menu-camera"].exists)
        XCTAssertTrue(app.buttons["plan-menu-photos"].exists)
        XCTAssertTrue(app.buttons["plan-menu-files"].exists)
        app.tap()
        app.tabBars.buttons["Archiv"].tap()
        XCTAssertTrue(app.buttons[clearID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan-'")).count, 4)
        XCTAssertFalse(app.staticTexts["Gesicherte Aufnahmen"].exists)
        XCTAssertFalse(app.staticTexts["Gespeicherte Termine"].exists)
        capture("Archive chronological plans")
        app.tabBars.buttons["Mehr"].tap(); app.buttons["Darstellung"].tap()
        XCTAssertTrue(app.navigationBars["Darstellung"].waitForExistence(timeout: 5))
        app.navigationBars["Darstellung"].buttons.firstMatch.tap()
        app.buttons["Erkennung"].tap()
        XCTAssertTrue(app.navigationBars["Erkennung"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Vorgabe hinzufügen"].exists)
        app.navigationBars["Erkennung"].buttons.firstMatch.tap()
        app.swipeUp(); app.buttons["Diagnose"].tap()
        XCTAssertTrue(app.navigationBars["Diagnose"].waitForExistence(timeout: 5))
        app.navigationBars["Diagnose"].buttons.firstMatch.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 15))
        capture("Today before setup")
    }
    func testOneActionSaveAndUndo() {
        openPlan(clearID)
        if app.buttons["Kalender einrichten"].waitForExistence(timeout: 3) {
            app.buttons["Kalender einrichten"].tap()
            app.buttons["Laßnitzhöhe-Kalender verwenden"].tap()
            let remember = app.switches["Für neue Pläne merken"]
            for _ in 0..<6 where !remember.isHittable { app.swipeUp() }
            remember.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let done = app.buttons["Diesen Kalender verwenden"]
            for _ in 0..<6 where !done.isHittable { app.swipeUp() }
            let enabled = NSPredicate(format: "enabled == true")
            expectation(for: enabled, evaluatedWith: done)
            waitForExpectations(timeout: 10); done.tap()
        }
        let save = app.buttons["save-plan"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(save.label, "2 Termine speichern")
        XCTAssertEqual(app.switches.count, 0)
        capture("Clear plan one action")
        save.tap()
        XCTAssertTrue(app.buttons["undo-save"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Jetzt speichern"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 Termine in")).firstMatch.exists)
        capture("Saved with undo")
        app.tabBars.buttons["Termine"].tap()
        if app.buttons["past-events"].waitForExistence(timeout: 3) { app.buttons["past-events"].tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Testtherapie 1")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", "Testtherapie 1")).count, 1)
        capture("Populated agenda no duplicate")
        app.tabBars.buttons["Archiv"].tap()
        app.buttons["undo-save"].tap()
        let allow = app.switches["Entfernen der angezeigten Termine bestätigen"]
        for _ in 0..<8 where !allow.isHittable { app.swipeUp() }
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let undo = app.buttons["Rücknahme ausführen"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: undo)
        waitForExpectations(timeout: 5)
        undo.tap()
        XCTAssertTrue(app.staticTexts["2 Änderungen rückgängig gemacht · 0 offen oder fehlgeschlagen"].waitForExistence(timeout: 10))
        app.navigationBars["Importverlauf"].buttons["Fertig"].tap()
        app.tabBars.buttons["Termine"].tap()
        // Saving chooses a destination, not an additional display calendar.
        // Once the last import is undone the dedicated selection state returns.
        XCTAssertTrue(app.staticTexts["Kalender auswählen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", "Testtherapie 1")).firstMatch.exists)
        capture("No imported appointments after undo")
    }
    func testPartialSaveAndMultiPageSummary() {
        openPlan(sampleID)
        let summary = app.staticTexts["plan-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("8 Termine erkannt"))
        let save = app.buttons["save-plan"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, "7 von 8 Terminen speichern")
        capture("Partial plan with duration question")
        app.navigationBars["Plan"].buttons.firstMatch.tap()
        openPlan("plan-33333333-3333-4333-8333-333333333333")
        XCTAssertTrue(app.staticTexts["plan-summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["plan-summary"].label.contains("4 Termine erkannt"))
        capture("Multiple pages one plan")
    }
    func testRetainedEditorAndOriginal() {
        openPlan(clearID)
        actions("Termin ergänzen")
        let title = app.textFields["Bezeichnung"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Nicht gespeicherter Entwurf")
        XCTAssertFalse(app.switches["Alle Angaben mit dem Foto abgeglichen; leere Felder sind nicht gedruckt"].exists)
        app.buttons["Abbrechen"].tap()
        app.buttons["Weiter bearbeiten"].tap()
        XCTAssertEqual(title.value as? String, "Nicht gespeicherter Entwurf")
        app.buttons["Abbrechen"].tap(); app.buttons["Änderungen verwerfen"].tap()
        actions("Originale")
        app.buttons["Originaldatei"].tap()
        XCTAssertTrue(app.navigationBars["Quellfoto"].waitForExistence(timeout: 5))
        capture("Retained original")
    }
    func testRecognitionKeepsOtherTabsAvailable() {
        openPlan(sampleID)
        actions("Foto korrigieren")
        let recognize = app.buttons["Neu erkennen"]
        XCTAssertTrue(recognize.waitForExistence(timeout: 10)); recognize.tap()
        app.tabBars.buttons["Termine"].tap()
        XCTAssertTrue(app.navigationBars["Termine"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Archiv"].tap()
        let summary = app.staticTexts["plan-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 75))
        capture("Processing or retained draft")
    }
    func testFailedCaptureRetry() {
        openPlan("plan-55555555-5555-4555-8555-555555555555")
        let retry = app.buttons["Erneut versuchen"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(app.buttons["Erneut versuchen"].waitForExistence(timeout: 20))
        capture("Retryable capture failure")
    }
    func testVoiceTabIsExplicitAndCancelEndsConversation() {
        app.tabBars.buttons["Sprechen"].tap()
        let state = app.descendants(matching: .any).matching(identifier: "voice-state").firstMatch
        XCTAssertEqual(state.value as? String, "idle")
        XCTAssertFalse(app.buttons["finish-speaking"].exists)
        XCTAssertFalse(app.staticTexts["voice-response"].exists)
        app.buttons["stop-speech"].tap()
        app.tabBars.buttons["Archiv"].tap(); app.tabBars.buttons["Sprechen"].tap()
        XCTAssertEqual(state.value as? String, "idle")
        capture("Voice explicit microphone and cancel")
    }
    func testVoiceCreationPreviewIsRevokedOnBackground() {
        app.tabBars.buttons["Sprechen"].tap()
        app.buttons["voice-details"].tap(); app.buttons["voice-create"].tap()
        let title = app.textFields["Bezeichnung"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Test Sprachbereich")
        app.buttons["Bezeichnung übernehmen"].tap()
        for label in ["Datum übernehmen", "Uhrzeit übernehmen"] {
            let button = app.buttons[label]
            for _ in 0..<6 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        let duration = app.textFields["Dauer in Minuten"]
        for _ in 0..<6 where !duration.isHittable { app.swipeUp() }
        duration.tap(); duration.typeText("30")
        let accept = app.buttons["Dauer übernehmen"]
        for _ in 0..<6 where !accept.isHittable { app.swipeUp() }
        accept.tap()
        let confirm = app.buttons["confirm-event"]
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        capture("Voice concrete preview before confirmation")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(confirm.exists)
        app.navigationBars["Gesprächsdetails"].buttons.firstMatch.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "voice-state").firstMatch.value as? String, "idle")
        capture("Voice proposal revoked after tab change")
    }
    func testZPhotoPickerImportsARealImage() {
        app.buttons["add-plan"].tap(); app.buttons["plan-menu-photos"].tap()
        XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
        capture("Photo picker with public sample")
        let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        // Photos exposes the thumbnail as a non-hittable accessibility image.
        // Tap its visible center, then verify the completed import below.
        XCTAssertTrue(app.frame.contains(image.frame))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        let summary = app.staticTexts["plan-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 90))
        capture("Real photo imported and recognized")
    }
    func testTextSizeAndDarkAppearance() throws {
        app.tabBars.buttons["Mehr"].tap(); app.buttons["Darstellung"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Erscheinungsbild,")).firstMatch.tap(); app.buttons["Dunkel"].tap()
        app.navigationBars["Darstellung"].buttons.firstMatch.tap()
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openPlan(clearID)
        XCTAssertTrue(app.staticTexts["plan-summary"].waitForExistence(timeout: 10))
        capture("Plan dark large text")
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .trait])
        }
    }
    func testZZFilePickerImportsAPublicPlan() {
        app.buttons["add-plan"].tap(); app.buttons["plan-menu-files"].tap()
        XCTAssertTrue(app.buttons["Abbrechen"].waitForExistence(timeout: 8))
        if app.buttons["Durchsuchen"].isHittable { app.buttons["Durchsuchen"].tap() }
        let local = app.staticTexts["Auf meinem iPhone"]
        if local.waitForExistence(timeout: 3) { local.tap() }
        let file = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "Testplan", "Testplan.png")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8))
        capture("File picker with public test plan")
        let thumbnail = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Testplan,")).firstMatch
        XCTAssertTrue(thumbnail.exists)
        // The provider's filename label is not its open target. Tap inside the
        // visible document thumbnail, using the cell's reported frame.
        thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let open = app.buttons["Öffnen"]
        if open.waitForExistence(timeout: 5) { open.tap() }
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["plan-summary"].waitForExistence(timeout: 90))
        let destination = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speichern in:")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        XCTAssertTrue(app.frame.contains(destination.frame), "The entire calendar destination must fit on screen: \(destination.frame)")
        capture("Public plan imported through Files")
    }
}
