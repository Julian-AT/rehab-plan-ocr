#if DEBUG || REHA_PROVIDER_PROBE
  import Foundation
  import RehaCore

  /// Synthetic interpretation-only observations. This type has no calendar service.
  enum InterpretationEvaluation {
    struct Fixture: Decodable {
      let runID: String
      let mode: String
      let cases: [Sample]
      enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case mode, cases
      }

      func validate(runID: String) throws {
        guard self.runID == runID, ["rules", "apple", "custom"].contains(mode),
          (1...200).contains(cases.count), Set(cases.map(\.id)).count == cases.count
        else { throw InterpretationError.invalidRequest }
        for sample in cases { _ = try sample.request() }
      }
    }
    struct Sample: Decodable {
      let id: String
      let text: String
      let today: String
      let timezone: String
      let references: [String]
      let selected: String?

      func request() throws -> InterpretationRequest {
        // The app prompt infers selection only for a single previous-page item.
        // Refuse datasets requiring context that this adapter cannot preserve.
        guard !id.isEmpty, id.utf8.count <= 128, references.count <= 64,
          Set(references).count == references.count,
          references.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
          selected == (references.count == 1 ? references.first : nil),
          let zone = TimeZone(identifier: timezone)
        else { throw InterpretationError.invalidRequest }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let now = CalendarConversation.civilDate(today, calendar: calendar) else {
          throw InterpretationError.invalidRequest
        }
        let context: [String: Any] = [
          "today": today, "timezone": timezone,
          "last_page": references.map { ["reference": $0] },
        ]
        let request = InterpretationRequest(
          text: text,
          context: String(
            decoding: try JSONSerialization.data(withJSONObject: context), as: UTF8.self),
          history: [], now: now, calendar: calendar, deadline: .now + .seconds(30))
        try request.validate()
        return request
      }
    }

    /// Preserve every app constraint. Fields not expressible in the compact model
    /// contract remain visible as extra keys, and therefore fail exact/schema checks.
    static func operation(_ value: ConversationInterpretation, sample: Sample) throws -> [String:
      Any]
    {
      var output: [String: Any] = ["action": String(describing: value.action)]
      let calendar = try sample.request().calendar
      func date(_ value: Date) -> String { CalendarConversation.day(value, calendar: calendar) }
      func time(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
      if let plan = value.plan {
        var fields: [String: Any] = ["search": plan.search]
        fields["source"] = plan.source
        fields["comparison"] = plan.comparison
        output["plan"] = fields
      }
      if let query = value.query {
        var result: [String: Any] = [:]
        if value.action == .calendar { result["detail"] = query.detail.rawValue }
        if let day = query.date { result["date"] = date(day) }
        result["reference"] = query.reference
        if query.usesLastPage, query.reference == nil, let selected = sample.selected {
          result["reference"] = selected
        } else if query.usesLastPage {
          result["uses_last_page"] = true
        }
        if let minutes = query.afterMinutes { result["after"] = time(minutes) }
        if let minutes = query.beforeMinutes { result["before"] = time(minutes) }
        let expectedDays = query.detail == .next && query.date == nil ? 90 : 1
        if query.days != expectedDays { result["days"] = query.days }
        if !query.title.isEmpty { result["title"] = query.title }
        if !query.excluding.isEmpty { result["excluding"] = query.excluding }
        result["calendar_name"] = query.calendarName
        if query.ordinal != 0 { result["ordinal"] = query.ordinal }
        if query.refinesPrevious { result["refines_previous"] = true }
        if query.offset != 0 { result["offset"] = query.offset }
        if query.timezone != sample.timezone { result["timezone"] = query.timezone }
        result["after_event_id"] = query.afterEventID
        if let day = query.afterEventDate { result["after_event_date"] = date(day) }
        if value.action != .calendar && query.detail != .list {
          result["detail"] = query.detail.rawValue
        }
        output["query"] = result
      }
      if let change = value.change {
        var result: [String: Any] = [:]
        result["title"] = change.title
        if let day = change.newDate { result["date"] = date(day) }
        if let minutes = change.newTime { result["time"] = time(minutes) }
        result["duration"] = change.duration
        result["location"] = change.location
        if change.negatedChange { result["negated"] = true }
        if !change.referenceText.isEmpty { result["reference_text"] = change.referenceText }
        result["calendar_name"] = change.calendarName
        result["reference_time"] = change.referenceTime
        if let day = change.date { result["reference_date"] = date(day) }
        if change.action.rawValue != String(describing: value.action) {
          result["action"] = change.action.rawValue
        }
        if change.timezone != sample.timezone { result["timezone"] = change.timezone }
        output["change"] = result
      }
      output["reply"] = value.reply
      if let topic = value.helpTopic { output["topic"] = String(describing: topic) }
      if let problem = value.problem {
        output["problem"] =
          switch problem {
          case .invalidDate: "invalid_date"
          case .missingDate: "missing_date"
          case .missingTime: "missing_time"
          case .missingTitle: "missing_title"
          case .missingEvent: "missing_event"
          case .ambiguous: "ambiguous"
          case .unsupported: "unsupported"
          }
      }
      return output
    }
  }
#endif
