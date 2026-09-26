import Foundation
import RehaCore

@main struct ConversationReplyProbe {
  static func main() throws {
    let suite = "reha-reply-probe-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    precondition(VoiceAddress.saved(in: defaults) == .du)
    defaults.set("Sie", forKey: VoiceAddress.key)
    precondition(VoiceAddress.saved(in: UserDefaults(suiteName: suite)!) == .sie)
    defaults.removeObject(forKey: VoiceAddress.key)
    precondition(VoiceAddress.saved(in: defaults) == .du)
    let values = CalendarEventValues(
      title: "Frühstück I", start_utc: "2026-09-14T07:15:00Z",
      end_utc: "2026-09-14T07:45:00Z", timezone: "Europe/Vienna", location: "",
      reminder_minutes: nil)
    let event = CalendarEvent(
      id: "fixture", external_id: "e", calendar_id: "c",
      calendar_title: "Privater Kalendername", source: "Private Kalenderquelle", occurrence: "",
      recurring: false,
      system_only: false, writable: true, values: values, metadata: .object([:]), fingerprint: "f")
    let reply = ConversationReply(event.spoken)
    precondition(reply.text.contains("Frühstück I"))
    precondition(reply.speech.contains("Frühstück eins beginnt"))
    precondition(!reply.text.contains("Privat") && !reply.speech.contains("Privat"))
    precondition(!reply.text.contains("nicht angegeben") && !reply.text.contains("Therapeut"))
    precondition(
      event.detailAnswer(to: "Welcher Raum?") == "Für diesen Termin ist mir kein Raum bekannt.")
    precondition(
      event.detailAnswer(to: "Wer ist der Therapeut?")
        == "Für diesen Termin ist mir kein Therapeut bekannt.")
    precondition(
      event.values.title == "Frühstück I" && event.calendar_title == "Privater Kalendername")
    for address in VoiceAddress.allCases {
      let proposal = EventProposalView(
        token: "p", session: "s", revision: 1, kind: "update",
        calendar_id: "c", calendar_title: "Privater Kalendername", before: event,
        patch: ["start_utc": .string("2026-09-14T08:15:00Z")], undo_of: nil)
      let prepared = ConversationReply(proposal.conversationText(address: address))
      precondition(prepared.text.contains(address == .du ? "Bitte prüfe" : "Bitte prüfen Sie"))
      precondition(!prepared.text.contains("Privat"))
      precondition(prepared.speech.contains("Frühstück eins"))
      var replay = ConversationReply()
      for phrase in prepared.phrases { replay.appendPrepared(phrase) }
      precondition(replay == prepared, "Repeat uses precisely the prepared phrases")
    }
    let written = "Frühstück II beginnt um 09:15 Uhr. Dr. Muster kommt in Raum 2.14."
    var stream = StableSpeechPhrases()
    var streamed = ConversationReply()
    for end in written.indices {
      for phrase in stream.append(snapshot: String(written[...end])) { streamed.append(phrase) }
    }
    for phrase in stream.append(snapshot: written, final: true) { streamed.append(phrase) }
    precondition(streamed.text == written)
    precondition(streamed.speech == normalizeSpeech(text: written))
    print(
      "Replies: Du/Sie persistence/reset, missing details, source omission, preserved originals, proposals, streamed normalization and exact replay passed"
    )
  }
}
