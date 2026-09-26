import UIKit
import XCTest

@MainActor final class AgendaPreviewTests: XCTestCase {
  private var app: XCUIApplication!
  private var motionSettings: XCUIApplication?
  private var originalMotionSetting: String?
  private func motionSwitch(in settings: XCUIApplication) -> XCUIElement {
    settings.switches.matching(
      NSPredicate(format: "label IN %@", ["Reduce Motion", "Bewegung reduzieren"])
    ).firstMatch
  }
  private func launch(_ mode: String, extra: [String] = []) {
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "at.rehakalender.personal")
    app.launchArguments =
      ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT", "--agenda-fixture", mode] + extra
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 20))
    // The shell is visible while its persistent-data recovery gate still
    // disables navigation. A visible tab is not yet an actionable tab.
    expectation(
      for: NSPredicate(format: "enabled == true"),
      evaluatedWith: app.tabBars.buttons["Termine"])
    waitForExpectations(timeout: 20)
  }
  override func tearDown() async throws {
    if let settings = motionSettings, let original = originalMotionSetting {
      settings.activate()
      let toggle = motionSwitch(in: settings)
      XCTAssertTrue(toggle.waitForExistence(timeout: 10))
      if toggle.value as? String != original {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      }
      let restored = expectation(
        for: NSPredicate(format: "value == %@", original), evaluatedWith: toggle)
      await fulfillment(of: [restored], timeout: 10)
      settings.terminate()
    }
    guard let app else { return }
    app.terminate()
    app.launchArguments = ["--agenda-fixture", "cleanup"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Termine"].waitForExistence(timeout: 15))
    app.terminate()
  }
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func applicationPixels(_ screenshot: XCUIScreenshot) throws -> Data {
    // voice-state ignores safe areas, so XCTest includes the changing system
    // clock. Use the same 160-pixel status-bar exclusion as the visual baseline.
    // Every app pixel below it still participates; no image tolerance is applied.
    let image = try XCTUnwrap(screenshot.image.cgImage)
    XCTAssertGreaterThan(image.height, 160)
    let content = try XCTUnwrap(
      image.cropping(to: CGRect(x: 0, y: 160, width: image.width, height: image.height - 160)))
    return try XCTUnwrap(UIImage(cgImage: content).pngData())
  }
  private func row(_ title: String) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
    ).firstMatch
  }
  private var voiceState: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "voice-state").firstMatch
  }
  // SwiftUI exposes a switch row and its actual trailing switch. Target the
  // visible switch, since tapping the center of the row can hit only its label.
  private func toggle(_ element: XCUIElement) {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
  }
  private func back(_ title: String) { app.navigationBars[title].buttons.firstMatch.tap() }

  func testTodayDeepLinkReturnsFromAnotherDayAndTab() throws {
    launch("readable")
    let selection = NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    let today = app.buttons.matching(selection).firstMatch.label
    app.swipeLeft()
    XCTAssertTrue(row("Physiotherapie Tag 1").waitForExistence(timeout: 8))
    XCTAssertNotEqual(app.buttons.matching(selection).firstMatch.label, today)
    app.tabBars.buttons["Mehr"].tap()
    XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "reha-calendar://today")))
    XCTAssertTrue(app.buttons["agenda-today"].waitForExistence(timeout: 8))
    expectation(
      for: NSPredicate(format: "label == %@", today),
      evaluatedWith: app.buttons.matching(selection).firstMatch)
    waitForExpectations(timeout: 8)
    capture("today-deep-link")
  }

  func testMissingOwnedLinkKeepsSelectedDayAndAppointments() throws {
    launch("readable")
    app.swipeLeft()
    let title = "Physiotherapie Tag 1"
    XCTAssertTrue(row(title).waitForExistence(timeout: 8))
    let selectedDay = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    ).firstMatch.label
    app.tabBars.buttons["Mehr"].tap()
    XCUIDevice.shared.system.open(
      try XCTUnwrap(URL(string: "reha-calendar://event/\(UUID().uuidString)")))
    let alert = app.alerts["Termin öffnen"]
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    XCTAssertTrue(
      alert.staticTexts["Die lokale Zuordnung zu diesem Termin ist nicht mehr vorhanden."].exists)
    alert.buttons["OK"].tap()
    XCTAssertTrue(row(title).waitForExistence(timeout: 8))
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
      ).firstMatch.label, selectedDay)
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(
          format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "agenda-event-", title)
      ).count, 1)
    capture("missing-owned-event-link")
  }

  func testTodayLinkDismissesPreviousLinkError() throws {
    launch("readable")
    let selection = NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    let today = app.buttons.matching(selection).firstMatch.label
    app.swipeLeft()
    XCTAssertTrue(row("Physiotherapie Tag 1").waitForExistence(timeout: 8))
    XCUIDevice.shared.system.open(
      try XCTUnwrap(URL(string: "reha-calendar://event/\(UUID().uuidString)")))
    let alert = app.alerts["Termin öffnen"]
    XCTAssertTrue(alert.waitForExistence(timeout: 10))
    XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "reha-calendar://today")))
    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: alert)
    waitForExpectations(timeout: 8)
    XCTAssertTrue(app.buttons["agenda-today"].exists)
    XCTAssertEqual(app.buttons.matching(selection).firstMatch.label, today)
    capture("today-dismisses-previous-link-error")
  }

  func testSwipingAndCompleteAppointmentLabels() {
    // Keep the 09:00 row visible when paging from Sunday into Monday.
    // Calendar paging intentionally preserves the initial time scroll anchor.
    launch("readable", extra: ["--preview-now", "2026-09-20T06:00:00Z"])
    // Left advances, including on the resting/empty state; no arrow needed.
    app.swipeLeft()
    let next = row("Physiotherapie Tag 1")
    XCTAssertTrue(next.waitForExistence(timeout: 8))
    XCTAssertTrue(next.label.contains("Anna Beispiel"))
    XCTAssertTrue(next.label.contains("Laßnitzhöhe"))
    XCTAssertTrue(next.label.contains("Raum 2.14"))
    let short = row("Kontrolle Tag 1")
    XCTAssertTrue(short.exists)
    XCTAssertTrue(short.label.contains("Erdgeschoss"))
    XCTAssertGreaterThanOrEqual(short.frame.height, 44)
    XCTAssertFalse(short.frame.intersects(next.frame))
    capture("01-kalender-uebersicht-ort-therapeut")
    let week = app.descendants(matching: .any).matching(identifier: "agenda-week").firstMatch
    week.swipeLeft()
    XCTAssertTrue(row("Physiotherapie Tag 1").isHittable)
    week.swipeRight()
    XCTAssertTrue(row("Physiotherapie Tag 1").waitForExistence(timeout: 8))
    let selected = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    ).firstMatch.label
    app.scrollViews["day-timeline"].swipeUp()
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
      ).firstMatch.label, selected)
    let training = row("Training Tag 1")
    let ergo = row("Ergotherapie Tag 1")
    XCTAssertEqual(training.frame.minY, ergo.frame.minY, accuracy: 1)
    XCTAssertFalse(training.frame.intersects(ergo.frame))
    capture("02-kalender-ueberlappende-termine")
    for _ in 0..<7 { app.swipeLeft() }
    XCTAssertTrue(row("Physiotherapie Tag 8").waitForExistence(timeout: 8))
    app.swipeRight()
    XCTAssertTrue(row("Physiotherapie Tag 7").waitForExistence(timeout: 8))
    capture("03-wischen-ueber-wochengrenze")
  }
  func testDayTimeAxisPagesWithContentAcrossEmptyDay() throws {
    launch("axis")
    let days = app.scrollViews["agenda-days"]
    XCTAssertTrue(days.waitForExistence(timeout: 8))
    days.swipeLeft()
    XCTAssertTrue(row("Therapie Tag 1, 12 Uhr").waitForExistence(timeout: 8))
    XCTAssertEqual(days.frame.width, app.frame.width, accuracy: 1)
    let selected = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    ).firstMatch
    let beforeDay = selected.label
    let timeline = app.scrollViews["day-timeline"]
    let origin = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
    origin.press(
      forDuration: 0.02, thenDragTo: origin.withOffset(CGVector(dx: 40, dy: -170)),
      withVelocity: .slow, thenHoldForDuration: 0.1)
    XCTAssertEqual(selected.label, beforeDay)
    let hour = try XCTUnwrap(
      days.staticTexts.matching(identifier: "timeline-hour-12")
        .allElementsBoundByIndex.first(where: \.isHittable))
    let anchorY = hour.frame.minY
    let anchorX = hour.frame.minX
    XCTAssertLessThan(anchorX, 56)
    capture("page-axis-01-vertikale-diagonale")
    let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    start.press(
      forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: -100, dy: 1)),
      withVelocity: .slow, thenHoldForDuration: 1)
    XCTAssertEqual(selected.label, beforeDay)
    XCTAssertEqual(hour.frame.minX, anchorX, accuracy: 1)
    XCTAssertEqual(hour.frame.minY, anchorY, accuracy: 2)
    days.swipeLeft()
    XCTAssertTrue(app.staticTexts["Keine Termine"].waitForExistence(timeout: 8))
    XCTAssertFalse(
      days.staticTexts.matching(identifier: "timeline-hour-12").allElementsBoundByIndex
        .contains(where: \.isHittable))
    XCTAssertEqual(days.frame.width, app.frame.width, accuracy: 1)
    XCTAssertEqual(app.staticTexts["Keine Termine"].frame.midX, app.frame.midX, accuracy: 2)
    capture("page-axis-02-leerer-nachbartag")
    let emptyStart = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    emptyStart.press(
      forDuration: 0.02, thenDragTo: emptyStart.withOffset(CGVector(dx: -100, dy: 1)),
      withVelocity: .slow, thenHoldForDuration: 1)
    XCTAssertTrue(app.staticTexts["Keine Termine"].isHittable)
    XCTAssertEqual(days.frame.width, app.frame.width, accuracy: 1)
    days.swipeLeft()
    XCTAssertTrue(row("Therapie Tag 3, 12 Uhr").waitForExistence(timeout: 8))
    let nextHour = try XCTUnwrap(
      days.staticTexts.matching(identifier: "timeline-hour-12")
        .allElementsBoundByIndex.first(where: \.isHittable))
    XCTAssertEqual(nextHour.frame.minY, anchorY, accuracy: 2)
    XCTAssertEqual(nextHour.frame.minX, anchorX, accuracy: 1)
    XCTAssertEqual(days.frame.width, app.frame.width, accuracy: 1)
    capture("page-axis-03-uhrzeit-erhalten")
    days.swipeRight()
    XCTAssertTrue(app.staticTexts["Keine Termine"].isHittable)
    days.swipeRight()
    XCTAssertTrue(row("Therapie Tag 1, 12 Uhr").isHittable)
    XCTAssertEqual(days.frame.width, app.frame.width, accuracy: 1)
  }
  func testCalendarDensityAndListPersistAfterRestart() {
    launch("readable")
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Darstellung"].tap()
    app.buttons["agenda-density"].tap()
    app.buttons["Großzügig"].tap()
    app.buttons["agenda-density"].tap()
    app.buttons["Standard"].tap()
    toggle(app.switches["agenda-list-setting"])
    capture("04-kalenderdarstellung-einstellbar")
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 15))
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Darstellung"].tap()
    XCTAssertEqual(app.buttons["agenda-density"].value as? String, "Standard")
    XCTAssertEqual(app.switches["agenda-list-setting"].value as? String, "1")
    app.tabBars.buttons["Termine"].tap()
    app.swipeLeft()
    XCTAssertTrue(
      app.descendants(matching: .any)["agenda-accessible-list"].waitForExistence(timeout: 8))
    XCTAssertTrue(row("Physiotherapie Tag 1").label.contains("Anna Beispiel"))
    capture("05-tagesliste-nach-neustart")
  }
  func testConversationWithoutAssetSetup() {
    launch("one")
    app.tabBars.buttons["Sprechen"].tap()
    XCTAssertFalse(app.buttons["stop-speech"].exists)
    XCTAssertLessThan(app.buttons["voice-details"].frame.maxY, voiceState.frame.midY)
    XCTAssertTrue(app.buttons["voice-details"].isHittable)
    XCTAssertEqual(app.buttons["speak"].label, "Gespräch starten")
    XCTAssertEqual(app.buttons["speak"].frame.midX, app.frame.midX, accuracy: 12)
    capture("06-gruener-orb-und-sprechen")
    app.buttons["voice-settings"].tap()
    XCTAssertFalse(app.buttons["Spracherkennung einrichten"].exists)
    XCTAssertTrue(app.buttons["preview-voice"].exists)
    capture("07-sprache-ohne-dateieinrichtung")
    back("Sprache")
    app.buttons["voice-details"].tap()
    let message =
      app.textFields["voice-message"].exists
      ? app.textFields["voice-message"] : app.textViews["voice-message"]
    app.buttons["voice-next"].tap()
    XCTAssertTrue(app.buttons["repeat-speech"].waitForExistence(timeout: 20))
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ergotherapie")).firstMatch
        .exists)
    capture("08-antwort-aus-kalender")
    message.tap()
    message.typeText("Hallo, erzähl mir einen Witz")
    app.buttons["voice-send"].tap()
    let freeReply = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@ OR label CONTAINS %@", "Apple Intelligence", "Die Antwort konnte"
      )
    ).firstMatch
    // Simulator has no Foundation Models runtime.
    XCTAssertTrue(freeReply.waitForExistence(timeout: 30))
    capture("10-freies-gespraech-modellstatus")
    back("Gesprächsdetails")
    app.buttons["stop-speech"].tap()
    XCTAssertEqual(voiceState.value as? String, "idle")
    XCTAssertTrue(app.buttons["speak"].isEnabled)
    app.terminate()
    launch("one", extra: ["--preview-dark"])
    app.tabBars.buttons["Sprechen"].tap()
    capture("31-sprechen-dunkel")
  }
  func testEmptyAndNoSelectionAreDistinct() {
    launch("empty")
    XCTAssertTrue(app.staticTexts["Heute keine Termine"].waitForExistence(timeout: 8))
    capture("01-keine-termine")
    app.terminate()
    launch("no-selection")
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

    let selected = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "weekday-")
    ).firstMatch
    let selectedID = selected.identifier
    app.buttons["next-week"].tap()
    XCTAssertTrue(row("Physiotherapie").exists)
    app.buttons["previous-week"].tap()
    XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
    XCTAssertEqual(selected.identifier, selectedID)
    // Rapid week changes must not let the previous query replace the final week.
    app.buttons["next-week"].tap()
    app.buttons["next-week"].tap()
    app.buttons["previous-week"].tap()
    XCTAssertTrue(row("Physiotherapie").exists)
    app.buttons["agenda-today"].tap()
    XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
    row("Physiotherapie").tap()
    XCTAssertTrue(app.navigationBars["Termin bearbeiten"].waitForExistence(timeout: 5))
    capture("04-terminformular")
  }
  func testFinishedDayAndAutomaticCompletion() {
    let justAfterMidnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(600)
    launch(
      "complete", extra: ["--preview-now", ISO8601DateFormatter().string(from: justAfterMidnight)])
    XCTAssertTrue(app.staticTexts["Zeit zum Erholen"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Für heute stehen keine weiteren Termine an."].exists)
    capture("05-zeit-zum-erholen")
    app.buttons["past-events"].tap()
    XCTAssertTrue(row("Erholung nach Physiotherapie").waitForExistence(timeout: 5))
    XCTAssertTrue(row("Erholung nach Physiotherapie").label.contains("Vorbei"))
    capture("06-tagesverlauf")
    app.terminate()
    launch("finishing")
    XCTAssertTrue(row("Erholung nach Physiotherapie").waitForExistence(timeout: 8))
    XCTAssertFalse(row("Erholung nach Physiotherapie").label.contains("Vorbei"))
    XCTAssertTrue(app.staticTexts["Zeit zum Erholen"].waitForExistence(timeout: 45))
    capture("07-automatischer-tagesabschluss")
  }
  func testShortEventsHaveSeparateHitAreas() {
    launch("short")
    let first = row("Kurztermin")
    let second = row("Kontrolle")
    XCTAssertTrue(first.waitForExistence(timeout: 8))
    XCTAssertTrue(second.exists)
    XCTAssertGreaterThanOrEqual(first.frame.height, 43.99)
    XCTAssertGreaterThanOrEqual(second.frame.height, 43.99)
    XCTAssertFalse(first.frame.intersects(second.frame))
    first.tap()
    XCTAssertTrue(app.navigationBars["Termin bearbeiten"].waitForExistence(timeout: 5))
    app.buttons["Fertig"].tap()
    second.tap()
    XCTAssertTrue(app.textFields["Bezeichnung"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields["Bezeichnung"].value as? String, "Kontrolle")
    app.buttons["Fertig"].tap()
    capture("08-kurze-termine")
  }
  func testOverlapsAllDayAndDarkAppearance() {
    launch("full", extra: ["--preview-dark"])
    let list = app.descendants(matching: .any)["agenda-accessible-list"].firstMatch
    if list.waitForExistence(timeout: 3) {
      XCTAssertTrue(row("Übernacht-Beobachtung").exists)
      XCTAssertTrue(row("Aufenthalt Laßnitzhöhe").exists)
      for _ in 0..<6 where !row("Physiotherapie").isHittable { list.swipeUp() }
      XCTAssertTrue(row("Physiotherapie").isHittable)
      XCTAssertTrue(row("Ärztliches Gespräch").exists)
    } else {
      XCTAssertTrue(row("Physiotherapie").waitForExistence(timeout: 8))
      XCTAssertFalse(row("Physiotherapie").frame.intersects(row("Ärztliches Gespräch").frame))
    }
    capture("09-ueberlappung-dunkel")
    app.tabBars.buttons["Sprechen"].tap()
    capture("10-sprechen-dunkel")
    XCTAssertEqual(voiceState.value as? String, "idle")
    app.terminate()
    launch("readable", extra: ["--preview-dark"])
    app.swipeLeft()
    XCTAssertTrue(row("Physiotherapie Tag 1").waitForExistence(timeout: 8))
    capture("11-kalender-dunkel")
  }
  func testLargestTypeWeekArrowsMoveTheDisplayedDay() throws {
    launch(
      "readable",
      extra: [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        "--preview-now", "2026-09-28T06:00:00Z",
      ])
    let date = app.descendants(matching: .any).matching(identifier: "agenda-date").firstMatch
    XCTAssertTrue(date.waitForExistence(timeout: 8))
    XCTAssertTrue(row("Physiotherapie Tag 0").waitForExistence(timeout: 8))
    XCTAssertTrue(date.isHittable)
    let week = app.descendants(matching: .any).matching(identifier: "agenda-week").firstMatch
    XCTAssertTrue(week.staticTexts["September 2026"].exists)

    app.buttons["next-week"].tap()
    XCTAssertTrue(row("Physiotherapie Tag 7").waitForExistence(timeout: 8))
    // The compact native date picker has an empty container value. Its actual
    // selected day is observed through the displayed appointments and month.
    XCTAssertTrue(date.isHittable)
    XCTAssertTrue(week.staticTexts["Oktober 2026"].exists)

    app.buttons["previous-week"].tap()
    XCTAssertTrue(row("Physiotherapie Tag 0").waitForExistence(timeout: 8))
    XCTAssertTrue(date.isHittable)
    XCTAssertTrue(week.staticTexts["September 2026"].exists)
    capture("large-type-week-navigation")
  }

  func testLargestTypeUsesDayListAndNativeSettings() throws {
    launch(
      "full",
      extra: [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        "--preview-dark",
      ])
    XCTAssertTrue(
      app.collectionViews["agenda-accessible-list"].waitForExistence(timeout: 8)
        || app.descendants(matching: .any)["agenda-accessible-list"].exists)
    capture("11-tagesliste-groesste-schrift")
    app.tabBars.buttons["Sprechen"].tap()
    XCTAssertTrue(app.buttons["speak"].isHittable)
    XCTAssertFalse(app.buttons["stop-speech"].exists)
    XCTAssertTrue(app.buttons["voice-details"].isHittable)
    capture("12-sprechen-groesste-schrift")
    try app.performAccessibilityAudit(for: [
      .elementDetection, .sufficientElementDescription, .trait,
    ])
    app.tabBars.buttons["Mehr"].tap()
    capture("13-mehr-groesste-schrift")
    app.tabBars.buttons["Archiv"].tap()
    capture("14-archiv-groesste-schrift")
  }
  func testMoreNavigationImmediateSettingsAndRestart() {
    launch("empty")
    app.tabBars.buttons["Mehr"].tap()
    capture("15-mehr-hell")
    app.buttons["Erinnerungen"].tap()
    XCTAssertTrue(app.navigationBars["Erinnerungen"].waitForExistence(timeout: 5))
    let sound = app.switches["reminder-sound"]
    let preview = app.switches["reminder-preview"]
    let soundBefore = sound.value as? String
    let previewBefore = preview.value as? String
    toggle(sound)
    toggle(preview)
    toggle(sound)
    let expectedPreview = preview.value as? String
    XCTAssertNotEqual(expectedPreview, previewBefore)
    XCTAssertEqual(sound.value as? String, soundBefore)
    capture("16-erinnerungen-sofort-gespeichert")
    back("Erinnerungen")
    app.buttons["Erfassung"].tap()
    app.buttons["Vorgabe hinzufügen"].tap()
    XCTAssertFalse(app.buttons["Übernehmen"].isEnabled)
    capture("17-neue-vorgabe-validierung")
    app.buttons["Abbrechen"].tap()
    back("Erkennung")
    app.buttons["Kalender"].tap()
    let destination = app.buttons["calendar-destination"]
    for _ in 0..<6 where !destination.isHittable { app.swipeUp() }
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
    destination.tap()
    XCTAssertTrue(app.navigationBars["Speicherziel"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Abbrechen"].exists)
    capture("18-speicherziel-native-navigation")
    back("Speicherziel")
    back("Kalender")
    app.swipeUp()
    app.buttons["Diagnose"].tap()
    XCTAssertTrue(app.navigationBars["Diagnose"].waitForExistence(timeout: 5))
    back("Diagnose")
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Version 0.3.0"].isHittable)
    capture("30-mehr-version")
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Mehr"].waitForExistence(timeout: 15))
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Erinnerungen"].tap()
    XCTAssertEqual(sound.value as? String, soundBefore)
    XCTAssertEqual(preview.value as? String, expectedPreview)
    if expectedPreview != previewBefore { toggle(preview) }
    capture("19-einstellungen-nach-neustart")
  }
  func testSettingsFailureShowsSavedValueAndRetry() {
    launch("empty", extra: ["--preview-settings-failure"])
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Erinnerungen"].tap()
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
  func testActivityCalendarStatusAndReminderFeedback() {
    launch("one")
    app.tabBars.buttons["Mehr"].tap()
    capture("quality-04-mehr-gruppen")
    let status = app.buttons["Kalenderstatus"]
    for _ in 0..<5 where !status.isHittable { app.swipeUp() }
    status.tap()
    let access = app.descendants(matching: .any)["calendar-access"].firstMatch
    XCTAssertTrue(access.waitForExistence(timeout: 10))
    XCTAssertEqual(access.value as? String, "Vollzugriff")
    let refresh = app.buttons["Aktualisieren"]
    for _ in 0..<5 where !refresh.isHittable { app.swipeUp() }
    refresh.tap()
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: refresh)
    waitForExpectations(timeout: 10)
    capture("quality-05-lesender-kalenderstatus")
    back("Kalenderstatus")
    app.buttons["Verlauf"].tap()
    XCTAssertTrue(app.navigationBars["Verlauf"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["activity-filter"].exists)
    capture("quality-06-aktivitaetsverlauf")
    back("Verlauf")
    let reminders = app.buttons["Erinnerungen"]
    for _ in 0..<5 where !reminders.isHittable { app.swipeDown() }
    reminders.tap()
    let test = app.buttons["test-reminder"]
    for _ in 0..<5 where !test.isHittable { app.swipeUp() }
    XCTAssertGreaterThanOrEqual(test.frame.height, 44)
    test.tap()
    let result = app.staticTexts.matching(
      NSPredicate(
        format: "label BEGINSWITH %@ OR label CONTAINS %@",
        "Testauftrag angenommen", "Mitteilungen sind nicht erlaubt"
      )
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 25))
    XCTAssertTrue(test.isEnabled)
    capture("quality-07-testerinnerung-rueckmeldung")
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
    let monitor = addUIInterruptionMonitor(withDescription: "Mikrofon und Spracherkennung erlauben")
    { alert in
      let allow = alert.buttons.matching(
        NSPredicate(format: "label IN %@", ["Erlauben", "Allow", "OK"])
      ).firstMatch
      guard allow.exists else { return false }
      allow.tap()
      return true
    }
    defer { removeUIInterruptionMonitor(monitor) }
    app.buttons["speak"].tap()
    // A fresh simulator's speech permission can appear after the first tap has
    // returned. Keep handling the actual system prompt until preparation ends.
    let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
      if ["recording", "error"].contains(voiceState.value as? String ?? "") { break }
      let allow = system.alerts.buttons.matching(
        NSPredicate(format: "label IN %@", ["Erlauben", "Allow", "OK"])
      ).firstMatch
      if allow.exists && allow.isHittable {
        allow.tap()
      } else {
        Thread.sleep(forTimeInterval: 0.25)
      }
    }
    XCTAssertTrue(
      ["recording", "error"].contains(voiceState.value as? String ?? ""),
      "Unexpected speech state: \(voiceState.value ?? "missing")")
    capture("22-spracherkennung-nativer-hinweis")
    if app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
    if voiceState.value as? String == "recording" {
      Thread.sleep(forTimeInterval: 3)
      XCTAssertTrue(app.buttons["stop-speech"].isHittable)
      XCTAssertFalse(app.buttons["speak"].exists)
    }
    app.buttons["stop-speech"].tap()
    XCTAssertEqual(voiceState.value as? String, "idle")
    XCTAssertTrue(app.buttons["speak"].isEnabled)
    app.buttons["voice-settings"].tap()
    capture("23-spracheinstellungen")
  }

  func testReminderIsConfirmedPendingBySystem() {
    launch("one")
    app.tabBars.buttons["Mehr"].tap()
    app.buttons["Erinnerungen"].tap()
    let enabled = app.switches["app-reminders"]
    XCTAssertTrue(enabled.waitForExistence(timeout: 5))
    let wasEnabled = enabled.value as? String == "1"
    if !wasEnabled {
      toggle(enabled)
      let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      let allow = springboard.buttons.matching(
        NSPredicate(format: "label IN %@", ["Allow", "Erlauben"])
      ).firstMatch
      if allow.waitForExistence(timeout: 5) { allow.tap() }
      expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: enabled)
      waitForExpectations(timeout: 10)
    }
    let test = app.buttons["test-reminder"]
    for _ in 0..<5 where !test.isHittable { app.swipeUp() }
    test.tap()
    let accepted = app.staticTexts.matching(
      NSPredicate(
        format: "label BEGINSWITH %@", "Testauftrag angenommen und vom System vorgemerkt.")
    ).firstMatch
    XCTAssertTrue(accepted.waitForExistence(timeout: 25))
    XCTAssertTrue(test.isEnabled)
    capture("quality-11-system-bestaetigt-testerinnerung")
    if !wasEnabled {
      for _ in 0..<5 where !enabled.isHittable { app.swipeDown() }
      toggle(enabled)
    }
  }
  func testVoiceCreationRequiresExplicitConfirmation() {
    launch("one")
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-details"].tap()
    app.buttons["voice-create"].tap()
    let title = app.textFields["Bezeichnung"]
    for _ in 0..<4 where !title.isHittable { app.swipeUp() }
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Test Gespräch bestätigt")
    for label in ["Bezeichnung übernehmen", "Datum übernehmen", "Uhrzeit übernehmen"] {
      let button = app.buttons[label]
      for _ in 0..<5 where !button.isHittable { app.swipeUp() }
      XCTAssertTrue(button.waitForExistence(timeout: 8))
      button.tap()
    }
    let duration = app.textFields["Dauer in Minuten"]
    for _ in 0..<5 where !duration.isHittable { app.swipeUp() }
    duration.tap()
    duration.typeText("30")
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
    // The conversation uses its short spoken receipt; the editor has a
    // different "Gespeichert in …" receipt. Verify the visible conversation
    // response and then the actual calendar entry below.
    let saved = app.staticTexts["voice-response-details"]
    for _ in 0..<5 where !saved.isHittable { app.swipeDown() }
    XCTAssertTrue(saved.waitForExistence(timeout: 10))
    XCTAssertTrue(saved.label.hasPrefix("Der Termin ist gespeichert."))
    capture("29-sprachvorschlag-gespeichert")
    app.tabBars.buttons["Termine"].tap()
    let outside = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Außerhalb von 06:00–18:00")
    ).firstMatch
    if outside.waitForExistence(timeout: 3) { outside.tap() }
    XCTAssertTrue(row("Test Gespräch bestätigt").waitForExistence(timeout: 8))
    row("Test Gespräch bestätigt").tap()
    let remove = app.buttons["Kalendereintrag löschen"]
    for _ in 0..<5 where !remove.isHittable { app.swipeUp() }
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    remove.tap()
    let deleteConfirmation = app.buttons["confirm-event"]
    XCTAssertTrue(deleteConfirmation.waitForExistence(timeout: 8))
    XCTAssertEqual(deleteConfirmation.label, "Diesen Kalendereintrag löschen")
    capture("quality-08-sprachtermin-loeschvorschlag")
    deleteConfirmation.tap()
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Kalendereintrag gelöscht")
      )
      .firstMatch.waitForExistence(timeout: 10))
    app.navigationBars["Termin bearbeiten"].buttons["Fertig"].tap()
    XCTAssertFalse(row("Test Gespräch bestätigt").exists)
  }
  func testRealAudioDrivesOrbAndStopEndsIt() throws {
    launch("one", extra: ["--audio-evidence"])
    app.tabBars.buttons["Sprechen"].tap()
    app.buttons["voice-details"].tap()
    app.buttons["voice-next"].tap()
    back("Gesprächsdetails")
    expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: voiceState)
    waitForExpectations(timeout: 45)
    let initialOrb = try applicationPixels(voiceState.screenshot())
    // Keep genuine playback visible long enough to review the recorded motion.
    Thread.sleep(forTimeInterval: 3)
    XCTAssertNotEqual(initialOrb, try applicationPixels(voiceState.screenshot()))
    capture("24-sprechen-echte-wiedergabe")
    app.buttons["stop-speech"].tap()
    XCTAssertEqual(voiceState.value as? String, "idle")
    XCTAssertFalse(app.staticTexts["voice-response"].exists)
    app.buttons["voice-details"].tap()
    app.buttons["voice-next"].tap()
    XCTAssertTrue(app.buttons["repeat-speech"].waitForExistence(timeout: 10))
    app.buttons["repeat-speech"].tap()
    back("Gesprächsdetails")
    expectation(for: NSPredicate(format: "value == %@", "playback"), evaluatedWith: voiceState)
    waitForExpectations(timeout: 30)
    app.tabBars.buttons["Mehr"].tap()
    app.tabBars.buttons["Sprechen"].tap()
    XCTAssertEqual(voiceState.value as? String, "idle")
    capture("25-abgebrochene-wiedergabe")
  }
  func testReducedMotionSystemSettingKeepsVoiceUsable() throws {
    continueAfterFailure = false
    #if targetEnvironment(simulator)
      // Exercise the actual accessibility environment; do not inject an app-only
      // override. The test runner permits only disposable native-test simulators.
      let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
      settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
      settings.launch()
      for titles in [["Accessibility", "Bedienungshilfen"], ["Motion", "Bewegung"]] {
        let row = settings.staticTexts.matching(NSPredicate(format: "label IN %@", titles))
          .firstMatch
        for _ in 0..<8 where !row.isHittable { settings.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
      }
      let toggle = motionSwitch(in: settings)
      XCTAssertTrue(toggle.waitForExistence(timeout: 10))
      let original = try XCTUnwrap(toggle.value as? String)
      XCTAssertTrue(["0", "1"].contains(original))
      motionSettings = settings
      originalMotionSetting = original
      if original != "1" {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      }
      expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
      waitForExpectations(timeout: 10)
      expectation(
        for: NSPredicate { _, _ in UIAccessibility.isReduceMotionEnabled }, evaluatedWith: nil)
      waitForExpectations(timeout: 10)
    #else
      throw XCTSkip("This test changes accessibility settings only on disposable simulators")
    #endif
    launch("one")
    app.tabBars.buttons["Sprechen"].tap()
    XCTAssertTrue(app.buttons["speak"].isHittable)
    XCTAssertEqual(voiceState.value as? String, "idle")
    let stillOrb = voiceState.screenshot()
    Thread.sleep(forTimeInterval: 1)
    let laterOrb = voiceState.screenshot()
    for (name, screenshot) in [
      ("reduced-motion-before", stillOrb), ("reduced-motion-after", laterOrb),
    ] {
      let attachment = XCTAttachment(screenshot: screenshot)
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    XCTAssertEqual(try applicationPixels(stillOrb), try applicationPixels(laterOrb))
    capture("26-bewegung-reduziert")
  }
}
