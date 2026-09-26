import Foundation

/// A request contains search constraints, never calendar facts supplied by a model.
struct CalendarQuestion: Equatable, Sendable {
  enum Detail: String, Codable, Sendable {
    case list, next, count, room, place, therapist, start, end, duration
  }
  var detail: Detail = .list
  var date: Date?
  var days = 1
  var title = ""
  var excluding = ""
  var calendarName: String?
  var reference: String?
  var ordinal = 0
  var offset = 0
  var usesLastPage = false
  /// Start-time constraints in the explicitly captured civil timezone.
  var afterMinutes: Int?
  var beforeMinutes: Int?
  var timezone = TimeZone.current.identifier
  /// Filled only after resolving an allowed conversational reference to live data.
  var afterEventID: String?
  var afterEventDate: Date?
  var hasTimeBounds: Bool { afterMinutes != nil || beforeMinutes != nil }
  var validTimeBounds: Bool {
    [afterMinutes, beforeMinutes].compactMap { $0 }.allSatisfy { (0..<1440).contains($0) }
      && (afterMinutes ?? 0) < (beforeMinutes ?? 1440)
      && TimeZone(identifier: timezone) != nil
  }
  static func clockMinutes(_ text: String) -> Int? {
    guard !VoiceRules.matches(#"^([01]\d|2[0-3]):[0-5]\d$"#, text).isEmpty else { return nil }
    return VoiceRules.time(text)
  }

  static func concernsCalendar(_ text: String) -> Bool {
    VoiceRules.parse(text).action != .unsupported
      || !VoiceRules.matches(
        #"\b(termin\w*|kalender\w*|therap\w*|raum|räume|uhr|danach|davor|anschließend|anzahl|wann|wo)\b"#,
        VoiceRules.normalized(text)
      ).isEmpty
  }

  /// Deliberately complete patterns: extra constraints go to structured understanding.
  static func direct(_ input: String, now: Date = .now, calendar: Calendar = .current) -> Self? {
    let text = VoiceRules.normalized(input).trimmingCharacters(in: .punctuationCharacters)
    if [
      "danach", "und danach", "was kommt danach", "welcher termin kommt danach",
      "was steht danach an",
    ]
    .contains(text) {
      return Self(detail: .next, days: 90, usesLastPage: true)
    }
    let timePattern =
      #" (vormittags|nachmittags|vor \d{1,2}(?::[0-5]\d)? uhr|(?:nach|ab) \d{1,2}(?::[0-5]\d)? uhr)$"#
    if let expression = try? NSRegularExpression(pattern: timePattern),
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range, in: text),
      var question = direct(String(text[..<range.lowerBound]), now: now, calendar: calendar)
    {
      guard !question.hasTimeBounds else { return nil }
      let suffix = text[range].trimmingCharacters(in: .whitespaces)
      switch suffix {
      case "vormittags": question.beforeMinutes = 12 * 60
      case "nachmittags":
        question.afterMinutes = 12 * 60
        question.beforeMinutes = 18 * 60
      default:
        let clock = suffix.split(separator: " ").dropFirst().joined(separator: " ")
        guard let minutes = VoiceRules.time(clock) else { return nil }
        if suffix.hasPrefix("vor ") {
          question.beforeMinutes = minutes
        } else {
          question.afterMinutes = minutes
        }
      }
      question.timezone = calendar.timeZone.identifier
      return question.validTimeBounds ? question : nil
    }
    let next = #"^(?:was|wann) ist (?:mein|der) nächste(?:r)? termin$|^(?:mein )?nächster termin$"#
    if !VoiceRules.matches(next, text).isEmpty { return Self(detail: .next, days: 90) }
    let dates =
      "heute|morgen|übermorgen|(?:am )?(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|\(VoiceRules.civilDatePattern))"
    let day = "(?: (?:\(dates)))?"
    let list =
      "^(?:(?:welche termine habe ich|habe ich (?:keine )?termine|was steht an|(?:meine )?termine|(?:bitte )?termine vorlesen|zeige (?:mir )?(?:meine )?termine)\(day)|(?:\(dates)) termine(?: vorlesen)?)$"
    let count = "^wie viele termine habe ich\(day)$"
    if !VoiceRules.matches(list, text).isEmpty || !VoiceRules.matches(count, text).isEmpty {
      let date = VoiceRules.date(text, now: now, calendar: calendar)
      // An explicit invalid date must never silently turn into today's query.
      if date == nil,
        text.contains(where: \.isNumber)
          || !VoiceRules.matches(VoiceRules.civilDatePattern, text).isEmpty
      {
        return nil
      }
      return Self(
        detail: VoiceRules.matches(count, text).isEmpty ? .list : .count,
        date: date ?? calendar.startOfDay(for: now))
    }
    let details: [String: Detail] = [
      "welcher raum": .room, "in welchem raum": .room, "wo": .place,
      "wo findet der statt": .place, "wer ist der therapeut": .therapist,
      "wer ist die therapeutin": .therapist, "wann beginnt der": .start,
      "wann endet der": .end, "wie lange dauert der": .duration,
    ]
    if let detail = details[text] { return Self(detail: detail, usesLastPage: true) }
    if ["und morgen", "und übermorgen", "und heute"].contains(text) {
      return Self(date: VoiceRules.date(text, now: now, calendar: calendar))
    }
    if ["weitere termine", "die nächsten termine", "weiter"].contains(text) {
      return Self(offset: 5, usesLastPage: true)
    }
    return nil
  }

