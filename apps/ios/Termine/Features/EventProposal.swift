import Foundation

struct EventProposalView: Codable, Identifiable, Sendable {
  let token: String
  let session: String
  let revision: UInt64
  let kind: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_title: String
  let before: CalendarEvent?
  let patch: [String: JSONValue]
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let undo_of: String?
  var id: String { token }
  var button: String {
    kind == "create"
      ? "Termin speichern"
      : kind == "remove" ? "Diesen Kalendereintrag löschen" : "Änderung speichern"
  }
  var after: CalendarEventValues? {
    guard kind != "remove" else { return nil }
    var values =
      before?.values
      ?? CalendarEventValues(
        title: "", start_utc: "", end_utc: "", timezone: "Europe/Vienna", location: "",
        reminder_minutes: nil)
    for (key, value) in patch {
      switch (key, value) {
      case ("title", .string(let v)): values.title = v
      case ("start_utc", .string(let v)): values.start_utc = v
      case ("end_utc", .string(let v)): values.end_utc = v
      case ("timezone", .string(let v)): values.timezone = v
      case ("location", .string(let v)): values.location = v
      case ("reminder_minutes", .number(let v)): values.reminder_minutes = Int(v)
      case ("reminder_minutes", .null): values.reminder_minutes = nil
      default: break
      }
    }
    return values
  }
  var spoken: String { conversationText(address: .saved()) }
  func conversationText(address: VoiceAddress) -> String {
    let action =
      kind == "remove"
      ? "Diesen Kalendereintrag löschen: \(before?.values.spoken ?? "")"
      : kind == "update"
        ? "Bisher: \(before?.values.spoken ?? "") Neu: \(after?.spoken ?? "")"
        : "Neuer Termin: \(after?.spoken ?? "")"
    return
      "\(action) \(before?.recurring == true ? "Die Änderung betrifft nur dieses Serienvorkommen. " : "")\(address.confirmation)"
  }
}
