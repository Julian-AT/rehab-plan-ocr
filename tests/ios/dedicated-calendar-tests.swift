import EventKit
import XCTest

final class DedicatedCalendarTests: XCTestCase {
  func testUnavailableCalendarDoesNotCreateDuplicate() throws {
    #if targetEnvironment(simulator)
      guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        throw XCTSkip("Simulator test runner requires full calendar access.")
      }
      let suite = "at.rehakalender.tests.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      defaults.set(
        [
          "id": UUID().uuidString, "title": "Unavailable test calendar \(UUID().uuidString)",
          "source_id": UUID().uuidString, "source_title": "Unavailable test account",
          "source_type": "0",
        ],
        forKey: "reha-calendar.destination")
      let store = EKEventStore()
      let before = Set(store.calendars(for: .event).map(\.calendarIdentifier))
      XCTAssertThrowsError(try DedicatedCalendar(defaults: defaults).resolve(in: store))
      XCTAssertEqual(Set(store.calendars(for: .event).map(\.calendarIdentifier)), before)
    #else
      throw XCTSkip("Calendar mutation tests are restricted to the simulator.")
    #endif
  }
}
