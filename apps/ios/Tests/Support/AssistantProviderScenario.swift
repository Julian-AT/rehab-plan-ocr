#if DEBUG && REHA_CUSTOM_ASSISTANT_TRIAL && targetEnvironment(simulator)
  import Foundation

  /// Runs the app's actual selected provider and typed boundary with invented
  /// facts. No NativeApplication or voice/audio session is opened by this probe.
  @MainActor enum AssistantProviderScenario {
    private static var started = false
    static func runIfRequested() async -> Bool {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--assistant-provider-probe"),
        arguments.indices.contains(index + 1), let uuid = UUID(uuidString: arguments[index + 1])
      else { return false }
      guard !started else { return true }
      started = true
      let output = URL.documentsDirectory.appendingPathComponent("assistant-provider-result.json")
      var report: [String: Any] = [
        "run_id": uuid.uuidString.lowercased(), "qualified": false,
        "calendar_operations": 0, "stage": "started",
      ]
      func save() throws {
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
          .write(to: output, options: .atomic)
      }
      do {
        try save()
        if arguments.contains("--assistant-evaluation-fixture") {
          let input = URL.documentsDirectory.appendingPathComponent(
            "assistant-evaluation-input.json")
          let data = try Data(contentsOf: input)
          guard data.count <= 1_048_576 else { throw InterpretationError.invalidRequest }
          let fixture = try JSONDecoder().decode(InterpretationEvaluation.Fixture.self, from: data)
          try fixture.validate(runID: uuid.uuidString.lowercased())
          let provider: any InterpretationProvider =
            switch fixture.mode {
            case "rules": CalendarRulesProvider()
            case "apple": AssistantProviderSelection.make(arguments: [])
            default: AssistantProviderSelection.make(arguments: ["--assistant-model-trial"])
            }
          defer { provider.discard() }
          let router = InterpretationRouter(generation: provider)
          report["mode"] = fixture.mode
          report["model_identity"] = provider.identity.model
          report["provider"] = provider.identity.provider
          report["availability"] = String(describing: provider.availability)
          var cases: [[String: Any]] = []
          for sample in fixture.cases {
            report["stage"] = "interpreting"
            report["case_id"] = sample.id
            try save()
            let request = try sample.request()
            let started = ContinuousClock.now
            var observation: [String: Any] = ["id": sample.id]
            do {
              if fixture.mode == "rules",
                router.rules.match(sample.text, now: request.now, calendar: request.calendar) == nil
              {
                observation["status"] = "no_match"
              } else {
                let result = try await router.interpret(request)
                observation["status"] = "interpreted"
                observation["provider"] = result.identity.provider
                observation["model_identity"] = result.identity.model
                observation["operation"] = try InterpretationEvaluation.operation(
                  result.value, sample: sample)
              }
            } catch InterpretationError.unavailable(let reason) {
              observation["status"] = "unavailable"
              observation["reason"] = reason
            } catch {
              observation["status"] = "error"
              observation["error"] = String(describing: error)
            }
            let elapsed = started.duration(to: .now).components
            observation["interpretation_seconds"] =
              Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            cases.append(observation)
            report["cases"] = cases
            try save()
          }
          report["stage"] = "evaluated"
          try save()
          return true
        }
        let provider = AssistantProviderSelection.make()
        guard provider.identity.provider == "custom-qwen-trial",
          provider.availability == .available
        else { throw InterpretationError.unavailable("Custom trial was not selected") }
        defer { provider.discard() }
        let router = InterpretationRouter(generation: provider)
        let context =
          #"{"today":"2031-05-15","timezone":"Europe/Vienna","last_page":[{"reference":"termin-1"}]}"#
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let now = CalendarConversation.civilDate("2031-05-15", calendar: calendar)!
        func request(_ text: String) -> InterpretationRequest {
          InterpretationRequest(
            text: text, context: context, history: [], now: now, calendar: calendar,
            deadline: .now + .seconds(30))
        }
        let simple = try await router.interpret(request("Termine morgen"))
        guard simple.identity.provider == "complete-rules" else {
          throw InterpretationError.invalidRequest
        }
        report["rules_passed"] = true
        report["model_identity"] = provider.identity.model
        var cases: [[String: Any]] = []
        for (id, text) in [
          ("correct-date-0000", "Nicht morgen, sondern übermorgen: Welche Termine habe ich da?"),
          ("room-follow-up-0000", "Und der Raum dazu?"),
        ] {
          report["stage"] = "interpreting"
          report["case_id"] = id
          try save()
          let result = try await router.interpret(request(text))
          guard result.identity.provider == "custom-qwen-trial" else {
            throw InterpretationError.invalidRequest
          }
          var value: [String: Any] = ["id": id, "action": String(describing: result.value.action)]
          if let query = result.value.query {
            value["detail"] = query.detail.rawValue
            value["reference"] = query.reference
            if let date = query.date { value["date"] = calendarDay(date, calendar: calendar) }
          }
          if let change = result.value.change {
            if let date = change.newDate {
              value["change_date"] = calendarDay(date, calendar: calendar)
            }
            value["change_title"] = change.title
            value["change_time"] = change.newTime
            value["change_duration"] = change.duration
          }
          cases.append(value)
          report["cases"] = cases
          try save()
        }
        report["stage"] = "passed"
        try save()
      } catch {
        report["stage"] = "failed"
        report["error"] = String(describing: error)
        try? save()
      }
      return true
    }

    private static func calendarDay(_ date: Date, calendar: Calendar) -> String {
      let parts = calendar.dateComponents([.year, .month, .day], from: date)
      return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
  }
#endif
