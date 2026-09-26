import Foundation
import RehaCore

/// Model JSON is decoded by the portable compact-schema boundary. Only this typed
/// result reaches the app; references still undergo a fresh visible-calendar query.
enum AssistantInterpretation {
  /// Structural validity is insufficient: the current utterance must support a
  /// mutation and every changed field. History and document text grant no authority.
  static func checked(_ value: ConversationInterpretation, for request: InterpretationRequest)
    -> ConversationInterpretation
  {
    func clarify(_ problem: AssistantProblem = .ambiguous) -> ConversationInterpretation {
      ConversationInterpretation(action: .clarify, problem: problem)
    }
    let intent = VoiceRules.parse(request.text, now: request.now, calendar: request.calendar)
    if intent.action == .cancel { return ConversationInterpretation(action: .cancel) }
    if VoiceRules.roomOnlyChange(request.text) == nil,
      VoiceRules.hasInvalidDate(request.text, now: request.now, calendar: request.calendar)
    {
      return clarify(.invalidDate)
    }
    let words = VoiceRules.normalized(request.text)
    let renameTitle = VoiceRules.titleOnlyRename(request.text)
    if value.action == .plan {
      guard let plan = value.plan, words.contains("plan"),
        plan.search.isEmpty || words.contains(VoiceRules.normalized(plan.search))
      else { return clarify() }
      for number in [plan.source, plan.comparison].compactMap({ $0 }) {
        guard !VoiceRules.matches("\\bplan \(number)\\b", words).isEmpty else { return clarify() }
      }
    }
    let mutation = [.create, .update, .remove].contains(value.action)
    if mutation {
      let expected: VoiceIntent.Action =
        value.action == .create ? .create : value.action == .update ? .update : .remove
      guard intent.action == expected, !intent.negatedChange else { return clarify() }
      if VoiceRules.roomOnlyChange(request.text) != nil {
        guard value.action == .update, value.change?.location == intent.location,
          value.change?.title == nil, let query = value.query,
          query.usesLastPage, query.reference == nil, query.ordinal == 0,
          query.title.isEmpty, query.excluding.isEmpty, query.date == nil,
          !query.hasTimeBounds, query.days == 1, query.offset == 0, query.calendarName == nil
        else { return clarify() }
      } else {
        guard VoiceRules.explicitMutation(words) == expected, value.change?.location == nil else {
          return clarify()
        }
      }
      if let renameTitle {
        guard value.action == .update,
          value.change?.title == renameTitle,
          let query = value.query,
          query.reference != nil || query.usesLastPage,
          query.detail == .list, query.ordinal == 0, query.days == 1, query.offset == 0,
          query.title.isEmpty, query.excluding.isEmpty, query.calendarName == nil,
          query.afterEventID == nil, query.afterEventDate == nil
        else { return clarify() }
      }
      if let change = value.change {
        guard change.newDate == intent.newDate, change.newTime == intent.newTime,
          change.duration == intent.duration
        else { return clarify() }
        if let title = change.title {
          let literal = VoiceRules.normalized(title)
          guard !literal.isEmpty,
            !VoiceRules.matches(
              "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: literal)
                + "(?![\\p{L}\\p{N}])", words
            ).isEmpty
          else { return clarify() }
          if value.action == .update, renameTitle == nil,
            VoiceRules.matches(#"\b(?:titel|namen|name|bezeichnung)\b"#, words).isEmpty
          {
            return clarify()
          }
        }
      }
    }
    if let query = value.query {
      if mutation {
        // A search target must not borrow the requested replacement date/time.
        guard query.date == intent.date else { return clarify() }
        if let minute = intent.referenceTime {
          guard query.afterMinutes == minute, query.beforeMinutes == minute + 1 else {
            return clarify()
          }
        } else if query.hasTimeBounds {
          return clarify()
        }
        if !query.title.isEmpty,
          !VoiceRules.normalized(intent.referenceText).contains(VoiceRules.normalized(query.title))
        {
          return clarify()
        }
        if query.reference == nil, query.ordinal == 0, !query.usesLastPage,
          query.date == nil, query.title.isEmpty
        {
          return clarify()
        }
      }
      if value.action == .calendar {
        if let date = VoiceRules.date(request.text, now: request.now, calendar: request.calendar),
          query.date != date
        {
          return clarify()
        }
        guard timeBoundsMatch(query, words: words) else { return clarify() }
      }
      if query.reference != nil || query.ordinal > 0 || (mutation && query.usesLastPage) {
        guard referenceMatches(query, words: words, context: request.context, mutation: mutation)
        else {
          return clarify()
        }
      }
    }
    return value
  }

  private struct ReferencedPage: Decodable {
    struct Item: Decodable {
      let reference: String
      let title: String?
    }
    let lastPage: [Item]
    enum CodingKeys: String, CodingKey { case lastPage = "last_page" }
  }

  private static func referenceMatches(
    _ query: CalendarQuestion, words: String, context: String, mutation: Bool
  )
    -> Bool
  {
    guard
      let page = try? JSONDecoder().decode(ReferencedPage.self, from: Data(context.utf8)).lastPage,
      !page.isEmpty,
      VoiceRules.matches(#"\b(?:anderen|andere|anderem|irgendeinen|irgendeinem)\b"#, words).isEmpty
    else { return false }
    let ordinals = ["erst", "zweit", "dritt", "viert", "fünft"]
    let spoken = ordinals.enumerated().filter {
      let ordinal = "\($0.element)e[nrms]?"
      return !VoiceRules.matches(
        "\\b\(ordinal) (?:termin|behandlung)\\b|\\b(?:den|dem|der|die|das|beim) \(ordinal)(?=\\s*(?:$|[.]|(?:auf|um|am|heute|morgen)\\b))",
        words
      ).isEmpty
    }
    let expected: String?
    if VoiceRules.titleOnlyRename(words) != nil || VoiceRules.roomOnlyChange(words) != nil {
      guard page.count == 1 else { return false }
      expected = page[0].reference
    } else if spoken.count == 1, let ordinal = spoken.first?.offset, page.indices.contains(ordinal)
    {
      expected = page[ordinal].reference
    } else if !spoken.isEmpty {
      return false
    } else if page.count == 1,
      !mutation
        || !VoiceRules.matches(
          #"\b(?:den|dem|der|die|das|diesen|diesem|dieser|dieses) (?:termin|behandlung)(?=\s*(?:$|[.]|(?:bitte|auf|um|am|heute|morgen|übermorgen|löschen|entfernen|verschieben|ändern)\b))"#,
          words
        ).isEmpty
    {
      expected = page[0].reference
    } else {
      let named = page.filter {
        guard let title = $0.title, !title.isEmpty else { return false }
        return !VoiceRules.matches(
          "(?<![\\p{L}\\p{N}])"
            + NSRegularExpression.escapedPattern(for: VoiceRules.normalized(title))
            + "(?![\\p{L}\\p{N}])", words
        ).isEmpty
      }
      expected = named.count == 1 ? named[0].reference : nil
    }
    guard let expected else { return false }
    if let reference = query.reference, reference != expected { return false }
    if query.ordinal > 0 {
      guard page.indices.contains(query.ordinal - 1),
        page[query.ordinal - 1].reference == expected
      else { return false }
    }
    return true
  }

  private static func timeBoundsMatch(_ query: CalendarQuestion, words: String) -> Bool {
    guard
      VoiceRules.matches(
        #"\b(?:nicht|kein\w*)\s+(?:nach|ab|vor|bis|vormittags|nachmittags)\b"#, words
      ).isEmpty
    else { return false }
    var lower = Set<Int>()
    var upper = Set<Int>()
    if !VoiceRules.matches(#"\bvormittags\b"#, words).isEmpty { upper.insert(720) }
    if !VoiceRules.matches(#"\bnachmittags\b"#, words).isEmpty {
      lower.insert(720)
      upper.insert(1080)
    }
    for match in VoiceRules.matches(
      #"\b(nach|ab|vor|bis) ([\p{L}\d:]+) uhr\b"#, words)
    {
      guard let minutes = VoiceRules.time(match[2] + " uhr") else { return false }
      if ["nach", "ab"].contains(match[1]) {
        lower.insert(minutes)
      } else {
        upper.insert(minutes)
      }
    }
    for match in VoiceRules.matches(
      #"\b(?:von|zwischen) ([\p{L}\d:]+)(?: uhr)? (?:bis|und) ([\p{L}\d:]+) uhr\b"#, words)
    {
      guard let start = VoiceRules.time(match[1] + " uhr"),
        let end = VoiceRules.time(match[2] + " uhr")
      else { return false }
      lower.insert(start)
      upper.insert(end)
    }
    return lower.count <= 1 && upper.count <= 1
      && query.afterMinutes == lower.first && query.beforeMinutes == upper.first
  }

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
      result.timezone = timezone
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
