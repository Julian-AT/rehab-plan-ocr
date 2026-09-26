import Foundation
import RehaCore

/// Model JSON is decoded by the portable compact-schema boundary. Only this typed
/// result reaches the app; references still undergo a fresh visible-calendar query.
enum AssistantInterpretation {
  static func clarification(_ problem: AssistantProblem?, address: VoiceAddress) -> String {
    switch problem {
    case .invalidDate: "Dieses Datum gibt es nicht. Bitte Tag, Monat und Jahr nennen."
    case .missingDate: "An welchem Tag soll der Termin stattfinden?"
    case .missingTime: "Um wie viel Uhr soll der Termin beginnen?"
    case .missingTitle: "Wie soll der Termin heißen?"
    case .unsupported: "Bitte eine Frage zum Kalender oder zur App stellen."
    case .ambiguous, .missingEvent, nil:
      address.choose(
        "Welchen Zeitraum oder welchen Termin meinst du?",
        "Welchen Zeitraum oder welchen Termin meinen Sie?")
    }
  }

  static func decode(_ text: String, references: [String], timezone: String) throws
    -> ConversationInterpretation
  {
    guard let zone = TimeZone(identifier: timezone) else {
      throw InterpretationError.invalidRequest
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parsed = try decodeAssistantRequest(json: text, visibleReferences: references)
    func query(_ reference: String) -> CalendarQuestion {
      CalendarQuestion(reference: reference, timezone: timezone)
    }
    func change(_ value: AssistantChange, action: VoiceIntent.Action) throws -> VoiceIntent {
      var result = VoiceIntent()
      result.action = action
      result.title = value.title
      if let date = value.date {
        guard let parsed = CalendarConversation.civilDate(date, calendar: calendar) else {
          throw InterpretationError.invalidRequest
        }
        result.newDate = parsed
      }
      result.newTime = value.timeMinutes.map(Int.init)
      result.duration = value.duration.map(Int.init)
      return result
    }
    let result: ConversationInterpretation
    switch parsed {
    case .calendar(let value):
      let detail: CalendarQuestion.Detail =
        switch value.detail {
        case .next: .next
        case .list: .list
        case .count: .count
        case .room: .room
        case .therapist: .therapist
        case .start: .start
        case .end: .end
        case .duration: .duration
        }
      let date = value.date.flatMap { CalendarConversation.civilDate($0, calendar: calendar) }
      guard value.date == nil || date != nil else { throw InterpretationError.invalidRequest }
      result = ConversationInterpretation(
        action: .calendar,
        query: CalendarQuestion(
          detail: detail, date: date, days: detail == .next && date == nil ? 90 : 1,
          reference: value.reference, afterMinutes: value.afterMinutes.map(Int.init),
          beforeMinutes: value.beforeMinutes.map(Int.init), timezone: timezone))
    case .create(let value):
      result = ConversationInterpretation(
        action: .create, change: try change(value, action: .create))
    case .update(let reference, let value):
      result = ConversationInterpretation(
        action: .update, query: query(reference), change: try change(value, action: .update))
    case .remove(let reference):
      result = ConversationInterpretation(action: .remove, query: query(reference))
    case .cancel:
      result = ConversationInterpretation(action: .cancel)
    case .help(let topic):
      result = ConversationInterpretation(action: .help, helpTopic: topic)
    case .clarify(let problem):
      result = ConversationInterpretation(action: .clarify, problem: problem)
    }
    try result.validate()
    return result
  }
}
