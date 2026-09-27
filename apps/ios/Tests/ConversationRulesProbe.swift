import Foundation

@main struct ConversationRulesProbe {
  static func main() {
    var wake = ConversationWakeState()
    precondition(!wake.update(active: false, current: false))
    precondition(wake.update(active: true, current: false))
    for _ in 0..<100 { precondition(wake.update(active: true, current: true)) }
    precondition(!wake.update(active: false, current: true), "Stopping must restore Auto-Lock")
    precondition(!wake.update(active: false, current: false))
    precondition(wake.update(active: true, current: true))
    precondition(wake.update(active: false, current: true), "Preserve an existing wake request")
    var heard = HeardSpeech()
    let firstPlayback = UUID()
    heard.capture(playback: firstPlayback, completedWords: "Frühstück eins")
    heard.capture(playback: firstPlayback, completedWords: "Frühstück eins beginnt")
    precondition(heard.text == "Frühstück eins beginnt")
    heard.capture(playback: UUID(), completedWords: "")
    precondition(!heard.text.contains("sieben Uhr"), "Unplayed remainder must not enter history")
    heard.capture(playback: UUID(), completedWords: "Bitte prüfe die Angaben.")
    precondition(heard.text == "Frühstück eins beginnt Bitte prüfe die Angaben.")
    var endpoint = SpeechEndpoint()
    for _ in 0..<300 { precondition(!endpoint.append(voice: false, transcript: "")) }
    endpoint = SpeechEndpoint(confirmedPreRoll: true)
    for _ in 0..<59 { precondition(!endpoint.append(voice: false, transcript: "Nein")) }
    precondition(endpoint.append(voice: false, transcript: "Nein"))
    endpoint = SpeechEndpoint()
    for _ in 0..<5 { precondition(!endpoint.append(voice: true, transcript: "Termine morgen")) }
    for _ in 0..<59 { precondition(!endpoint.append(voice: false, transcript: "Termine morgen")) }
    precondition(endpoint.append(voice: false, transcript: "Termine morgen"))
    endpoint = SpeechEndpoint()
    for _ in 0..<6 { _ = endpoint.append(voice: true, transcript: "Was habe ich am") }
    for _ in 0..<124 { precondition(!endpoint.append(voice: false, transcript: "Was habe ich am")) }
    precondition(endpoint.append(voice: false, transcript: "Was habe ich am"))
    endpoint = SpeechEndpoint()
    for _ in 0..<3 { _ = endpoint.append(voice: true, transcript: "") }
    for _ in 0..<300 { precondition(!endpoint.append(voice: false, transcript: "")) }
    var abbreviations = StableSpeechPhrases()
    let unfinished = "Heute folgt nach dem Frühstück beispielsweise z.B. Physiotherapie"
    precondition(abbreviations.append(snapshot: unfinished).isEmpty)
    precondition(SpeechPhrasing.phrases(unfinished).count == 1)
    precondition(
      SpeechPhrasing.phrases("Hallo! Wie kann ich dir helfen?") == [
        "Hallo!", "Wie kann ich dir helfen?",
      ])
    let long =
      "Du kannst mir Fragen zu deinen nächsten Terminen stellen, und ich schaue in deinem Kalender nach."
    precondition(SpeechPhrasing.phrases(long).count == 2)
    precondition(SpeechPhrasing.phrases(long).joined(separator: " ") == long)
    let date = "Am 14. September um 09:15 Uhr ist Dr. Muster in Raum 2.14."
    precondition(SpeechPhrasing.phrases(date) == [date])
    var phrases = StableSpeechPhrases()
    precondition(
      phrases.append(snapshot: "Am 14. September ist Dr. Muster da. Danach").joined().contains(
        "Muster da."))
    precondition(!phrases.emitted.contains("Danach"))
    precondition(
      phrases.append(
        snapshot: "Am 14. September ist Dr. Muster da. Danach frühstückst du.", final: true) == [
          "Danach frühstückst du."
        ])
    precondition(phrases.append(snapshot: "Changed prefix").isEmpty)
    for (title, expected) in [
      ("Frühstück I", EventCategory.meal), ("Ärztliches Gespräch", .medical),
      ("Physiotherapie Tag 1", .therapy), ("Anmeldung", .organization), ("Irgendwas", .other),
      ("Frühstück und Therapie", .other),
    ] {
      precondition(EventCategory.classify(title) == expected, title)
    }
    print(
      "Conversation: silence, 1.2/2.5-second endpoints, short noise, stable sentence prefixes and conservative categories passed"
    )
  }
}
