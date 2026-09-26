import Foundation

indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
}
struct CalendarEventValues: Codable, Equatable, Sendable {
    var title: String; var start_utc: String; var end_utc: String; var timezone: String; var location: String; var reminder_minutes: Int?
    var start: Date { ISO8601DateFormatter().date(from: start_utc) ?? .distantPast }
    var end: Date { ISO8601DateFormatter().date(from: end_utc) ?? .distantPast }
    var spoken: String {
        let until = Calendar.current.isDate(start, inSameDayAs: end) ? eventTime(end) : eventDate(end)
        return "\(title), \(eventDate(start)), bis \(until). \(location.isEmpty ? "Kein Ort angegeben" : location)."
    }
}
struct CalendarEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String; let external_id: String; let calendar_id: String; let calendar_title: String; let source: String
    let occurrence: String; let recurring: Bool; let system_only: Bool; let writable: Bool
    let values: CalendarEventValues; let metadata: JSONValue; let fingerprint: String; var import_id: String?
    var isAllDay: Bool {
        if case .object(let fields) = metadata, case .bool(let value) = fields["all_day"] { return value }
        return false
    }
    var spoken: String {
        let summary: String
        if isAllDay {
            let last = values.end.addingTimeInterval(-1)
            let span = Calendar.current.isDate(values.start, inSameDayAs: last) ? "" : " bis \(eventDay(last))"
            summary = "\(values.title), ganztägig am \(eventDay(values.start))\(span).\(values.location.isEmpty ? "" : " " + values.location + ".")"
        } else { summary = values.spoken }
        return "\(summary) Kalender \(calendar_title)\(source.isEmpty ? "" : ", " + source)."
    }
}

func eventTime(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_AT"))) }
func eventDate(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(Locale(identifier: "de_AT"))) }

func eventDay(_ date: Date) -> String { date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_AT"))) }
