import Foundation

/// Patterns are shared across voice turns. The lock protects only the bounded
/// cache; matching happens outside it on immutable regular expressions.
private final class VoiceRegexCache: @unchecked Sendable {
  private let lock = NSLock()
  private var expressions: [String: NSRegularExpression] = [:]

  func expression(_ pattern: String) -> NSRegularExpression? {
    lock.lock()
    let cached = expressions[pattern]
    lock.unlock()
    if let cached { return cached }
    guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
    lock.lock()
    defer { lock.unlock() }
    if let cached = expressions[pattern] { return cached }
    // Retain the frequent rules without unbounded growth from future callers.
    if expressions.count < 128 { expressions[pattern] = compiled }
    return compiled
  }
}

/// Only the current turn is held in memory. Reference time and requested new time
/// are deliberately separate; a model suggestion never becomes a calendar ID.
struct VoiceIntent: Equatable {
  var negatedChange = false
  enum Origin: String { case spoken, corrected, context, choice }
  var origins: [String: Origin] = [:]
  enum Action: String { case next, list, create, update, remove, cancel, unsupported }
  var action: Action = .unsupported
  var referenceText = ""
  var calendarName: String?
  var referenceTime: Int?
  var date: Date?
  var newDate: Date?
  var newTime: Int?
  var duration: Int?
  var title: String?
  var corrected = false
}
enum VoiceRules {
  private static let expressions = VoiceRegexCache()
  private static let timeWords = [
    "ein": 1, "eins": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
    "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13,
    "vierzehn": 14, "fünfzehn": 15, "sechzehn": 16, "siebzehn": 17, "achtzehn": 18,
    "neunzehn": 19, "zwanzig": 20, "einundzwanzig": 21, "zweiundzwanzig": 22,
    "dreiundzwanzig": 23, "dreissig": 30, "vierzig": 40, "fünfundvierzig": 45, "fünfzig": 50,
  ]
  private static let durationWords = [
    "fünf": 5, "zehn": 10, "fünfzehn": 15, "zwanzig": 20, "dreissig": 30, "fünfundvierzig": 45,
    "sechzig": 60, "neunzig": 90,
  ]
  private static let timePattern = "\\b(?:\(timeWords.keys.sorted().joined(separator: "|")))\\b"
  private static let durationPattern =
    "\\b(?:\(durationWords.keys.sorted().joined(separator: "|")))\\b"

