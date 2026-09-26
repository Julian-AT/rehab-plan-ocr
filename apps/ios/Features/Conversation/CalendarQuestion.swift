import Foundation

struct CalendarReadEvidence: Sendable {
  struct Source: Sendable {
    let id: String
    let fingerprint: String
  }
  let observedAt: Date
  let selection: AgendaSelection
  let sources: [Source]
  let complete: Bool
}

struct CalendarInsightRequest: Sendable {
  let question: CalendarQuestion
  let windows: [DateInterval]
  init(question: CalendarQuestion, start: Date) throws {
    guard question.detail.isInsight, question.validTimeBounds, (1...7).contains(question.days),
      question.reference == nil, question.ordinal == 0, !question.usesLastPage,
      // Filtering titles out of a free/busy calculation would invent free time.
      question.detail != .freeTime || (question.title.isEmpty && question.excluding.isEmpty)
    else { throw CalendarUnderstandingError.invalidRequest }
    self.question = question
    let calendar = question.calendar
    windows = try (0..<question.days).map { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: start),
        let day = calendar.dateInterval(of: .day, for: date)
      else { throw CalendarUnderstandingError.invalidRequest }
      func bound(_ minutes: Int?, fallback: Date) throws -> Date {
        guard let minutes else { return fallback }
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0)
        // Ambiguous/repeated or nonexistent local clock bounds require clarification.
        let first = calendar.nextDate(
          after: day.start.addingTimeInterval(-1), matching: components,
          matchingPolicy: .strict, repeatedTimePolicy: .first)
        let last = calendar.nextDate(
          after: day.start.addingTimeInterval(-1), matching: components,
          matchingPolicy: .strict, repeatedTimePolicy: .last)
        guard let first, first == last, first >= day.start, first < day.end else {
          throw CalendarUnderstandingError.invalidRequest
        }
        return first
      }
      return try DateInterval(
        start: bound(question.afterMinutes, fallback: day.start),
        end: bound(question.beforeMinutes, fallback: day.end))
    }
  }
}

/// All arithmetic uses actual calendar records and absolute intervals. Civil day
/// boundaries come from Calendar, so DST days are not assumed to be 24 hours.
enum CalendarInsights {
  static func answer(_ request: CalendarInsightRequest, response: CalendarQueryResponse)
    -> CalendarAnswer.Result
  {
    let question = request.question
    guard response.events.count <= 1_000 else {
      return .init(text: "Bitte den Zeitraum für diese Auswertung eingrenzen.")
    }
    guard !response.scope.calendarIDs.isEmpty else {
      return .init(text: "Bitte zuerst einen sichtbaren Kalender auswählen.")
    }
    let incomplete =
      response.unavailableCalendarIDs?.isEmpty == false
      || response.unavailableEvents?.isEmpty == false
    if question.detail == .freeTime && incomplete {
      return .init(
        text:
          "Einige Kalenderdaten sind nicht lesbar. Freie Zeiten lassen sich deshalb nicht verlässlich bestimmen."
      )
    }
    var seen = Set<String>()
    let events = response.events.filter {
      response.scope.calendarIDs.contains($0.calendar_id) && $0.values.end > $0.values.start
        && seen.insert($0.id).inserted
        && (question.calendarName == nil
          || VoiceRules.normalized($0.calendar_title)
            == VoiceRules.normalized(question.calendarName!))
        && (question.title.isEmpty
          || VoiceRules.normalized($0.values.title).contains(VoiceRules.normalized(question.title)))
        && (question.excluding.isEmpty
          || !VoiceRules.normalized($0.values.title).contains(
            VoiceRules.normalized(question.excluding)))
    }.sorted { ($0.values.start, $0.id) < ($1.values.start, $1.id) }
    let timezone = question.calendar.timeZone
    func clock(_ date: Date) -> String { eventTime(date, timezone: timezone) }
    func range(_ interval: DateInterval) -> String {
      "\(eventDay(interval.start, timezone: timezone)) von \(clock(interval.start)) bis \(clock(interval.end))"
    }
    func clipped(_ event: CalendarEvent, _ window: DateInterval) -> DateInterval? {
      let start = max(event.values.start, window.start)
      let end = min(event.values.end, window.end)
      return end > start ? DateInterval(start: start, end: end) : nil
    }
    var sentences: [String] = []
    var total = 0
    switch question.detail {
    case .freeTime:
      var gaps: [DateInterval] = []
      for window in request.windows {
        var cursor = window.start
        for event in events {
          guard let occupied = clipped(event, window) else { continue }
          if occupied.start > cursor {
            gaps.append(DateInterval(start: cursor, end: occupied.start))
          }
          cursor = max(cursor, occupied.end)
        }
        if cursor < window.end { gaps.append(DateInterval(start: cursor, end: window.end)) }
      }
      total = gaps.count
      sentences = gaps.prefix(5).map { range($0) + "." }
      if gaps.isEmpty {
        sentences = [
          "In diesem Zeitraum gibt es keine freie Zeit zwischen den eingetragenen Terminen."
        ]
      } else {
        sentences.insert("In den ausgewählten Kalendern ist frei:", at: 0)
      }
    case .conflicts:
      for (index, event) in events.enumerated() {
        for other in events.dropFirst(index + 1) {
          if other.values.start >= event.values.end { break }
          for window in request.windows {
            guard let left = clipped(event, window), let right = clipped(other, window) else {
              continue
            }
            let start = max(left.start, right.start)
            let end = min(left.end, right.end)
            guard end > start else { continue }
            total += 1
            if sentences.count < 5 {
              sentences.append(
                "\(event.values.title) und \(other.values.title) überschneiden sich am \(range(DateInterval(start: start, end: end)))."
              )
            }
          }
        }
      }
      if total == 0 {
        sentences = ["Die lesbaren Termine überschneiden sich in diesem Zeitraum nicht."]
      }
    case .totalDuration, .dailySummary:
      var seconds = 0.0
      var allDay = 0
      var eventIDs = Set<String>()
      for window in request.windows {
        let matches = events.filter { clipped($0, window) != nil }
        let timed = matches.filter { !$0.isAllDay }
        let sum = timed.compactMap { clipped($0, window)?.duration }.reduce(0, +)
        seconds += sum
        allDay += matches.filter(\.isAllDay).count
        eventIDs.formUnion(timed.map(\.id))
        if question.detail == .dailySummary {
          sentences.append(
            "\(eventDay(window.start, timezone: timezone)): \(matches.count) Termine, \(Int(sum / 60)) Minuten mit bekannter Uhrzeit."
          )
        }
      }
      total = eventIDs.count
      if question.detail == .totalDuration {
        sentences = [
          "Die eingetragenen Termine mit bekannter Uhrzeit dauern in diesem Zeitraum zusammen \(Int(seconds / 60)) Minuten. Überschneidungen sind dabei mehrfach gezählt."
        ]
      }
      sentences.append(
        "Das ist die geplante Terminzeit; eine Therapiedauer wird nicht aus Termintiteln abgeleitet."
      )
      if allDay > 0 {
        sentences.append(
          "Ganztägige Termine sind ohne bekannte Behandlungsdauer eingetragen und nicht in der Minutensumme enthalten."
        )
      }
    default: return .init(text: "Bitte die Kalenderfrage eingrenzen.")
    }
    if [.freeTime, .conflicts].contains(question.detail), total > 5 {
      sentences.append("Es gibt \(total - 5) weitere Ergebnisse. Bitte den Zeitraum eingrenzen.")
    }
    if incomplete {
      sentences.insert("Die Auswertung umfasst nur die lesbaren Kalenderdaten.", at: 0)
    }
    return .init(text: sentences.joined(separator: " "), total: total)
  }
}

