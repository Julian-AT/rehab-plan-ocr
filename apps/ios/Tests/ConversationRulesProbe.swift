import Foundation

@main struct ConversationRulesProbe {
  static func main() {
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
