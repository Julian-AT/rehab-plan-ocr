import Foundation

/// Keep the original wire value while parsing it once per decode or edit.
/// Layout and spoken-answer projections can read the Date without a formatter.
@propertyWrapper struct CalendarTimestamp: Codable, Equatable, Sendable {
  private var rawValue: String
  private(set) var projectedValue: Date?
  var wrappedValue: String {
    get { rawValue }
    set {
      rawValue = newValue
      projectedValue = ISO8601DateFormatter().date(from: newValue)
    }
  }
  init(wrappedValue: String) {
    rawValue = wrappedValue
    projectedValue = ISO8601DateFormatter().date(from: wrappedValue)
  }
  init(from decoder: Decoder) throws {
    self.init(wrappedValue: try decoder.singleValueContainer().decode(String.self))
  }
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct CalendarQueryResponse: Decodable, Sendable {
  let events: [CalendarEvent]
  let unavailableCalendarIDs: [String]?
  var unavailableEvents: [UnavailableCalendarEvent]? = nil
  enum CodingKeys: String, CodingKey {
    case events
    case unavailableCalendarIDs = "unavailable_calendar_ids"
    case unavailableEvents = "unavailable_events"
  }
  var warning: String {
    unavailableCalendarIDs?.isEmpty == false
      ? "Einige Kalenderdaten sind nicht verfügbar. Die Auskunft umfasst nur lesbare Termine. " : ""
  }
}

struct UnavailableCalendarEvent: Decodable, Sendable {
  let id: String
  @CalendarTimestamp var start: String
  @CalendarTimestamp var end: String
  enum CodingKeys: String, CodingKey {
    case id
    case start = "start_utc"
    case end = "end_utc"
  }
  func overlaps(_ day: Date, calendar: Calendar = .current) -> Bool {
    guard let start = $start, let end = $end, end > start,
      let interval = calendar.dateInterval(of: .day, for: day)
    else { return false }
    return start < interval.end && end > interval.start
  }
}

indirect enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Double.self) {
      self = .number(v)
    } else if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
}
struct CalendarEventValues: Codable, Equatable, Sendable {
  var title: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  @CalendarTimestamp var start_utc: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  @CalendarTimestamp var end_utc: String
  var timezone: String
  var location: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var reminder_minutes: Int?
  var start: Date { $start_utc ?? .distantPast }
  var end: Date { $end_utc ?? .distantPast }
  var spoken: String { spoken(in: .current) }
  func spoken(in timezone: TimeZone) -> String {
    var calendar = Calendar.current
    calendar.timeZone = timezone
    let until =
      calendar.isDate(start, inSameDayAs: end)
      ? eventTime(end, timezone: timezone) : eventDate(end, timezone: timezone)
    return
      "\(title) beginnt am \(eventDay(start, timezone: timezone)) um \(eventTime(start, timezone: timezone)) und endet \(calendar.isDate(start, inSameDayAs: end) ? "um" : "am") \(until)."
      + (location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "" : " Ort: \(location).")
  }
}
struct CalendarEvent: Codable, Identifiable, Equatable, Sendable {
  let id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let external_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_id: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let calendar_title: String
  let source: String
  let occurrence: String
  let recurring: Bool
  // swift-format-ignore: AlwaysUseLowerCamelCase
  let system_only: Bool
  let writable: Bool
  let values: CalendarEventValues
  let metadata: JSONValue
  let fingerprint: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var import_id: String?
  var isAllDay: Bool {
    if case .object(let fields) = metadata, case .bool(let value) = fields["all_day"] {
      return value
    }
    return false
  }
  /// Imported treatment details are preserved in EventKit notes. Read only
  /// labelled fields; never mistake an arbitrary note or attendee for a therapist.
  func note(_ labels: [String]) -> String? {
    guard case .object(let fields) = metadata, case .string(let notes) = fields["notes"] else {
      return nil
    }
    let wanted = labels.map { $0.lowercased() + ":" }.sorted { $0.count > $1.count }
    var result: [String] = []
    var collecting = false
    for line in notes.components(separatedBy: .newlines) {
      if collecting && line.hasPrefix("  ") {
        result.append(line.trimmingCharacters(in: .whitespaces))
        continue
      }
      if collecting { break }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let prefix = wanted.first(where: { trimmed.lowercased().hasPrefix($0) }) else {
        continue
      }
      collecting = true
      result.append(trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
    }
    let value = result.filter { !$0.isEmpty }.joined(separator: ", ")
    return value.isEmpty ? nil : value
  }
  var therapist: String? {
    note(["Therapeut", "Therapeutin", "Therapeut:in", "Therapeut/in", "Therapist"])
  }
  var therapistDescription: String {
    therapist.map { "Therapeut: \($0)" } ?? "Therapeut nicht angegeben"
  }
  var knownPlace: String {
    var parts = [values.location.trimmingCharacters(in: .whitespacesAndNewlines)]
    for label in ["Raum", "Klinik", "Abteilung"] {
      if let value = note([label]),
        !parts.contains(where: { $0.localizedCaseInsensitiveContains(value) })
      {
        parts.append(value)
      }
    }
    let text = parts.filter { !$0.isEmpty }.joined(separator: " · ")
    return text
  }
  var placeDescription: String { knownPlace.isEmpty ? "Ort nicht angegeben" : knownPlace }
  func detailAnswer(to question: String) -> String? {
    let query = question.lowercased()
    if query.range(of: #"\b(therapeut|therapeutin|wer)\b"#, options: .regularExpression) != nil {
      return therapist.map { "Die Behandlung übernimmt \($0)." }
        ?? "Für diesen Termin ist mir kein Therapeut bekannt."
    }
    if query.range(of: #"\b(raum|zimmer|ort|wo)\b"#, options: .regularExpression) != nil {
      if query.contains("raum") || query.contains("zimmer") {
        let room =
          note(["Raum", "Zimmer"])
          ?? (values.location.range(of: #"(?i)\b(raum|zimmer)\b"#, options: .regularExpression)
            != nil ? values.location : nil)
        return room.map { "Der Raum ist \($0)." } ?? "Für diesen Termin ist mir kein Raum bekannt."
      }
      return knownPlace.isEmpty
        ? "Für diesen Termin ist mir kein Ort bekannt." : "Ort: \(knownPlace)."
    }
    return nil
  }
  var spoken: String { spoken(in: .current) }
  func spoken(in timezone: TimeZone) -> String {
    var calendar = Calendar.current
    calendar.timeZone = timezone
    let summary: String
    if isAllDay {
      let last = values.end.addingTimeInterval(-1)
      let span =
        calendar.isDate(values.start, inSameDayAs: last)
        ? "" : " bis \(eventDay(last, timezone: timezone))"
      summary =
        "\(values.title), ganztägig am \(eventDay(values.start, timezone: timezone))\(span).\(values.location.isEmpty ? "" : " " + values.location + ".")"
    } else {
      var summaryValues = values
      summaryValues.location = knownPlace
      summary = summaryValues.spoken(in: timezone)
    }
    return
      summary
      + (therapist.map { " Die Behandlung übernimmt \($0)." } ?? "")
  }
}

func eventTime(_ date: Date, timezone: TimeZone = .current) -> String {
  date.formatted(
    Date.FormatStyle(timeZone: timezone).hour().minute().locale(Locale(identifier: "de_AT")))
}
func eventDate(_ date: Date, timezone: TimeZone = .current) -> String {
  date.formatted(
    Date.FormatStyle(timeZone: timezone).weekday(.wide).day().month(.wide).year().hour().minute()
      .locale(
        Locale(identifier: "de_AT")))
}

func eventDay(_ date: Date, timezone: TimeZone = .current) -> String {
  date.formatted(
    Date.FormatStyle(timeZone: timezone).day().month(.wide).year().locale(
      Locale(identifier: "de_AT")))
}

/// Strict routing for widget and notification URLs; external parameters are ignored by rejection.
enum AgendaLink: Equatable {
  case today
  case event(String)
  init?(_ url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "reha-calendar", parts.user == nil, parts.password == nil,
      parts.port == nil, parts.query == nil, parts.fragment == nil
    else { return nil }
    if parts.host == "today", parts.path.isEmpty {
      self = .today
      return
    }
    guard parts.host == "event", url.pathComponents.count == 2,
      let id = url.pathComponents.last, UUID(uuidString: id) != nil,
      parts.percentEncodedPath == "/\(id)"
    else { return nil }
    self = .event(id)
  }
}
