import Foundation

@main struct CalendarImportContractsProbe {
  static func main() throws {
    func values(_ minutes: Int?) -> NativeImportValues {
      NativeImportValues(
        title: "Erfundene Therapie", startUTC: "2026-09-18T08:00:00Z",
        endUTC: "2026-09-18T08:30:00Z", timezone: "Europe/Vienna", location: "Raum 3",
        notes: "Erfundene Notiz: äöü ·\nZweite Zeile", reminderMinutes: minutes)
    }
    for minutes in [nil, 0, 10, Int(UInt32.max)] {
      let original = values(minutes)
      let decoded = try JSONDecoder().decode(
        Values.self, from: JSONSerialization.data(withJSONObject: original.legacyValue))
      precondition(NativeImportValues(decoded) == original)
      let unsigned = try original.unsignedReminderMinutes
      precondition(unsigned == minutes.map(UInt32.init))
    }
    for minutes in [-1, Int(UInt32.max) + 1] {
      do {
        _ = try values(minutes).unsignedReminderMinutes
        preconditionFailure("External alarms must not wrap into different unsigned values")
      } catch NativeServiceError.storage {}
    }
    let snapshot = NativeImportSnapshot(current: ["owned": values(nil)], protectedIDs: ["owned"])
    let wire = snapshot.legacyValue
    let current = wire["current"] as! [String: [String: Any]]
    precondition(current["owned"]?["reminder_minutes"] is NSNull)
    precondition(wire["protected_ids"] as? [String] == ["owned"])
    for status in [NativeImportWriteStatus.saved, .failed, .uncertain, .conflict] {
      let result = NativeImportWriteResult(
        id: "owned", status: status, externalID: nil, error: nil, maintenanceWarnings: [])
      let legacy = result.legacyValue
      precondition(Set(legacy.keys) == ["id", "status"])
      precondition(legacy["status"] as? String == status.rawValue)
    }
    let saved = NativeImportWriteResult(
      id: "owned", status: .saved, externalID: "external", error: nil,
      maintenanceWarnings: ["Nachbearbeitung ausstehend"])
    precondition(saved.legacyValue["status"] as? String == "saved")
    precondition(saved.legacyValue["external_id"] as? String == "external")
    precondition(
      saved.legacyValue["maintenance_warnings"] as? [String] == saved.maintenanceWarnings)
    precondition(saved.legacyValue["error"] == nil)
    let preferences = ReminderPreferences(
      enabled: false, minutes: nil, sound: false, preview: false)
    let restored = try JSONDecoder().decode(
      ReminderPreferences.self, from: JSONEncoder().encode(preferences))
    precondition(restored == preferences)
    let gate = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      defer { gate.signal() }
      do {
        let result: NativeImportWriteResult = try NativeServiceCall.waitValue(for: .apply) {
          $0(.success(saved))
        }
        precondition(
          result.status == .saved && result.maintenanceWarnings == saved.maintenanceWarnings)
      } catch { preconditionFailure("Typed import callback failed: \(error)") }
      do {
        let _: NativeImportWriteResult = try NativeServiceCall.waitValue(
          for: .apply, timeout: 0.001
        ) {
          _ in
        }
        preconditionFailure("Missing write completion must stay uncertain")
      } catch { precondition(error as? NativeServiceError == .uncertainWrite) }
    }
    precondition(gate.wait(timeout: .now() + 5) == .success)
    print(
      "Import contracts: notes, reminders, protected identities, legacy fields, durable status and uncertain callbacks passed"
    )
  }
}