  private static func replacing(_ pattern: String, in text: String, with template: String)
    -> String
  {
    guard let regex = expressions.expression(pattern) else { return text }
    return regex.stringByReplacingMatches(
      in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
  }

  private static func replacingNumbers(_ text: String, words: [String: Int], pattern: String)
    -> String
  {
    guard let regex = expressions.expression(pattern) else { return text }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard !matches.isEmpty else { return text }
    let original = text as NSString
    let result = NSMutableString(string: text)
    // Original UTF-16 ranges stay valid when replacements proceed from the end.
    for match in matches.reversed() {
      if let value = words[original.substring(with: match.range)] {
        result.replaceCharacters(in: match.range, with: String(value))
      }
    }
    return result as String
  }

  static func normalized(_ text: String) -> String {
    let lower = text.lowercased().replacingOccurrences(of: "ß", with: "ss")
    let punctuation = replacing("[,!?]", in: lower, with: " ")
    return replacing("\\s+", in: punctuation, with: " ").trimmingCharacters(
      in: .whitespacesAndNewlines)
  }
  static func matches(_ pattern: String, _ text: String) -> [[String]] {
    guard let regex = expressions.expression(pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
      (0..<match.numberOfRanges).map {
        let r = match.range(at: $0)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
      }
    }
  }
  private static let datePattern =
    #"\b(?:übermorgen|morgen|heute|sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|\d{1,2}[./]\d{1,2}[./]\d*)\b|\b\d{1,2}[./]\d{1,2}[./](?!\d)"#

  private static func dateContext(_ input: String) -> String {
    let text = normalized(input)
    if let correction = matches(#"\b(?:nein|sondern|ich meine)\s+(.+)$"#, text).last,
      !matches(datePattern, correction[1]).isEmpty
    {
      return correction[1]
    }
    return text
  }

  static func hasInvalidDate(_ text: String, now: Date = .now, calendar: Calendar = .current)
    -> Bool
  {
    matches(#"\b\d{1,2}[./]\d{1,2}[./]\d*"#, dateContext(text)).contains {
      date($0[0], now: now, calendar: calendar) == nil
    }
  }

  static func date(_ text: String, now: Date, calendar: Calendar) -> Date? {
    let context = dateContext(text)
    guard let token = matches(datePattern, context).last?.first else { return nil }
    let today = calendar.startOfDay(for: now)
    if let offset = ["heute": 0, "morgen": 1, "übermorgen": 2][token] {
      return calendar.date(byAdding: .day, value: offset, to: today)
    }
    if let value = matches(#"^(\d{1,2})[./](\d{1,2})[./](\d{4})?$"#, token).first,
      let day = Int(value[1]), let month = Int(value[2])
    {
      let year = Int(value[3]) ?? calendar.component(.year, from: now)
      guard (1...9999).contains(year),
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
        calendar.component(.day, from: date) == day,
        calendar.component(.month, from: date) == month,
        calendar.component(.year, from: date) == year
      else { return nil }
      return date
    }
    let days = [
      "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6,
      "samstag": 7,
    ]
    if let day = days[token] {
      var offset = (day - calendar.component(.weekday, from: today) + 7) % 7
      if context.contains("nächsten") && offset == 0 { offset = 7 }
      return calendar.date(byAdding: .day, value: offset, to: today)
    }
    return nil
  }
  static func time(_ text: String) -> Int? {
    var text = normalized(text)
    if let correction = text.range(of: " nein ", options: .backwards) {
      text = String(text[correction.upperBound...])
    }
    text = replacingNumbers(text, words: timeWords, pattern: timePattern)
    var minutes: Int?
    if let m = matches("\\b(dreiviertel|halb|viertel) (\\d{1,2})\\b", text).last,
      let hour = Int(m[2]), (1...24).contains(hour)
    {
      minutes = (hour - 1) * 60 + (m[1] == "halb" ? 30 : m[1] == "dreiviertel" ? 45 : 15)
    } else if let m = matches("\\b(\\d{1,2}):(\\d{2})\\b", text).last, let h = Int(m[1]),
      let min = Int(m[2]), h < 24, min < 60
    {
      minutes = h * 60 + min
    } else if let m = matches("(?:\\bum |\\bauf |^)(\\d{1,2})(?: uhr(?: (\\d{1,2}))?\\b|$)", text)
      .last, let h = Int(m[1]), h < 24, (Int(m[2]) ?? 0) < 60
    {
      minutes = h * 60 + (Int(m[2]) ?? 0)
    }
    if let value = minutes, value < 12 * 60, text.contains("nachmittag") || text.contains("abends")
    {
      minutes = value + 12 * 60
    }
    return minutes
  }
  static func duration(_ text: String) -> Int? {
    let input = replacingNumbers(normalized(text), words: durationWords, pattern: durationPattern)
    if let match = matches("\\b(\\d{1,3}) minuten\\b", input).last, let value = Int(match[1]),
      value > 0
    {
      return value
    }
    return nil
  }
  static func referenceWords(_ input: String) -> [String] {
    let clean = replacing(
      "(?:im|in|aus|vom) kalender .+?(?= am | um | heute| morgen|$)", in: normalized(input),
      with: "")
    let ignored = Set(
      "verschiebe verschieben ändere ändern lösche löschen entferne entfernen den der die das dem meinen mein meine meiner mir bitte termin termine behandlung um am auf von nach vor bis uhr heute morgen übermorgen nächste nächsten nächster ist wann zeige finde habe ich mich dienstag montag mittwoch donnerstag freitag samstag sonntag halb viertel dreiviertel nein keine keinen kein nicht neun zehn eins ein zwei drei vier fünf sechs sieben acht elf zwölf"
        .split(separator: " ").map(String.init))
    return matches("[a-zäöü]+", clean).map { $0[0] }.filter { !ignored.contains($0) }
  }
  static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> VoiceIntent
  {
    let text = normalized(input)
    var result = VoiceIntent()
    result.corrected = text.contains("nein")
    if let named = matches(
      "(?:im|in|aus|vom) kalender (.+?)(?: am | um | auf | heute| morgen|$)", text
    ).last {
      result.calendarName = named[1]
    }
    if !matches("\\b(medikamente|medikament|dosis|diagnose|schmerzen)\\b", text).isEmpty {
      return result
    }
    if ["stopp", "abbrechen", "gespräch beenden", "gesprach beenden", "gespräch abbrechen"]
      .contains(text.trimmingCharacters(in: .punctuationCharacters))
    {
      result.action = .cancel
      return result
    }
    if matches("\\b(nicht|keine|keinen|kein)\\b", text).count > 0
      && ["lösch", "entfern", "verschieb", "änder", "erstell", "eintragen"].contains(
        where: text.contains)
    {
      result.negatedChange = true
      return result
    }

    if text.contains("lösch") || text.contains("entfern") {
      result.action = .remove
    } else if text.contains("verschieb") || text.contains("änder") {
      result.action = .update
    } else if text.contains("erstell") || text.contains("eintragen")
      || text.contains("neuen termin") || text.contains("neuer termin")
      || text.contains("hinzufügen")
    {
      result.action = .create
    } else if text.contains("nächst") && (text.contains("termin") || text.contains("wann")) {
      result.action = .next
    } else if text.contains("termin") || text.contains("wann") || text.contains("vorlesen") {
      result.action = .list
    }
    if result.action == .update, let split = text.range(of: " auf ") {
      result.referenceText = String(text[..<split.lowerBound])
      let target = String(text[split.upperBound...])
      result.referenceTime = time(result.referenceText)
      result.date = date(result.referenceText, now: now, calendar: calendar)
      result.newDate = date(target, now: now, calendar: calendar)
      result.newTime = time(target)
    } else {
      result.referenceText = text
      result.date = date(text, now: now, calendar: calendar)
      if result.action == .create {
        result.newDate = result.date
        result.newTime = time(text)
      } else {
        result.referenceTime = time(text)
      }
    }
    result.duration = duration(text)
    if result.date != nil {
      result.origins["reference_date"] = result.corrected ? .corrected : .spoken
    }
    if result.referenceTime != nil { result.origins["reference_time"] = .spoken }
    if result.newDate != nil {
      result.origins["new_date"] = result.corrected ? .corrected : .spoken
    }
    if result.newTime != nil {
      result.origins["new_time"] = result.corrected ? .corrected : .spoken
    }
    if result.duration != nil { result.origins["duration"] = .spoken }
    return result
  }
}
