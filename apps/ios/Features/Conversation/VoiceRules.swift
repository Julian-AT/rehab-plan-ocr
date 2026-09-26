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
struct VoiceIntent: Equatable, Sendable {
  var negatedChange = false
  enum Origin: String, Sendable { case spoken, corrected, context, choice }
  var origins: [String: Origin] = [:]
  enum Action: String, Sendable { case next, list, create, update, remove, cancel, unsupported }
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
  var timezone = TimeZone.current.identifier
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    return calendar
  }
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
  private static let months = [
    "januar": 1, "jänner": 1, "februar": 2, "märz": 3, "april": 4, "mai": 5, "juni": 6,
    "juli": 7, "august": 8, "september": 9, "oktober": 10, "november": 11, "dezember": 12,
  ]
  private static let ordinalStems = [
    "erst", "zweit", "dritt", "viert", "fünft", "sechst", "siebt", "acht", "neunt", "zehnt",
    "elft", "zwölft", "dreizehnt", "vierzehnt", "fünfzehnt", "sechzehnt", "siebzehnt",
    "achtzehnt", "neunzehnt", "zwanzigst", "einundzwanzigst", "zweiundzwanzigst",
    "dreiundzwanzigst", "vierundzwanzigst", "fünfundzwanzigst", "sechsundzwanzigst",
    "siebenundzwanzigst", "achtundzwanzigst", "neunundzwanzigst", "dreissigst", "einunddreissigst",
  ]
  private static let monthPattern = "(?:\(months.keys.sorted().joined(separator: "|")))"
  private static let ordinalPattern = "(?:\(ordinalStems.joined(separator: "|")))e[nrms]?"
  /// Shared with complete-match calendar questions, including malformed years so
  /// they can be rejected rather than silently treated as an undated question.
  static let civilDatePattern =
    "(?:\\d{4,}-\\d{1,2}-\\d{1,2}|\\d{1,2}[./]\\d{1,2}[./]\\d*|(?:\\d{1,2}\\.?|\(ordinalPattern))\\s+\(monthPattern)(?:\\s+\\d+)?)"
  private static let datePattern =
    "\\b(?:übermorgen|morgen|heute|sonntag|montag|dienstag|mittwoch|donnerstag|freitag|samstag|\(civilDatePattern))(?![\\p{L}\\d])"
  private static let correctionPattern = #"\b(?:nein|sondern|ich meine)\b"#

  private static func correctedContext(_ text: String, containing pattern: String) -> String {
    guard let regex = expressions.expression(correctionPattern) else { return text }
    let ns = text as NSString
    // Inspect the latest correction first, including when several repairs occur.
    for marker in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
    {
      let tail = ns.substring(from: NSMaxRange(marker.range)).trimmingCharacters(in: .whitespaces)
      if !matches(pattern, tail).isEmpty { return tail }
    }
    return text
  }

  private static func rejectedField(_ text: String, pattern: String) -> Bool {
    // Negation must apply to this field. “Habe ich keine Termine morgen?” still
    // asks about tomorrow; “nicht morgen” does not supply a replacement date.
    !matches(
      "\\b(?:nicht|kein|keine|keinen|keinem)\\s+(?:(?:am|um|auf|für|den|dem)\\s+)?(?:\(pattern))",
      text
    ).isEmpty
      || !matches("(?:\(pattern))\\s+(?:(?:doch|lieber)\\s+)?nicht\\b", text).isEmpty
      || !matches(#"\bnein\s*$"#, text).isEmpty
  }

  private static func dateContext(_ input: String) -> String {
    correctedContext(normalized(input), containing: datePattern)
  }

  static func hasInvalidDate(_ text: String, now: Date = .now, calendar: Calendar = .current)
    -> Bool
  {
    matches("\\b\(civilDatePattern)(?![\\p{L}\\d])", dateContext(text)).contains {
      date($0[0], now: now, calendar: calendar) == nil
    }
  }

  static func date(_ text: String, now: Date, calendar: Calendar) -> Date? {
    let context = dateContext(text)
    guard !rejectedField(context, pattern: datePattern),
      let token = matches(datePattern, context).last?.first
    else { return nil }
    let today = calendar.startOfDay(for: now)
    if let offset = ["heute": 0, "morgen": 1, "übermorgen": 2][token] {
      return calendar.date(byAdding: .day, value: offset, to: today)
    }
    func civilDate(day: Int, month: Int, yearText: String) -> Date? {
      guard yearText.isEmpty || yearText.count == 4 else { return nil }
      let year = Int(yearText) ?? calendar.component(.year, from: now)
      guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
        calendar.component(.day, from: date) == day,
        calendar.component(.month, from: date) == month,
        calendar.component(.year, from: date) == year
      else { return nil }
      return date
    }
    if let value = matches(#"^(\d{4,})-(\d{1,2})-(\d{1,2})$"#, token).first,
      let day = Int(value[3]), let month = Int(value[2])
    {
      return civilDate(day: day, month: month, yearText: value[1])
    }
    if let value = matches(#"^(\d{1,2})[./](\d{1,2})[./](\d*)$"#, token).first,
      let day = Int(value[1]), let month = Int(value[2])
    {
      return civilDate(day: day, month: month, yearText: value[3])
    }
    if let value = matches(
      "^(\\d{1,2})\\.?\\s+(\(monthPattern))(?:\\s+(\\d+))?$", token
    ).first, let day = Int(value[1]), let month = months[value[2]] {
      return civilDate(day: day, month: month, yearText: value[3])
    }
    if let value = matches(
      "^(\(ordinalStems.joined(separator: "|")))e[nrms]?\\s+(\(monthPattern))(?:\\s+(\\d+))?$",
      token
    ).first, let index = ordinalStems.firstIndex(of: value[1]), let month = months[value[2]] {
      return civilDate(day: index + 1, month: month, yearText: value[3])
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
  static func time(_ input: String) -> Int? {
    let clockPattern =
      #"\b(dreiviertel|halb|viertel) (\d{1,2})\b|\b(\d{1,2}):(\d+)\b|(?:\bum |\bauf |^)(\d{1,2})(?: uhr(?: (\d{1,2}))?\b|$)"#
    let numeric = replacingNumbers(normalized(input), words: timeWords, pattern: timePattern)
    let text = correctedContext(numeric, containing: clockPattern)
    guard !rejectedField(text, pattern: clockPattern),
      let m = matches(clockPattern, text).last
    else { return nil }
    var minutes: Int
    if let hour = Int(m[2]), (1...24).contains(hour) {
      minutes = (hour - 1) * 60 + (m[1] == "halb" ? 30 : m[1] == "dreiviertel" ? 45 : 15)
    } else if let hour = Int(m[3]), let minute = Int(m[4]),
      m[4].count == 2, hour < 24, minute < 60
    {
      minutes = hour * 60 + minute
    } else if let hour = Int(m[5]), hour < 24, (Int(m[6]) ?? 0) < 60 {
      minutes = hour * 60 + (Int(m[6]) ?? 0)
    } else {
      return nil
    }
    if minutes < 12 * 60, text.contains("nachmittag") || text.contains("abends") {
      minutes += 12 * 60
    }
    return minutes
  }
  static func duration(_ text: String) -> Int? {
    let pattern = #"\b(\d{1,3}) minuten\b"#
    let numeric = replacingNumbers(normalized(text), words: durationWords, pattern: durationPattern)
    let input = correctedContext(numeric, containing: pattern)
    guard !rejectedField(input, pattern: pattern),
      let match = matches(pattern, input).last, let value = Int(match[1]), value > 0
    else { return nil }
    return value
  }
  static func referenceWords(_ input: String) -> [String] {
    let calendarFree = replacing(
      "(?:im|in|aus|vom) kalender .+?(?= am | um | heute| morgen|$)", in: normalized(input),
      with: "")
    let clean = replacing(datePattern, in: calendarFree, with: "")
    let ignored = Set(
      "verschiebe verschieben ändere ändern lösche löschen entferne entfernen den der die das dem meinen mein meine meiner mir bitte termin termine behandlung um am auf von nach vor bis uhr heute morgen übermorgen nächste nächsten nächster ist wann zeige finde habe ich mich dienstag montag mittwoch donnerstag freitag samstag sonntag halb viertel dreiviertel nein keine keinen kein nicht neun zehn eins ein zwei drei vier fünf sechs sieben acht elf zwölf"
        .split(separator: " ").map(String.init))
    return matches("[a-zäöü]+", clean).map { $0[0] }.filter { !ignored.contains($0) }
  }
  enum EventPosition: Equatable {
    case absent
    case ordinal(Int)
    case ambiguous
  }
  private static let eventOrdinalStems = ["erst", "zweit", "dritt", "viert", "fünft"]
  private static let eventOrdinalWord = "(?:\(eventOrdinalStems.joined(separator: "|")))e[nrms]?"
  private static let eventMentionPattern =
    "(?:\\b(?:den|dem|der|die|das|des|beim) \(eventOrdinalWord)\\b|\\b\(eventOrdinalWord) (?:termin|behandlung)\\b|^\(eventOrdinalWord)[.]?$)"
  private static let eventPositionPattern =
    "(?:\\b(?:den|dem|der|die|das|des|beim) \(eventOrdinalWord)(?=\\s*(?:$|[.]|(?:termin|behandlung|um|am|heute|morgen|übermorgen)\\b))|\\b\(eventOrdinalWord) (?:termin|behandlung)\\b|^\(eventOrdinalWord)[.]?$)"

  /// Positions refer to a displayed/spoken page, never to a fresh unlabelled
  /// calendar search. Calendar dates such as “am ersten Mai” are not positions.
  static func eventPosition(_ input: String) -> EventPosition {
    let withoutDates = replacing(datePattern, in: normalized(input), with: "")
    let text = correctedContext(withoutDates, containing: eventMentionPattern)
    if !matches(
      #"\b(?:den|dem|der|die|das|des) (?:ander\w*|irgendein\w*) (?:termin|behandlung)\b"#, text
    ).isEmpty {
      return .ambiguous
    }
    let mentions = matches(eventMentionPattern, text)
    let references = matches(eventPositionPattern, text).map { $0[0] }
    guard !references.isEmpty else {
      return matches(eventMentionPattern, text).isEmpty ? .absent : .ambiguous
    }
    guard references.count == mentions.count else { return .ambiguous }
    guard matches(#"\b(?:nicht|kein\w*|ander\w*|irgendein\w*)\b"#, text).isEmpty else {
      return .ambiguous
    }
    let positions = eventOrdinalStems.enumerated().compactMap { index, stem in
      references.contains { !matches("\\b\(stem)e[nrms]?\\b", $0).isEmpty } ? index + 1 : nil
    }
    return positions.count == 1 ? .ordinal(positions[0]) : .ambiguous
  }

  static func eventTargetWords(_ input: String) -> [String] {
    referenceWords(input).filter {
      matches("^\(eventOrdinalWord)$", $0).isEmpty
        && !["verschieb", "änder", "lösch", "entfern"].contains($0)
    }
  }

  static func selectionIndex(_ input: String, titles: [String]) -> Int? {
    let names = titles.map(normalized)
    let namesPattern = names.filter { !$0.isEmpty }.map(NSRegularExpression.escapedPattern).joined(
      separator: "|")
    let text = correctedContext(
      normalized(input),
      containing: eventPositionPattern + (namesPattern.isEmpty ? "" : "|(?:\(namesPattern))"))
    // A position-only reply must not silently discard an additional time/date.
    guard matches(datePattern, text).isEmpty,
      matches(#"\buhr\b|\d{1,2}:\d{2}"#, text).isEmpty, time(text) == nil
    else { return nil }
    guard matches(#"\b(?:nicht|kein\w*|ander\w*|irgendein\w*)\b"#, text).isEmpty else { return nil }
    switch eventPosition(text) {
    case .ordinal(let position):
      let index = position - 1
      guard names.indices.contains(index),
        eventTargetWords(text).allSatisfy({ names[index].contains($0) })
      else { return nil }
      return index
    case .ambiguous: return nil
    case .absent:
      let named = names.indices.filter { index in
        !names[index].isEmpty
          && !matches(
            "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: names[index])
              + "(?![\\p{L}\\p{N}])", text
          ).isEmpty
      }
      return named.count == 1 ? named[0] : nil
    }
  }
  /// A complete, deliberately narrow exception to the general negation guard:
  /// keep one discussed event, changing only its explicitly named title.
  /// Multiword titles need quotes so a trailing instruction cannot become a title.
  static func titleOnlyRename(_ input: String) -> String? {
    let text = replacing("\\s+", in: input, with: " ").trimmingCharacters(
      in: .whitespacesAndNewlines)
    let keep =
      #"(?:bitte )?(?:nicht (?:löschen|entfernen)|(?:diesen|den) termin (?:bitte )?nicht (?:löschen|entfernen)|(?:lösche|entferne|löschen sie|entfernen sie) (?:diesen|den) termin (?:bitte )?nicht)"#
    let separator = #"(?:[.,;] ?(?:sondern )?| (?:sondern )?)"#
    let only = #"(?:nur|ausschlie(?:ss|ß)lich)"#
    let title = #"(?:"([^"]+)"|„([^“]+)“|([\p{L}][\p{L}\p{M}-]*))"#
    let commands = [
      #"(?:ändere|ändern sie) (?:bitte )?"# + only
        + #" (?:den namen|den titel|die bezeichnung) (?:dieses|des) termins (?:in|auf) "# + title,
      #"(?:gib|geben sie) (?:diesem|dem) termin (?:bitte )?"# + only
        + #" (?:den namen|den titel|die bezeichnung) "# + title,
      #"(?:benenne|benennen sie) (?:diesen|den) termin (?:bitte )?"# + only
        + #" in "# + title + #" um"#,
    ]
    for command in commands {
      guard
        let match = matches("(?i)^" + keep + separator + "(?:bitte )?" + command + "[.!]?$", text)
          .first,
        let value = match.dropFirst().first(where: { !$0.isEmpty })
      else { continue }
      let words = normalized(value)
      guard value.count <= 160, value.split(separator: " ").count <= 8,
        !matches(#"^[\p{L}\p{M}]+(?:[ -][\p{L}\p{M}]+)*$"#, value).isEmpty,
        matches(
          #"\b(?:nicht|nein|kein\w*|doch|oder|sondern|statt\w*|auch|zusätzlich|danach|dann|stopp?|abbrechen|beenden|verwerfen|vergiss|irgend\w*|ander\w*|etwas|beliebig\w*|so|neu|titel|name|namen|bezeichnung|termin\w*|behandlung\w*|heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|um|am|auf|uhr|minut\w*|lösch\w*|entfern\w*|änder\w*|verschieb\w*|erstell\w*|eintrag\w*|hinzufüg\w*|absag\w*|streich\w*|kürz\w*|verlänger\w*)\b"#,
          words
        ).isEmpty
      else { return nil }
      return value
    }
    return nil
  }

  static func explicitMutation(_ input: String) -> VoiceIntent.Action? {
    if titleOnlyRename(input) != nil { return .update }
    let text = normalized(input)
    let patterns: [(VoiceIntent.Action, String)] = [
      (.remove, #"\b(?:lösch(?:e|en)?|entfern(?:e|en)?)\b"#),
      (.update, #"\b(?:verschieb(?:e|en)?|änder(?:e|n)?)\b"#),
      (.create, #"\b(?:erstell(?:e|en)?|eintragen|hinzufügen)\b"#),
    ]
    let actions = patterns.filter { !matches($0.1, text).isEmpty }.map(\.0)
    // A compound request cannot silently become just its first mutation.
    return actions.count > 1 ? .unsupported : actions.first
  }

  /// Complete local commands, separate from `parse`'s partial field evidence.
  /// Every word must belong to the command, one target, or a supported field.
  /// Free phrasing and extra qualifiers remain the interpretation provider's job.
  static func completeMutation(
    _ input: String, now: Date = .now, calendar: Calendar = .current
  ) -> VoiceIntent? {
    var intent = parse(input, now: now, calendar: calendar)
    guard [.create, .update, .remove].contains(intent.action), !intent.negatedChange,
      !intent.corrected, !hasInvalidDate(input, now: now, calendar: calendar)
    else { return nil }
    let text = replacing("\\s+", in: input, with: " ").trimmingCharacters(
      in: .whitespacesAndNewlines)
    var remainder = replacing("[.!]$", in: text, with: "")
    func take(_ pattern: String) -> [String]? {
      guard let match = matches("(?i)^(?:" + pattern + ")(?= |$)", remainder).first else {
        return nil
      }
      remainder = String(remainder.dropFirst(match[0].count)).trimmingCharacters(in: .whitespaces)
      return match
    }
    _ = take("bitte")
    if intent.action == .create {
      guard
        take(
          #"erstell(?:e|en sie)? (?:einen )?(?:neuen )?termin|(?:einen )?neuen termin (?:erstellen|eintragen|hinzufügen)|neuer termin"#
        ) != nil
      else {
        return nil
      }
      if let title = take(
        #"(?:namens|mit (?:dem )?titel) (?:"([^"]+)"|„([^“]+)“|([\p{L}\p{M}-]+(?: [\p{L}\p{M}-]+)*?))(?= (?:am|um|für|heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b|$)"#
      )?.dropFirst().first(where: { !$0.isEmpty }) {
        guard completeMutationTitle(title) else { return nil }
        intent.title = title
        intent.origins["title"] = .spoken
      }
      guard completeMutationFields(remainder, now: now, calendar: calendar),
        intent.newDate == date(remainder, now: now, calendar: calendar),
        intent.newTime == time(remainder), intent.duration == duration(remainder)
      else { return nil }
      return intent
    }
    guard
      take(
        intent.action == .remove
          ? #"lösch(?:e|en sie)?|entfern(?:e|en sie)?"#
          : #"verschieb(?:e|en sie)?|änder(?:e|n sie)?"#) != nil
    else {
      return nil
    }
    let pieces = remainder.components(separatedBy: " auf ")
    guard pieces.count <= 2, intent.action == .update || pieces.count == 1 else { return nil }
    let reference = pieces[0]
    // Generic singular targets enter visible candidate selection. Ordinals keep
    // the discussed page; a named target must contain only a literal title.
    remainder = reference
    if take("(?:den |die |meinen |meine )?\(eventOrdinalWord) (?:termin|behandlung)") == nil,
      take(#"(?:den |meinen )?termin"#) == nil
    {
      _ = take(#"den|die|meinen|meine"#)
      guard
        let title = take(
          #"([\p{L}\p{M}-]+(?: [\p{L}\p{M}-]+)*?)(?= (?:am|um|heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b|$)"#
        )?[1], completeMutationTitle(title),
        referenceWords(title)
          == normalized(title).split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
      else { return nil }
    }
    guard completeMutationFields(remainder, now: now, calendar: calendar, allowsDuration: false)
    else { return nil }
    if pieces.count == 2 {
      var target = pieces[1]
      if date(target, now: now, calendar: calendar) == nil,
        !normalized(target).hasPrefix("um ")
      {
        target = "um " + target
      }
      guard !pieces[1].isEmpty,
        completeMutationFields(target, now: now, calendar: calendar),
        intent.newDate != nil || intent.newTime != nil
      else { return nil }
    }
    intent.referenceText = normalized(reference)
    return intent
  }

  private static func completeMutationTitle(_ title: String) -> Bool {
    title.count <= 160 && title.split(separator: " ").count <= 8
      && !matches(#"^[\p{L}\p{M}]+(?:[ -][\p{L}\p{M}]+)*$"#, title).isEmpty
      && matches(
        #"\b(?:nicht|nein|kein\w*|doch|oder|und|sondern|statt\w*|auch|nur|zusätzlich|danach|dann|stopp?|abbrechen|beenden|verwerfen|vergiss|irgend\w*|ander\w*|alle\w*|beide\w*|etwas|bitte|beliebig\w*|so|neu|titel|name|namen|bezeichnung|termin\w*|behandlung\w*|heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|um|am|auf|im|in|aus|vom|für|mit|ohne|uhr|minut\w*|kalender|raum|lösch\w*|entfern\w*|änder\w*|verschieb\w*|erstell\w*|eintrag\w*|hinzufüg\w*|absag\w*|streich\w*|kürz\w*|verlänger\w*)\b"#,
        normalized(title)
      ).isEmpty
  }

  private static func completeMutationFields(
    _ input: String, now: Date, calendar: Calendar, allowsDuration: Bool = true
  ) -> Bool {
    let number = "(?:\\d{1,2}|\(timeWords.keys.sorted().joined(separator: "|")))"
    let clock =
      "(?:\\d{1,2}:\\d{2}|\(number)(?: uhr(?: \(number))?)?|(?:halb|viertel|dreiviertel) \(number))(?: (?:nachmittags|abends))?"
    let day =
      "(?:heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|\(civilDatePattern))"
    let length = "(?:\\d{1,3}|\(durationWords.keys.sorted().joined(separator: "|")))"
    guard
      let fields = matches(
        "^(?: (?:am )?(\(day)))?(?: um (\(clock)))?(?: (?:für )?(\(length)) minuten)?$",
        input.isEmpty ? "" : " " + normalized(input)
      ).first
    else { return false }
    return (fields[1].isEmpty || date(fields[1], now: now, calendar: calendar) != nil)
      && (fields[2].isEmpty || time(fields[2]) != nil)
      && (fields[3].isEmpty || (allowsDuration && duration(fields[3] + " minuten") != nil))
  }

  /// Partial action/field evidence for safety checks and targeted slot entry.
  /// Recognizing a verb here does not mean the whole request was understood.
  static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> VoiceIntent
  {
    let text = normalized(input)
    var result = VoiceIntent()
    result.timezone = calendar.timeZone.identifier
    result.corrected = !matches(correctionPattern, text).isEmpty
    if let named = matches(
      "(?:im|in|aus|vom) kalender (.+?)(?: am | um | auf | heute| morgen|$)", text
    ).last {
      result.calendarName = named[1]
    }
    if !matches("\\b(medikamente|medikament|dosis|diagnose|schmerzen)\\b", text).isEmpty {
      return result
    }
    if text.hasPrefix("stopp ")
      || ["stopp", "abbrechen", "gespräch beenden", "gesprach beenden", "gespräch abbrechen"]
        .contains(text.trimmingCharacters(in: .punctuationCharacters))
    {
      result.action = .cancel
      return result
    }
    if let title = titleOnlyRename(input) {
      result.action = .update
      result.referenceText = "diesen termin"
      result.title = title
      result.origins["title"] = .spoken
      return result
    }
    if matches("\\b(nicht|keine|keinen|kein)\\b", text).count > 0
      && ["lösch", "entfern", "verschieb", "änder", "erstell", "eintragen"].contains(
        where: text.contains)
    {
      result.negatedChange = true
      return result
    }

    if let mutation = explicitMutation(text) {
      result.action = mutation
    } else if text.contains("neuen termin") || text.contains("neuer termin") {
      result.action = .create
    } else if text.contains("nächst") && (text.contains("termin") || text.contains("wann")) {
      result.action = .next
    } else if text.contains("termin") || text.contains("wann") || text.contains("vorlesen") {
      result.action = .list
    }
    if [.create, .update, .remove].contains(result.action),
      !matches(
        #"^(?:wie|wo|warum|weshalb|wieso|wann|wer|welche\w*|was|ist|sind|kann ich|könnte ich|darf ich)\b|\b(?:wenn|angenommen|beispielsweise)\b"#,
        text
      ).isEmpty
    {
      result.action = .unsupported
      return result
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
