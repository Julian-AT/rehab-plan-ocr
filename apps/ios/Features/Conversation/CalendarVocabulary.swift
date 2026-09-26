import Foundation

enum CalendarVocabulary {
  /// Bounded phrases from existing records, never synthesized names or numbers.
  static func phrases(titles: [String]) -> [String] {
    let general = [
      "nächster Termin", "Termine morgen", "übermorgen", "Therapie", "Physiotherapie",
      "Ergotherapie", "Atemgymnastik", "Funktionstraining", "Wartezone", "Therapeut",
      "Termin verschieben", "Termin hinzufügen", "Termin löschen", "wiederholen",
    ]
    var seen = Set<String>()
    return Array(
      (general + titles).compactMap { value -> String? in
        let phrase = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, phrase.count <= 80,
          phrase.split(whereSeparator: \.isWhitespace).count <= 8,
          seen.insert(phrase.lowercased()).inserted
        else { return nil }
        return phrase
      }.prefix(32))
  }
}
