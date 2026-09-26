import Foundation

struct CalendarQueryResponse: Decodable {
  let events: [CalendarEvent]
  let unavailableCalendarIDs: [String]?
  enum CodingKeys: String, CodingKey {
    case events
    case unavailableCalendarIDs = "unavailable_calendar_ids"
  }
  var warning: String {
    unavailableCalendarIDs?.isEmpty == false
      ? "Einige Kalenderdaten sind nicht verfügbar. Die Auskunft umfasst nur lesbare Termine. " : ""
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
  var start_utc: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var end_utc: String
  var timezone: String
  var location: String
  // swift-format-ignore: AlwaysUseLowerCamelCase
  var reminder_minutes: Int?
  var start: Date { ISO8601DateFormatter().date(from: start_utc) ?? .distantPast }
  var end: Date { ISO8601DateFormatter().date(from: end_utc) ?? .distantPast }
  var displayLocation: String? {
    let text = location.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
  var spoken: String {
    let until = Calendar.current.isDate(start, inSameDayAs: end) ? eventTime(end) : eventDate(end)
    return
      "\(title), \(eventDate(start)), bis \(until)." + (displayLocation.map { " \($0)." } ?? "")
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
  var therapistDescription: String? {
    therapist.map { "Therapeut: \($0)" }
  }
  var placeDescription: String? {
    var parts = [values.location.trimmingCharacters(in: .whitespacesAndNewlines)]
    for label in ["Raum", "Klinik", "Abteilung"] {
      if let value = note([label]),
        !parts.contains(where: { $0.localizedCaseInsensitiveContains(value) })
      {
        parts.append(value)
      }
    }
    let text = parts.filter { !$0.isEmpty }.joined(separator: " · ")
    return text.isEmpty ? nil : text
  }
  var spoken: String {
    let summary: String
    if isAllDay {
      let last = values.end.addingTimeInterval(-1)
      let span =
        Calendar.current.isDate(values.start, inSameDayAs: last) ? "" : " bis \(eventDay(last))"
      summary =
        "\(values.title), ganztägig am \(eventDay(values.start))\(span)."
    } else {
      var timing = values
      timing.location = ""
      summary = timing.spoken
    }
    return
      ([summary] + [placeDescription, therapistDescription].compactMap { $0.map { $0 + "." } } + [
        "Kalender \(calendar_title)\(source.isEmpty ? "" : ", " + source)."
      ]).joined(separator: " ")
  }
}

func eventTime(_ date: Date) -> String {
  date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_AT")))
}
func eventDate(_ date: Date) -> String {
  date.formatted(
    .dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(
      Locale(identifier: "de_AT")))
}

func eventDay(_ date: Date) -> String {
  date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_AT")))
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
