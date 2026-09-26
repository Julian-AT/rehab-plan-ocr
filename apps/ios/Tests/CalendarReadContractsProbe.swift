import Foundation

@main struct CalendarReadContractsProbe {
  static func main() throws {
    let original: [String: Any] = [
      "id": "calendar|event|2026-09-18T08:00:00Z", "external_id": "event",
      "calendar_id": "calendar",
      "calendar_title": "Therapie", "source": "Local", "occurrence": "2026-09-18T08:00:00Z",
      "recurring": true, "system_only": true, "writable": false, "fingerprint": "preserve",
      "values": [
        "title": "Termin", "start_utc": "2026-09-18T08:00:00Z", "end_utc": "2026-09-18T09:00:00Z",
        "timezone": "Europe/Vienna", "location": "Raum 2", "reminder_minutes": NSNull(),
      ],
      "metadata": [
        "notes": "Unverändert", "alarms": [["relative": -600, "absolute": NSNull()]],
        "recurrence": [["unknown_future_field": [1, true, NSNull()] as [Any]]], "all_day": true,
      ],
    ]
    for imported in [false, true] {
      var snapshot = original
      if imported { snapshot["import_id"] = "owned" }
      let typed = try NativeCalendarEvent(snapshot: snapshot)
      let roundtrip = try typed.legacyValue
      precondition(NSDictionary(dictionary: snapshot).isEqual(to: roundtrip))
      precondition(typed.recurring && typed.systemOnly && !typed.writable)
      precondition(typed.values.reminderMinutes == nil)
      let reference = try NativeCalendarReference(legacy: snapshot)
      precondition(reference.calendarID == "calendar" && reference.externalID == "event")
      precondition(reference.expectedStartUTC == "2026-09-18T08:00:00Z")
      let result = NativeCalendarReadResult(
        events: [typed], unavailableCalendarIDs: ["missing"],
        unavailableEvents: [
          NativeCalendarUnavailableEvent(id: "owned-missing", startUTC: "start", endUTC: "end")
        ])
      let legacy = try result.legacyValue
      precondition(
        (legacy["unavailable_events"] as? [[String: String]])?.first?["id"] == "owned-missing")
    }
    for access: NativeCalendarAccessStatus in [.fullAccess, .denied, .restricted, .notDetermined] {
      let observed = NativeCalendarPlatformStatus(
        access: access, lastReadAt: access == .fullAccess ? "2026-09-18T08:00:00Z" : nil,
        calendars: access == .fullAccess
          ? [NativeCalendarStatusItem(id: "visible", title: "Therapie", writable: false)] : [],
        unavailableCalendarIDs: access == .fullAccess ? ["unavailable"] : [])
      let legacy = observed.legacyValue
      precondition(legacy["access"] as? String == access.rawValue)
      let calendars = legacy["calendars"] as! [[String: Any]]
      if access == .fullAccess {
        precondition(calendars.count == 1 && calendars[0]["id"] as? String == "visible")
        precondition(calendars[0]["writable"] as? Bool == false)
        precondition(legacy["last_read_at"] as? String == "2026-09-18T08:00:00Z")
        precondition(legacy["unavailable_calendar_ids"] as? [String] == ["unavailable"])
      } else {
        precondition(calendars.isEmpty && legacy["last_read_at"] is NSNull)
        precondition(legacy["unavailable_calendar_ids"] as? [String] == [])
      }
      precondition(JSONSerialization.isValidJSONObject(legacy))
    }
    var incomplete = original
    incomplete.removeValue(forKey: "fingerprint")
    do {
      _ = try NativeCalendarEvent(snapshot: incomplete)
      preconditionFailure("Incomplete event must not acquire default identity or metadata")
    } catch NativeServiceError.storage {}
    let query = try NativeCalendarQuery(legacy: [
      "calendar_ids": [], "start_utc": "start", "end_utc": "end",
      "timezone": "Europe/Vienna", "selection_revision": UInt64.max, "records": [],
    ])
    precondition(query.calendarIDs.isEmpty && query.selectionRevision == UInt64.max)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      defer { done.signal() }
      do {
        let missing: NativeCalendarEvent? = try NativeServiceCall.waitValue(for: .getEvent) {
          $0(.success(nil))
        }
        precondition(missing == nil)
        let result: NativeCalendarReadResult = try NativeServiceCall.waitValue(for: .queryEvents) {
          $0(
            .success(
              NativeCalendarReadResult(
                events: [], unavailableCalendarIDs: [], unavailableEvents: [])))
        }
        precondition(result.events.isEmpty)
      } catch { preconditionFailure("Typed completion failed: \(error)") }
      do {
        let _: NativeCalendarEvent? = try NativeServiceCall.waitValue(
          for: .getEvent, timeout: 0.001
        ) { _ in }
        preconditionFailure("Missing callback must expire")
      } catch { precondition(error as? NativeServiceError == .timeout("getEvent")) }
    }
    precondition(done.wait(timeout: .now() + 5) == .success)
    print(
      "Calendar reads: metadata/identity roundtrip, absent import identity, scope revision, platform status compatibility, typed nil and timeout passed"
    )
  }
}
