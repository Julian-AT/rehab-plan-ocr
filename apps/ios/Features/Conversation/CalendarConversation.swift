import Foundation

/// References survive turns, query results do not. Every new answer rechecks visibility
/// and live values; repeated lookups within that answer share one snapshot.
actor CalendarConversation {
  typealias Fetch = @Sendable (Date, Date) async throws -> CalendarQueryResponse
  private let fetch: Fetch
  private var active: UUID?
  private var references: [String: CalendarEvent] = [:]
  private var lastPage: [String] = []
  private var nextID = 0
  private var lastQuestion: CalendarQuestion?
  private var nextOffset = 0
  private var cached: [String: CalendarQueryResponse] = [:]

  init(fetch: @escaping Fetch) { self.fetch = fetch }
  func begin(_ token: UUID) {
    active = token
    cached = [:]
  }
  func invalidate(_ token: UUID? = nil) {
    guard token == nil || active == token else { return }
    active = nil
    cached = [:]
  }
  func clear(_ token: UUID? = nil) {
    guard active == nil || token == nil || active == token else { return }
    invalidate()
    references = [:]
    lastPage = []
    lastQuestion = nil
    nextOffset = 0
  }
  private func check(_ token: UUID) throws {
    try Task.checkCancellation()
    guard token == active else { throw CancellationError() }
  }
  static func civilDate(_ text: String, calendar: Calendar = .current) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard text.count == 10, let date = formatter.date(from: text),
      formatter.string(from: date) == text
    else { return nil }
    return calendar.startOfDay(for: date)
  }
  static func day(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
  func context() throws -> String {
    let value: [String: Any] = [
      "today": Self.day(.now), "now_local": eventDate(.now),
      "timezone": TimeZone.current.identifier,
      "last_discussed_date": lastQuestion?.date.map(Self.day) ?? "",
      "last_page": lastPage.compactMap { id -> [String: Any]? in
        guard let event = references[id] else { return nil }
        return [
          "reference": id, "title": String(event.values.title.prefix(120)),
          "date": Self.day(event.values.start),
        ]
      },
    ]
    return String(
      decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      as: UTF8.self)
  }
  private func query(start: Date, days: Int, token: UUID) async throws -> CalendarQueryResponse {
    try check(token)
    guard (1...90).contains(days),
      let end = Calendar.current.date(byAdding: .day, value: days, to: start)
    else {
      throw CalendarUnderstandingError.invalidRequest
    }
    let key = "\(start.timeIntervalSince1970):\(days)"
    if let response = cached[key] { return response }
    let response = try await fetch(start, end)
    try check(token)
    let scoped = CalendarQueryResponse(
      events: response.events.filter { $0.values.start < end && $0.values.end > start },
      unavailableCalendarIDs: response.unavailableCalendarIDs,
      unavailableEvents: response.unavailableEvents)
    cached[key] = scoped
    return scoped
  }
  private func reference(_ question: CalendarQuestion) -> CalendarEvent? {
    if let id = question.reference { return references[id] }
    if question.ordinal > 0, lastPage.indices.contains(question.ordinal - 1) {
      return references[lastPage[question.ordinal - 1]]
    }
    if question.usesLastPage && lastPage.count == 1 { return references[lastPage[0]] }
    return nil
  }
  func resolve(
    _ input: CalendarQuestion, token: UUID, now: Date = .now, address: VoiceAddress = .du
  ) async throws -> CalendarAnswer.Result {
    try check(token)
    guard (1...90).contains(input.days), (0...500).contains(input.offset),
      (0...5).contains(input.ordinal), input.title.count <= 160, input.excluding.count <= 160,
      input.validTimeBounds
    else { throw CalendarUnderstandingError.invalidRequest }
    var question = input
    if input.usesLastPage && input.detail == .list && input.offset > 0 {
      guard let previous = lastQuestion else {
        return CalendarAnswer.Result(text: "Bitte zuerst einen Zeitraum auswählen.")
      }
      question = previous
      question.detail = .list
      question.offset = nextOffset
      guard question.offset <= 500 else {
        return CalendarAnswer.Result(
          text: "Bitte den Zeitraum oder die Terminbezeichnung eingrenzen.")
      }
    }
    let referenced = reference(question)
    let needsReference =
      question.reference != nil || question.ordinal > 0
      || (question.usesLastPage && question.detail != .list)
    let followsReference = needsReference && question.detail == .next
    if needsReference && referenced == nil {
      return CalendarAnswer.Result(
        text: address.choose("Welchen Termin meinst du?", "Welchen Termin meinen Sie?"))
    }
    if followsReference && question.date == nil { question.days = 90 }
    if needsReference && !followsReference, let date = question.date, let referenced,
      !Calendar.current.isDate(date, inSameDayAs: referenced.values.start)
    {
      return CalendarAnswer.Result(
        text:
          "Der besprochene Termin liegt an einem anderen Tag. Bitte den Termin oder das Datum genauer angeben."
      )
    }
    let start = Calendar.current.startOfDay(for: question.date ?? referenced?.values.start ?? now)
    let response = try await query(
      start: start, days: referenced == nil || followsReference ? question.days : 1, token: token)
    try check(token)
    if followsReference {
      question.afterEventID = referenced?.id
      question.afterEventDate = referenced?.values.start
    }
    var warning = response.warning
    let events: [CalendarEvent]
    if let anchorID = question.afterEventID {
      let anchorResponse: CalendarQueryResponse
      if let anchorDate = question.afterEventDate,
        !Calendar.current.isDate(anchorDate, inSameDayAs: start)
      {
        anchorResponse = try await query(
          start: Calendar.current.startOfDay(for: anchorDate), days: 1, token: token)
        if !anchorResponse.warning.isEmpty && anchorResponse.warning != warning {
          warning = [warning, anchorResponse.warning].filter { !$0.isEmpty }.joined(separator: " ")
        }
      } else {
        anchorResponse = response
      }
      guard let anchor = anchorResponse.events.first(where: { $0.id == anchorID }) else {
        return CalendarAnswer.Result(
          text: "Der zuvor besprochene Termin ist in den ausgewählten Kalendern nicht mehr lesbar.")
      }
      events = response.events.filter { $0.id != anchorID && $0.values.start >= anchor.values.end }
      // Pagination keeps the native anchor, not a model-produced ID or the
      // previous answer's copied end time. Every turn resolves its live values.
      question.reference = nil
      question.ordinal = 0
      question.usesLastPage = false
    } else {
      events =
        referenced.map { old in response.events.filter { $0.id == old.id } } ?? response.events
    }
    if referenced != nil && !followsReference && events.isEmpty {
      return CalendarAnswer.Result(
        text: "Der zuvor besprochene Termin ist in den ausgewählten Kalendern nicht mehr lesbar.")
    }
    let result = CalendarAnswer.build(
      question, events: events, warning: warning, now: now, address: address)
    if !result.events.isEmpty {
      var page: [String] = []
      for event in result.events {
        let id =
          references.first(where: { $0.value.id == event.id })?.key
          ?? {
            nextID += 1
            return "r\(nextID)"
          }()
        references[id] = event
        page.append(id)
      }
      lastPage = page
      references = references.filter { page.contains($0.key) }
    } else {
      lastPage = []
      references = [:]
    }
    if !needsReference || followsReference {
      question.date = start
      question.offset = result.offset
      lastQuestion = question
      nextOffset = result.offset + result.events.count
    }
    return result
  }
}

enum CalendarUnderstandingError: Error {
  case invalidRequest, contextTooLarge
}
