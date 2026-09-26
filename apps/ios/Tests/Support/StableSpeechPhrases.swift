import Foundation

/// Feeds incremental snapshots to phrase/normalization regression probes.
/// App replies are prepared as complete text and do not use this helper.
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
      guard prefix.last?.isNumber != true, !SpeechPhrasing.isAbbreviation(word) else { continue }
      boundary = range.upperBound
    }
    guard let boundary else { return [] }
    let phrase = String(rest[..<boundary])
    emitted += phrase
    return SpeechPhrasing.phrases(phrase)
  }
}
