import EventKit
import XCTest

final class EventEditingTests: XCTestCase {
    private let editing = EventEditingService(isForeground: { true })
    private func call(_ command: String, _ args: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: args)
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            let request = ServiceRequest(arguments: data) { continuation.resume(with: $0) }
            editing.perform(command, request)
        }
        return try JSONSerialization.jsonObject(with: response) as? [String: Any] ?? [:]
    }
    func testExternalMetadataOccurrenceAndUndo() async throws {
        #if targetEnvironment(simulator)
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw XCTSkip("Simulator runner calendar access required") }
        let store = AgendaService.shared.store
        let source = try XCTUnwrap(store.defaultCalendarForNewEvents?.source)
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Erfundener Bearbeitungstest \(UUID().uuidString)"; calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }
        let event = EKEvent(eventStore: store); event.calendar = calendar
        event.title = "Erfundene Einzeltherapie"; event.location = "Raum 1"; event.notes = "Diese fremde Notiz muss bleiben."
        event.url = URL(string: "https://example.org/original")
        event.startDate = Date(timeIntervalSince1970: floor(Date().addingTimeInterval(86400).timeIntervalSince1970))
        event.endDate = event.startDate.addingTimeInterval(1800); event.timeZone = TimeZone(identifier: "Europe/Vienna")
        event.alarms = [EKAlarm(relativeOffset: -600), EKAlarm(absoluteDate: event.startDate.addingTimeInterval(-3600))]
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))]
        try store.save(event, span: .thisEvent, commit: true)
        let iso = ISO8601DateFormatter()
        let query: [String: Any] = ["calendar_ids": [calendar.calendarIdentifier], "start_utc": iso.string(from: event.startDate.addingTimeInterval(-3600)), "end_utc": iso.string(from: event.startDate.addingTimeInterval(4*86400)), "records": []]
        let initialResponse = try await call("queryEvents", query)
        let initial = try XCTUnwrap(initialResponse["events"] as? [[String: Any]])
        XCTAssertEqual(initial.count, 3)
        let target = initial[1]
        let checked = try await call("getEvent", ["event": target])
        XCTAssertNotNil(checked["event"] as? [String: Any], "Occurrence could not be resolved")
        if let current = checked["event"] as? [String: Any] {
            XCTAssertTrue(NSDictionary(dictionary: current).isEqual(to: target), "Unchanged snapshot must remain stable across repeated occurrence lookup")
        }
        XCTAssertEqual(target["system_only"] as? Bool, false)
        let token = UUID().uuidString
        let proposal: [String: Any] = ["token": token, "kind": "update", "calendar_id": calendar.calendarIdentifier, "before": target, "patch": ["location": "Raum 2"]]
        let saved = try await call("mutateEvent", ["proposal": proposal, "recovery_only": false])
        XCTAssertEqual(saved["status"] as? String, "saved")
        let repeated = try await call("mutateEvent", ["proposal": proposal, "recovery_only": false])
        XCTAssertEqual(repeated["status"] as? String, "saved")
        let queried = try await call("queryEvents", query)
        let current = try XCTUnwrap(queried["events"] as? [[String: Any]])
        XCTAssertEqual(current.count, 3)
        let locations = current.compactMap { ($0["values"] as? [String: Any])?["location"] as? String }
        XCTAssertEqual(locations, ["Raum 1", "Raum 2", "Raum 1"])
        for item in current {
            let metadata = try XCTUnwrap(item["metadata"] as? [String: Any])
            XCTAssertEqual(metadata["notes"] as? String, event.notes)
            XCTAssertEqual(metadata["url"] as? String, "https://example.org/original")
            XCTAssertEqual((metadata["alarms"] as? [Any])?.count, 2)
        }
        let stale: [String: Any] = ["token": UUID().uuidString, "kind": "remove", "calendar_id": calendar.calendarIdentifier, "before": target, "patch": [:]]
        let conflict = try await call("mutateEvent", ["proposal": stale, "recovery_only": false])
        XCTAssertEqual(conflict["status"] as? String, "conflict")
        let after = try XCTUnwrap(saved["event"] as? [String: Any])
        let undo: [String: Any] = ["token": UUID().uuidString, "kind": "update", "calendar_id": calendar.calendarIdentifier, "before": after, "patch": ["location": "Raum 1"], "undo_of": token]
        let undone = try await call("mutateEvent", ["proposal": undo, "recovery_only": false])
        XCTAssertEqual(undone["status"] as? String, "saved")
        let deleteToken = UUID().uuidString
        let removal: [String: Any] = ["token": deleteToken, "kind": "remove", "calendar_id": calendar.calendarIdentifier, "before": try XCTUnwrap(undone["event"]), "patch": [:]]
        let removed = try await call("mutateEvent", ["proposal": removal, "recovery_only": false])
        XCTAssertEqual(removed["status"] as? String, "saved")
        let afterRemoval = try await call("queryEvents", query)
        XCTAssertEqual((afterRemoval["events"] as? [Any])?.count, 2)
        let restored: [String: Any] = ["token": UUID().uuidString, "kind": "create", "calendar_id": calendar.calendarIdentifier, "patch": try XCTUnwrap(target["values"]), "undo_of": deleteToken]
        let restoration = try await call("mutateEvent", ["proposal": restored, "recovery_only": false])
        XCTAssertEqual(restoration["status"] as? String, "saved")
        let final = try await call("queryEvents", query)
        XCTAssertEqual((final["events"] as? [Any])?.count, 3)
        #endif
    }
}