  static func isRepeat(_ text: String) -> Bool {
    ["wiederholen", "bitte wiederholen", "noch einmal", "nochmal", "wie bitte"]
      .contains(VoiceRules.normalized(text).trimmingCharacters(in: .punctuationCharacters))
  }
}

/// Every displayed/spoken field and count is derived from this one query result.
enum CalendarAnswer {
  struct Result: Sendable {
    var text: String
    var events: [CalendarEvent] = []
    var total = 0
    var offset = 0
  }

  static func build(
    _ question: CalendarQuestion, events: [CalendarEvent], warning: String = "",
    now: Date = .now, address: VoiceAddress = .du
  ) -> Result {
    guard question.validTimeBounds else {
      return Result(text: "Bitte die Uhrzeitangabe und den Zeitraum prüfen.")
    }
    var seen = Set<String>()
    var found = events.filter {
      $0.values.end > $0.values.start && seen.insert($0.id).inserted
        && (question.calendarName == nil
          || VoiceRules.normalized($0.calendar_title)
            == VoiceRules.normalized(question.calendarName!))
        && (question.title.isEmpty
          || VoiceRules.normalized($0.values.title).contains(VoiceRules.normalized(question.title)))
        && (question.excluding.isEmpty
          || !VoiceRules.normalized($0.values.title).contains(
            VoiceRules.normalized(question.excluding)))
    }.sorted { ($0.values.start, $0.id) < ($1.values.start, $1.id) }
    if question.detail == .next { found = found.filter { $0.values.end > now } }
    var warnings = [warning].filter { !$0.isEmpty }
    if question.hasTimeBounds {
      let unknownTimes = found.contains(where: \.isAllDay)
      var calendar = Calendar.current
      calendar.timeZone = TimeZone(identifier: question.timezone)!
      found = found.filter { event in
        guard !event.isAllDay else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: event.values.start)
        guard let hour = parts.hour, let minute = parts.minute else { return false }
        let time = hour * 60 + minute
        return time >= (question.afterMinutes ?? 0) && time < (question.beforeMinutes ?? 1440)
      }
      if unknownTimes {
        warnings.append(
          "Ganztägige Termine haben keine bekannte Uhrzeit und sind in dieser Uhrzeitauswahl nicht enthalten."
        )
      }
    }
    let prefix = warnings.isEmpty ? "" : warnings.joined(separator: " ") + " "
    if question.detail == .count {
      return Result(
        text: prefix
          + "In diesem Zeitraum \(found.count == 1 ? "ist 1 passender Termin" : "sind \(found.count) passende Termine") eingetragen.",
        total: found.count)
    }
    guard !found.isEmpty else {
      return Result(
        text: prefix + "In diesem Zeitraum wurden keine passenden lesbaren Termine gefunden.")
    }
    if question.detail == .list || question.detail == .next {
      let page = Array(found.dropFirst(question.offset).prefix(question.detail == .next ? 1 : 5))
      if page.isEmpty {
        return Result(
          text: prefix + "In diesem Zeitraum gibt es keine weiteren passenden Termine.",
          total: found.count, offset: question.offset)
      }
      let remaining = question.detail == .next ? 0 : found.count - question.offset - page.count
      return Result(
        text: prefix + page.map(\.spoken).joined(separator: " ")
          + (remaining > 0 ? " Es gibt \(remaining) weitere passende Termine." : ""),
        events: page, total: found.count, offset: question.offset)
    }
    guard found.count == 1 else {
      return Result(
        text: prefix + address.choose("Welchen Termin meinst du?", "Welchen Termin meinen Sie?")
          + " "
          + found.prefix(5).enumerated().map { "\($0.offset + 1). \($0.element.spoken)" }.joined(
            separator: " ")
          + (found.count > 5
            ? " Es gibt weitere passende Termine; bitte die Suche eingrenzen." : ""),
        events: Array(found.prefix(5)), total: found.count)
    }
    let event = found[0]
    let detail: String
    switch question.detail {
    case .room: detail = event.detailAnswer(to: "Raum")!
    case .place: detail = event.detailAnswer(to: "Ort")!
    case .therapist: detail = event.detailAnswer(to: "Therapeut")!
    case .start:
      detail =
        event.isAllDay
        ? "Der Termin ist ganztägig eingetragen."
        : "Der Termin beginnt am \(eventDate(event.values.start))."
    case .end:
      detail =
        event.isAllDay
        ? "Der Termin ist bis einschließlich \(eventDay(event.values.end.addingTimeInterval(-1))) ganztägig eingetragen."
        : "Der Termin endet am \(eventDate(event.values.end))."
    case .duration:
      detail =
        event.isAllDay
        ? "Der Termin ist ganztägig eingetragen; eine Behandlungsdauer ist nicht bekannt."
        : "Der Termin dauert \(Int(event.values.end.timeIntervalSince(event.values.start) / 60)) Minuten."
    case .list, .next, .count: detail = event.spoken
    }
    return Result(text: prefix + detail, events: [event], total: 1)
  }
}
