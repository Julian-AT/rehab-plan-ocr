import Foundation
import RehaCore

enum VoiceAddress: String, CaseIterable {
  case du = "Du"
  case sie = "Sie"
  static let key = "voice.address"
  static func saved(in defaults: UserDefaults = .standard) -> Self {
    Self(rawValue: defaults.string(forKey: key) ?? "") ?? .du
  }
  func choose(_ informal: String, _ formal: String) -> String {
    self == .du ? informal : formal
  }
  var instruction: String {
    choose(
      "Sprich die Person mit du an; verwende dir und dein.",
      "Sprich die Person mit Sie an; verwende Ihnen und Ihr.")
  }
  var confirmation: String {
    choose(
      "Bitte prüfe die Angaben und tippe zum Bestätigen auf die Schaltfläche.",
      "Bitte prüfen Sie die Angaben und tippen Sie zum Bestätigen auf die Schaltfläche.")
  }
}

/// Written information and its pronunciation travel together. Neither mutates
/// source events. Completed audio word marks alone populate the heard history.
struct ConversationReply: Equatable {
  struct Phrase: Equatable {
    let text: String
    let speech: String
  }
  private(set) var phrases: [Phrase] = []
  var text: String { phrases.map(\.text).joined(separator: " ") }
  var speech: String { phrases.map(\.speech).joined(separator: " ") }
  init(_ text: String = "") {
    for phrase in SpeechPhrasing.phrases(text) { append(phrase) }
  }
  mutating func appendPrepared(_ phrase: Phrase) { phrases.append(phrase) }
  mutating func append(_ text: String) {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    phrases.append(Phrase(text: clean, speech: normalizeSpeech(text: clean)))
  }
}
