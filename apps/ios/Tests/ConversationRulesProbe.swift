import Foundation

@main struct ConversationRulesProbe {
  static func main() {
    var endpoint = SpeechEndpoint()
    for _ in 0..<300 { precondition(!endpoint.append(voice: false, transcript: "")) }
    endpoint = SpeechEndpoint(confirmedPreRoll: true)
    for _ in 0..<49 { precondition(!endpoint.append(voice: false, transcript: "Nein")) }
    precondition(endpoint.append(voice: false, transcript: "Nein"))
    endpoint = SpeechEndpoint()
    for _ in 0..<5 { precondition(!endpoint.append(voice: true, transcript: "Termine morgen")) }
    for _ in 0..<49 { precondition(!endpoint.append(voice: false, transcript: "Termine morgen")) }
    precondition(endpoint.append(voice: false, transcript: "Termine morgen"))
    endpoint = SpeechEndpoint()
    for _ in 0..<6 { _ = endpoint.append(voice: true, transcript: "Was habe ich am") }
    for _ in 0..<109 { precondition(!endpoint.append(voice: false, transcript: "Was habe ich am")) }
    precondition(endpoint.append(voice: false, transcript: "Was habe ich am"))
    endpoint = SpeechEndpoint()
    for _ in 0..<2 { _ = endpoint.append(voice: true, transcript: "") }
    for _ in 0..<300 { precondition(!endpoint.append(voice: false, transcript: "")) }
    endpoint = SpeechEndpoint()
    for _ in 0..<3 { _ = endpoint.append(voice: true, transcript: "Ja") }
    precondition(!endpoint.append(voice: false, transcript: "Ja", duration: 0.99))
    precondition(endpoint.append(voice: false, transcript: "Ja", duration: 0.01))
    // A thinking pause resumes without an early endpoint; callback batch size is irrelevant.
    endpoint = SpeechEndpoint()
    _ = endpoint.append(voice: true, transcript: "Ich möchte", duration: 0.2)
    precondition(!endpoint.append(voice: false, transcript: "Ich möchte", duration: 2.1))
    precondition(!endpoint.append(voice: true, transcript: "Ich möchte Termine", duration: 0.2))
    precondition(endpoint.append(voice: false, transcript: "Ich möchte Termine", duration: 1.0))
    precondition(AudioWatchdog(lastBuffer: 10).stalled(at: 11.6))
    precondition(!AudioWatchdog(lastBuffer: 10).stalled(at: 11.4))
    let source = "Frühstück II, am 14.09.2026 um 09:15, Raum 2.14, bei Dr. Muster in Laßnitzhöhe."
    precondition(
      SpokenText(source: source, candidate: source.replacingOccurrences(of: ", bei", with: ". bei"))
        .refined)
    for changed in [
      source.replacingOccurrences(of: "09:15", with: "09:50"),
      source.replacingOccurrences(of: "2.14", with: "2 14"),
      source.replacingOccurrences(of: "II", with: "I"),
      source.replacingOccurrences(of: "Dr.", with: "Dr"),
      source.replacingOccurrences(of: "Muster", with: "Mustermann"), "Bitte " + source,
    ] {
      precondition(SpokenText(source: source, candidate: changed).text == source)
      precondition(!SpokenText(source: source, candidate: changed).refined)
    }
    precondition(
      !SpokenText(
        source: "Am 14. September ist Therapie.",
        candidate: "Am 14 September ist Therapie."
      ).refined)
    for strength in stride(from: 0.1, through: 0.7, by: 0.01) {
      var colors = AppointmentColors()
      colors.strength = strength
      for color: UInt32 in [0, 0xFFFFFF, 0x009640, 0xFFFF00, 0xFF0000, 0x0000FF, 0x777777] {
        colors.colors[EventCategory.therapy.rawValue] = color
        for dark in [false, true] {
          let luminance = AppointmentColors.luminance(colors.surface(.therapy, dark: dark))
          let contrast =
            colors.usesWhiteText(.therapy, dark: dark)
            ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05
          precondition(contrast >= 4.5)
        }
      }
    }
    var colors = AppointmentColors()
    colors.strength = 0.66
    colors.colors["meal"] = 0xAA3322
    precondition(AppointmentColors(rawValue: colors.rawValue) == colors)
    precondition(AppointmentColors(rawValue: "invalid").strength == 0.35)
    colors.strength = 1
    precondition(AppointmentColors(rawValue: colors.rawValue).strength == 0.7)
    precondition(
      AppointmentColors(rawValue: "{\"version\":2,\"strength\":0.6,\"colors\":{}}").strength == 0.35
    )
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
      "Conversation: silence, 1.0/2.2-second endpoints, short noise, stable sentence prefixes and conservative categories passed"
    )
  }
}
