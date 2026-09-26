import Foundation

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

/// Only stable, complete sentence prefixes enter synthesis. A trailing number
/// period (dates) or abbreviation never becomes an early phrase boundary.
struct StableSpeechPhrases {
  private(set) var emitted = ""
  mutating func append(snapshot: String, final: Bool = false) -> [String] {
    guard snapshot.hasPrefix(emitted) else { return [] }
    let rest = String(snapshot.dropFirst(emitted.count))
    if final {
      emitted = snapshot
      return rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? [] : SpeechPhrasing.phrases(rest)
    }
    let pattern = #"[.!?](?:\s+)(?=[A-ZÄÖÜ])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var boundary: String.Index?
    for match in regex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)) {
      guard let range = Range(match.range, in: rest) else { continue }
      let prefix = rest[..<range.lowerBound]
      let word = prefix.split(separator: " ").last.map(String.init) ?? ""
      guard prefix.last?.isNumber != true,
        ![
          "Dr", "Prof", "Min", "Std", "ca", "bzw", "z", "B", "d", "h", "u", "a", "ev", "evtl",
          "Tel",
        ].contains(word)
      else { continue }
      boundary = range.upperBound
    }
    guard let boundary else { return [] }
    let phrase = String(rest[..<boundary])
    emitted += phrase
    return SpeechPhrasing.phrases(phrase)
  }
}

enum SpeechPhrasing {
  static func phrases(_ text: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    for word in text.split(whereSeparator: \.isWhitespace) {
      if !current.isEmpty { current += " " }
      current += word
      if current.count > 40
        && (word.hasSuffix("!") || word.hasSuffix("?")
          || (word.hasSuffix(".") && word.dropLast().last?.isNumber == false
            && ![
              "Dr.", "Prof.", "Min.", "Std.", "ca.", "bzw.", "z.", "B.", "d.", "h.", "u.", "a.",
              "ev.", "evtl.", "Tel.",
            ].contains(String(word))))
      {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
