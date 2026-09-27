import Foundation

/// A foreground conversation relies on the visible confirmation and word display.
/// Restore the pre-existing idle policy as soon as its active use ends.
struct ConversationWakeState {
  private var previous: Bool?
  mutating func update(active: Bool, current: Bool) -> Bool {
    if active {
      if previous == nil { previous = current }
      return true
    }
    defer { previous = nil }
    return previous ?? current
  }
}

struct HeardSpeech {
  private var order: [UUID] = []
  private var passages: [UUID: String] = [:]
  var text: String {
    order.compactMap { passages[$0] }.filter { !$0.isEmpty }.joined(separator: " ")
  }
  mutating func capture(playback: UUID, completedWords: String) {
    if passages[playback] == nil { order.append(playback) }
    passages[playback] = completedWords
  }
}

/// Pure endpoint policy, fed exactly one 20 ms VAD decision at a time.
struct SpeechEndpoint {
  private(set) var voicedFrames = 0
  private(set) var silenceFrames = 0
  init(confirmedPreRoll: Bool = false) {
    // Barge-in already required ten voiced frames. A short word may finish
    // entirely inside the pre-roll, before this endpoint starts receiving.
    voicedFrames = confirmedPreRoll ? 10 : 0
  }
  mutating func append(voice: Bool, transcript: String) -> Bool {
    if voice {
      voicedFrames += 1
      silenceFrames = 0
    } else {
      silenceFrames += 1
    }
    guard voicedFrames >= 5 else { return false }
    let last =
      transcript.lowercased().split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
    let incomplete = [
      "am", "um", "äh", "ähm", "und", "oder", "den", "die", "das", "im", "in", "auf", "mit", "zum",
      "von",
    ].contains(last)
    return silenceFrames >= (incomplete ? 125 : 60)
  }
}

enum SpeechPhrasing {
  static func isAbbreviation(_ word: String) -> Bool {
    let compact = word.lowercased().replacingOccurrences(of: ".", with: "")
    return [
      "dr", "prof", "min", "std", "ca", "bzw", "z", "b", "zb", "d", "h", "dh",
      "u", "a", "ua", "ev", "evtl", "tel",
    ].contains(compact)
  }
  static func phrases(_ text: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    for word in text.split(whereSeparator: \.isWhitespace) {
      if !current.isEmpty { current += " " }
      current += word
      let sentence =
        word.hasSuffix("!") || word.hasSuffix("?")
        || (word.hasSuffix(".") && word.dropLast().last?.isNumber == false
          && !isAbbreviation(String(word)))
      // Start with the first complete sentence, even when it is short. Split
      // long sentences at clause punctuation so Victoria can prepare the next
      // phrase during playback; never split a date, abbreviation or bare word.
      let clause = current.count >= 55 && [",", ";", ":"].contains(where: word.hasSuffix)
      if sentence || clause {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