/// A request contains search constraints, never calendar facts supplied by a model.
struct CalendarQuestion: Equatable, Sendable {
  enum Detail: String, Codable, Sendable {
    case list, next, count, room, place, therapist, start, end, duration
    case freeTime, conflicts, totalDuration, dailySummary
    var isInsight: Bool { [.freeTime, .conflicts, .totalDuration, .dailySummary].contains(self) }
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
  var refinesPrevious = false
  /// Start-time constraints in the explicitly captured civil timezone.
  var afterMinutes: Int?
  var beforeMinutes: Int?
  var timezone = TimeZone.current.identifier
  /// Filled only after resolving an allowed conversational reference to live data.
  var afterEventID: String?
  var afterEventDate: Date?
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    return calendar
  }
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
        #"\b(plan|pläne|termin\w*|kalender\w*|therap\w*|raum|räume|uhr|danach|davor|anschließend|anzahl|wann|wo|frei|überschneidungen|terminkonflikte|tagesübersicht|tageszusammenfassung|verplant)\b"#,
        VoiceRules.normalized(text)
      ).isEmpty
  }

  /// Deliberately complete patterns: extra constraints go to structured understanding.
  static func direct(_ input: String, now: Date = .now, calendar: Calendar = .current) -> Self? {
    var question = directInCalendar(input, now: now, calendar: calendar)
    question?.timezone = calendar.timeZone.identifier
    return question
  }

  private static func directInCalendar(_ input: String, now: Date, calendar: Calendar) -> Self? {
    let text = VoiceRules.normalized(input).trimmingCharacters(in: .punctuationCharacters)
    if [
      "danach", "und danach", "was kommt danach", "welcher termin kommt danach",
      "was steht danach an",
    ]
    .contains(text) {
      return Self(detail: .next, days: 90, usesLastPage: true)
    }
    if let match = VoiceRules.matches(
      #" (?:von|zwischen) ([\p{L}\d:]+)(?: uhr)? (?:bis|und) ([\p{L}\d:]+) uhr$"#, text
    ).first,
      let range = text.range(of: match[0], options: .backwards),
      var query = direct(String(text[..<range.lowerBound]), now: now, calendar: calendar),
      !query.hasTimeBounds,
      let lower = VoiceRules.time(match[1] + " uhr"), let upper = VoiceRules.time(match[2] + " uhr")
    {
      query.afterMinutes = lower
      query.beforeMinutes = upper
      return query.validTimeBounds ? query : nil
    }
    let timePattern =
      #" (vormittags|nachmittags|(?:vor|nach|ab) (?:\d{1,2}(?::[0-5]\d)?|[\p{L}]+) uhr)$"#
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
    if let match = VoiceRules.matches(
      #"^(?:nur|und) (heute|morgen|übermorgen) (nachmittags|vormittags|am nachmittag|am vormittag)$"#,
      text
    ).first {
      let afternoon = match[2].contains("nachmittag")
      return Self(
        date: VoiceRules.date(match[1], now: now, calendar: calendar),
        refinesPrevious: true, afterMinutes: afternoon ? 720 : nil,
        beforeMinutes: afternoon ? 1080 : 720)
    }
    let next = #"^(?:was|wann) ist (?:mein|der) nächste(?:r)? termin$|^(?:mein )?nächster termin$"#
    if !VoiceRules.matches(next, text).isEmpty { return Self(detail: .next, days: 90) }
    let dates =
      "heute|morgen|übermorgen|(?:am )?(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|\(VoiceRules.civilDatePattern))"
    let datedNext =
      "^(?:(?:was|welchen termin) habe ich (?:\(dates)) als nächstes|(?:mein )?nächster termin (?:\(dates)))$"
    let correctedList =
      "^nicht (?:\(dates)) sondern (?:\(dates)):? welche termine habe ich da$"
    if !VoiceRules.matches(datedNext, text).isEmpty
      || !VoiceRules.matches(correctedList, text).isEmpty
    {
      guard !VoiceRules.hasInvalidDate(text, now: now, calendar: calendar),
        let date = VoiceRules.date(text, now: now, calendar: calendar)
      else { return nil }
      return Self(
        detail: VoiceRules.matches(datedNext, text).isEmpty ? .list : .next, date: date)
    }
    let day = "(?: (?:\(dates)))?"
    let insights: [(String, Detail)] = [
      ("(?:wann habe ich frei|freie zeiten|wann habe ich zeit)", .freeTime),
      (
        "(?:welche termine überschneiden sich|gibt es überschneidungen|gibt es terminkonflikte)",
        .conflicts
      ),
      (
        "(?:wie lange dauern meine termine insgesamt|wie viel zeit ist verplant|gesamtdauer meiner termine|wie viel therapie habe ich)",
        .totalDuration
      ),
      ("(?:fasse meinen tag zusammen|tagesübersicht|tageszusammenfassung)", .dailySummary),
    ]
    for (pattern, detail) in insights where !VoiceRules.matches("^\(pattern)\(day)$", text).isEmpty
    {
      guard !VoiceRules.hasInvalidDate(text, now: now, calendar: calendar) else { return nil }
      return Self(
        detail: detail,
        date: VoiceRules.date(text, now: now, calendar: calendar)
          ?? calendar.startOfDay(for: now))
    }
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
      "und der raum dazu": .room, "welcher raum ist das": .room,
      "in welchem raum ist der termin": .room, "und in welchem raum": .room,
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
    var evidence: CalendarReadEvidence?
  }

  static func build(
    _ question: CalendarQuestion, events: [CalendarEvent], warning: String = "",
    now: Date = .now, address: VoiceAddress = .du
  ) -> Result {
    guard question.validTimeBounds else {
      return Result(text: "Bitte die Uhrzeitangabe und den Zeitraum prüfen.")
    }
    let timezone = question.calendar.timeZone
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
      let calendar = question.calendar
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
        text: prefix + page.map { $0.spoken(in: timezone) }.joined(separator: " ")
          + (remaining > 0 ? " Es gibt \(remaining) weitere passende Termine." : ""),
        events: page, total: found.count, offset: question.offset)
    }
    guard found.count == 1 else {
      return Result(
        text: prefix + address.choose("Welchen Termin meinst du?", "Welchen Termin meinen Sie?")
          + " "
          + found.prefix(5).enumerated().map {
            "\($0.offset + 1). \($0.element.spoken(in: timezone))"
          }.joined(
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
        : "Der Termin beginnt am \(eventDate(event.values.start, timezone: timezone))."
    case .end:
      detail =
        event.isAllDay
        ? "Der Termin ist bis einschließlich \(eventDay(event.values.end.addingTimeInterval(-1), timezone: timezone)) ganztägig eingetragen."
        : "Der Termin endet am \(eventDate(event.values.end, timezone: timezone))."
    case .duration:
      detail =
        event.isAllDay
        ? "Der Termin ist ganztägig eingetragen; eine Behandlungsdauer ist nicht bekannt."
        : "Der Termin dauert \(Int(event.values.end.timeIntervalSince(event.values.start) / 60)) Minuten."
    case .list, .next, .count, .freeTime, .conflicts, .totalDuration, .dailySummary:
      detail = event.spoken(in: timezone)
    }
    return Result(text: prefix + detail, events: [event], total: 1)
  }
}
