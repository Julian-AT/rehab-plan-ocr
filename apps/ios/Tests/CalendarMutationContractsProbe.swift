import Foundation

@main struct CalendarMutationContractsProbe {
  static func main() throws {
    let patches: [[String: Any]] = [
      ["location": ""], ["reminder_minutes": NSNull()],
      ["reminder_minutes": 0], ["reminder_minutes": 60],
    ]
    for source in patches {
      let patch = try NativeEventEditPatch(journal: source)
      precondition(NSDictionary(dictionary: patch.journalValue).isEqual(to: source))
    }
    for invalid in [
      ["title": NSNull()], ["notes": "not editable"], ["reminder_minutes": true],
      ["reminder_minutes": 1.5], ["reminder_minutes": -1], ["reminder_minutes": 10081],
    ] as [[String: Any]] {
      do {
        _ = try NativeEventEditPatch(journal: invalid)
        preconditionFailure("Invalid patch accepted")
      } catch {}
    }
    for receipt in [
      ["status": "acknowledged", "message": "Checked by the user"],
      ["status": "saved", "event": NSNull(), "operation_id": "saved-id"],
      ["status": "uncertain", "message": "Interrupted"],
      ["status": "saved", "event": NSNull(), "maintenance_warnings": ["Reminder warning"]],
    ] as [[String: Any]] {
      let result = try NativeEventMutationResult(journal: receipt)
      let journal = try result.journalValue
      precondition(NSDictionary(dictionary: journal).isEqual(to: receipt))
    }
    let event: [String: Any] = [
      "id": "occurrence", "external_id": "native", "calendar_id": "selected",
      "calendar_title": "Therapie", "source": "Local", "occurrence": "2031-05-15T08:00:00Z",
      "recurring": true, "system_only": false, "writable": true, "fingerprint": "unchanged",
      "values": [
        "title": "Therapie", "start_utc": "2031-05-15T08:00:00Z",
        "end_utc": "2031-05-15T09:00:00Z", "timezone": "Europe/Vienna", "location": "Raum 2",
        "reminder_minutes": NSNull(),
      ],
      "metadata": [
        "notes": "Keep", "alarms": [["absolute": NSNull(), "relative": -600]],
        "recurrence": [["frequency": 1, "weekdays": [2, 4]]], "future": [true, NSNull()],
      ],
    ]
    let proposal: [String: Any] = [
      "token": "proposal", "session": "session", "revision": 7, "expires_at": 2_000_000_000,
      "kind": "update", "calendar_id": "selected", "calendar_title": "Therapie · Local",
      "before": event, "patch": ["location": "", "reminder_minutes": NSNull()],
      "undo_of": NSNull(), "owned_id": NSNull(), "origin": "manual",
    ]
    let restored = try NativeEventEditProposal(journal: proposal)
    let journal = try restored.journalValue
    precondition(NSDictionary(dictionary: journal).isEqual(to: proposal))
    print("Typed mutation patches preserve unchanged/disabled/minutes and historical result shapes")
  }
}
