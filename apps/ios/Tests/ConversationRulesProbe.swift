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
    for text in ["Ja", "Was habe ich am"] {
      endpoint = SpeechEndpoint()
      for _ in 0..<3 { _ = endpoint.append(voice: true, transcript: text) }
      let frames = text == "Ja" ? 60 : 125
      for _ in 1..<frames { precondition(!endpoint.append(voice: false, transcript: text)) }
      precondition(endpoint.append(voice: false, transcript: text), "Quiet reply stayed open")
    }
    endpoint = SpeechEndpoint()
    for _ in 0..<3 { _ = endpoint.append(voice: true, transcript: "...") }
    for _ in 0..<300 { precondition(!endpoint.append(voice: false, transcript: "...")) }
    // Sparse false VAD hits alone cannot acquire a turn.
    endpoint = SpeechEndpoint()
    for frame in 0..<600 {
      precondition(!endpoint.append(voice: frame.isMultiple(of: 25), transcript: ""))
    }
    for (text, frames) in [("Wann ist mein Termin", 60), ("Verschiebe ihn um", 125)] {
      endpoint = SpeechEndpoint()
      for _ in 0..<50 { _ = endpoint.append(voice: true, transcript: text) }
      // Start noise after the onset window; each burst is only 20 or 40 ms.
      // If a tentative burst starts exactly at the deadline, wait for its
      // 40 ms to resolve. A real resumed word still gets a fresh full pause.
      let completionFrame = frames == 60 ? 62 : frames
      for frame in 1...completionFrame {
        let noisy = frame % 25 == 10 || frame % 25 == 11
        precondition(
          endpoint.append(voice: noisy, transcript: text) == (frame == completionFrame),
          "Short noise kept restarting the pause")
      }
    }
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
      "Conversation: silence, quiet replies, 1.2/2.5-second pauses, noisy pause boundaries, stable sentence prefixes and conservative categories passed"
    )
  }
}
