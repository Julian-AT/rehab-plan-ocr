import Foundation

/// Audio duration, not UI callback arrival time, determines the end of a turn.
struct SpeechEndpoint {
  private(set) var voicedDuration = 0.0
  private(set) var silenceDuration = 0.0
  var voicedFrames: Int { Int((voicedDuration / 0.02).rounded()) }
  init(confirmedPreRoll: Bool = false) { voicedDuration = confirmedPreRoll ? 0.2 : 0 }
  static func pause(for transcript: String) -> Double {
    let words = transcript.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    guard let last = words.last else { return 2.2 }
    let incomplete = [
      "am", "um", "äh", "ähm", "und", "oder", "den", "die", "das", "im", "in", "auf", "mit", "zum",
      "zur", "von", "vom", "für", "weil", "wenn", "dass", "ob", "ich", "möchte", "bitte", "also",
    ]
    return incomplete.contains(last) ? 2.2 : 1.0
  }
  mutating func append(voice: Bool, transcript: String, duration: Double = 0.02) -> Bool {
    guard duration.isFinite, duration > 0 else { return false }
    if voice {
      voicedDuration += duration
      silenceDuration = 0
    } else {
      silenceDuration += duration
    }
    // Three voiced frames retain short words. Untranscribed clicks never submit.
    guard voicedDuration >= 0.06 - 0.000001 else { return false }
    return silenceDuration >= Self.pause(for: transcript) - 0.000001
  }
}

struct AudioActivity: Sendable {
  let time: Double
  let speech: Bool
  let duration: Double
}
struct AudioActivityBatch: Sendable {
  let time: Double
  let level: Double
  let frames: [AudioActivity]
  let failure: String?
}

/// Wall time is used only to detect a stalled device, never as speech evidence.
struct AudioWatchdog {
  var lastBuffer: Double
  func stalled(at now: Double) -> Bool { now - lastBuffer > 1.5 }
}

/// Only stable, complete sentence prefixes enter synthesis. A trailing number
/// period (dates) or abbreviation never becomes an early phrase boundary.
struct StableSpeechPhrases {
  private(set) var emitted = ""
  private(set) var hasRevisionConflict = false
  mutating func append(snapshot: String, final: Bool = false) -> [String] {
    guard snapshot.hasPrefix(emitted) else {
      hasRevisionConflict = true
      return []
    }
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
        !["Dr", "Prof", "Min", "Std", "ca", "bzw", "z", "B"].contains(word)
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
      if current.count + word.count > 220 && !current.isEmpty {
        chunks.append(current)
        current = ""
      }
      if !current.isEmpty { current += " " }
      current += word
      if !current.isEmpty
        && (word.hasSuffix("!") || word.hasSuffix("?")
          || (word.hasSuffix(".") && word.dropLast().last?.isNumber == false
            && !["Dr.", "Prof.", "Min.", "Std.", "ca.", "bzw.", "z.", "B."].contains(String(word))))
      {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}

/// The model may adjust pauses, but cannot change even one word or embedded fact.
struct SpokenText: Sendable {
  let source: String
  let text: String
  let refined: Bool
  var phrases: [String] { SpeechPhrasing.phrases(text) }
  init(source: String, candidate: String? = nil) {
    self.source = source
    if let candidate, Self.tokens(source) == Self.tokens(candidate),
      !candidate.contains("\n#"), !candidate.contains("**"),
      source.filter({ "?!".contains($0) }) == candidate.filter({ "?!".contains($0) }),
      candidate.count <= source.count + 80,
      !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      refined = true
    } else {
      text = source.trimmingCharacters(in: .whitespacesAndNewlines)
      refined = false
    }
  }
  private static func tokens(_ text: String) -> [String] {
    // Internal punctuation binds dates, times, rooms, hyphenated names and decimals.
    let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:[.:,/’'−–-][\p{L}\p{N}]+)*"#)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range, in: text).map { String(text[$0]) }
    }
  }
}
