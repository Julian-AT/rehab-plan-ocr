#if REHA_PRIVATE_VICTORIA
  import Foundation
  import FoundationModels
  import UIKit

  /// Explicit launch-only diagnostic using fixed synthetic input. It opens no
  /// calendar, microphone or app database and never records the user's dialogue.
  @MainActor enum PrivateAssistantProbe {
    @Generable struct ShortReply { var reply: String }
    private static var started = false
    static func runIfRequested() async -> Bool {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--diagnose-assistant"),
        arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1])
      else { return false }
      guard !started else { return true }
      started = true
      let idleTimer = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
      defer { UIApplication.shared.isIdleTimerDisabled = idleTimer }
      let folder = URL.documentsDirectory.appendingPathComponent("assistant-diagnostics")
      let output = folder.appendingPathComponent(id.uuidString.lowercased() + ".json")
      var cases: [[String: Any]] = []
      var report: [String: Any] = [
        "synthetic": true, "calendar_operations": 0, "microphone_capture": false,
        "run_id": id.uuidString.lowercased(), "stage": "started",
      ]
      func save() throws {
        report["cases"] = cases
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
          .write(
            to: output, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
      func observe(_ name: String, operation: () async throws -> [String: Any]) async throws {
        report["current_case"] = name
        try save()
        let start = ContinuousClock.now
        var result: [String: Any] = ["case": name]
        do {
          result["result"] = try await operation()
          result["status"] = "completed"
        } catch {
          result["status"] = "failed"
          result["failure_code"] = InterpretationDiagnostics.failure(error)
          // Synthetic requests only, kept in this explicit private report.
          result["error"] = String(String(reflecting: error).prefix(4_000))
        }
        let elapsed = start.duration(to: .now).components
        result["seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        cases.append(result)
        try save()
      }
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: output.path) else { return true }
        let provider = CalendarUnderstandingSession()
        report["availability"] = String(describing: provider.availability)
        try save()
        guard provider.availability == .available else {
          report["stage"] = "unavailable"
          try save()
          return true
        }
        try await observe("plain-greeting") {
          let reply = try await LanguageModelSession(instructions: "Antworte kurz auf Deutsch.")
            .respond(
              to: "Hallo", options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 128)
            )
          return ["reply": reply.content]
        }
        try await observe("guided-greeting") {
          let reply = try await LanguageModelSession(instructions: "Antworte kurz auf Deutsch.")
            .respond(
              to: "Hallo", generating: ShortReply.self,
              options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 128))
          return ["reply": reply.content.reply]
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let now = CalendarConversation.civilDate("2031-05-15", calendar: calendar)!
        let context =
          #"{"today":"2031-05-15","timezone":"Europe/Vienna","last_page":[],"last_discussed_date":"","plan_sources":[]}"#
        let router = InterpretationRouter(generation: provider)
        for text in [
          "Hallo", "Wie geht es dir?", "Was kannst du?",
          "Wann habe ich morgen meinen ersten Termin?",
        ] {
          try await observe(text) {
            let result = try await router.interpret(
              InterpretationRequest(
                text: text, context: context, history: [], now: now,
                calendar: calendar, deadline: .now + .seconds(30)))
            return [
              "action": InterpretationDiagnostics.action(result.value),
              "reply": result.value.reply ?? "",
              "query": result.value.query.map { String(describing: $0) } ?? "",
            ]
          }
        }
        report["stage"] = "completed"
        try save()
      } catch {
        report["stage"] = "failed"
        report["failure_code"] = InterpretationDiagnostics.failure(error)
        try? save()
      }
      return true
    }
  }
#endif
