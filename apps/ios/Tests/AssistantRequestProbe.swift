import Foundation
import RehaCore

@main struct AssistantRequestProbe {
  @MainActor static func main() async throws {
    let fixture = URL(fileURLWithPath: "ml/evaluation/conversation/fixtures/native-contract.json")
    let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: Any]]
    for row in rows {
      let valid = row["valid"] as! Bool
      do {
        _ = try AssistantInterpretation.decode(
          row["json"] as! String,
          references: row["references"] as! [String], timezone: "Europe/Vienna")
        precondition(valid, "Invalid compact request crossed the native boundary: \(row["id"]!)")
      } catch { precondition(!valid, "Valid compact request was rejected: \(row["id"]!)") }
    }
    func decode(_ json: String) throws -> ConversationInterpretation {
      try AssistantInterpretation.decode(json, references: ["r1"], timezone: "Europe/Vienna")
    }
    let duration = try decode(
      #"{"action":"update","query":{"reference":"r1"},"change":{"duration":20}}"#)
    precondition(duration.action == .update && duration.change?.duration == 20)
    precondition(
      duration.change?.title == nil && duration.change?.newDate == nil
        && duration.change?.newTime == nil)
    precondition(duration.query?.reference == "r1")
    let title = try decode(
      #"{"action":"update","query":{"reference":"r1"},"change":{"title":"Entspannung"}}"#)
    precondition(title.change?.title == "Entspannung" && title.change?.duration == nil)
    let after = try decode(
      #"{"action":"calendar","query":{"detail":"next","reference":"r1","after":"12:00","before":"18:00"}}"#
    )
    precondition(after.query?.afterMinutes == 720 && after.query?.beforeMinutes == 1080)
    precondition(after.query?.days == 90 && after.query?.timezone == "Europe/Vienna")
    let help = try decode(#"{"action":"help","topic":"capture"}"#)
    precondition(help.action == .help && help.reply == nil && help.helpTopic == .capture)
    precondition(AppHelpContent.text(for: .capture) == AppHelpContent.capture)
    let cancel = try decode(#"{"action":"cancel"}"#)
    precondition(cancel.action == .cancel && cancel.query == nil && cancel.change == nil)
    let clarify = try decode(#"{"action":"clarify","problem":"invalid_date"}"#)
    precondition(clarify.action == .clarify && clarify.problem == .invalidDate)
    precondition(
      AssistantInterpretation.clarification(clarify.problem, address: .du)
        == "Dieses Datum gibt es nicht. Bitte Tag, Monat und Jahr nennen.")
    for malformed in [
      ConversationInterpretation(action: .cancel, query: CalendarQuestion()),
      ConversationInterpretation(action: .cancel, change: VoiceIntent()),
      ConversationInterpretation(action: .help, reply: "Model invented help", helpTopic: .capture),
      ConversationInterpretation(action: .calendar, query: CalendarQuestion(), helpTopic: .privacy),
    ] {
      do {
        try malformed.validate()
        preconditionFailure("Cross-action fields accepted")
      } catch InterpretationError.invalidRequest {}
    }
    print(
      "Assistant typed boundary passed: \(rows.count) shared cases, partial changes, references, cancellation and fixed app help"
    )
  }
}
