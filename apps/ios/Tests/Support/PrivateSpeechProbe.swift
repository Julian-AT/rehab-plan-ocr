#if REHA_PRIVATE_VICTORIA
  import Foundation
  import UIKit

  /// Explicit fixed-text renderer timing on the actual device. No microphone,
  /// calendar access, preferences changes, or user text in this report.
  @MainActor enum PrivateSpeechProbe {
    private static var started = false
    static func runIfRequested() async -> Bool {
      let args = ProcessInfo.processInfo.arguments
      guard let index = args.firstIndex(of: "--diagnose-speech"),
        args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1])
      else { return false }
      guard !started else { return true }
      started = true
      let idle = UIApplication.shared.isIdleTimerDisabled
      UIApplication.shared.isIdleTimerDisabled = true
      defer { UIApplication.shared.isIdleTimerDisabled = idle }
      let folder = URL.documentsDirectory.appendingPathComponent("speech-diagnostics")
      let output = folder.appendingPathComponent(id.uuidString.lowercased() + ".json")
      var cases: [[String: Any]] = []
      var report: [String: Any] = [
        "synthetic": true, "microphone_capture": false, "calendar_operations": 0,
        "voice": "victoria", "rate": 1.15, "stage": "started",
        "measurement": "renderer preparation only; not end-to-end response latency",
      ]
      func save() throws {
        report["cases"] = cases
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
          .write(
            to: output, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      }
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: output.path) else { return true }
        let renderer = VictoriaSpeechRenderer()
        renderer.setRequest(1)
        let voice = renderer.voices[0]
        func render(_ text: String, name: String) async throws {
          report["current_case"] = name
          try save()
          let result = try await renderer.render(text: text, voice: voice, rate: 1.15, request: 1)
          let time = result.preparation.components
          cases.append([
            "case": name, "characters": text.count,
            "preparation_seconds": Double(time.seconds) + Double(time.attoseconds) / 1e18,
            "audio_seconds": result.duration, "word_marks": result.marks.count,
          ])
          try save()
        }
        try await render("Hallo!", name: "cold-short-sentence")
        let fixtures = [
          "Hallo! Wie kann ich dir heute helfen?",
          "Du kannst mir Fragen zu deinen nächsten Terminen stellen, und ich schaue in deinem Kalender nach.",
          "Frühstück II beginnt um 09:15 Uhr. Dr. Muster kommt in Raum 2.14.",
        ]
        for round in 0..<2 {
          for (index, text) in fixtures.enumerated() {
            let first = ConversationReply(text).phrases[0].speech
            // Counterbalance order; whole is the previous first buffer for
            // these fixtures. Use identical normalization for both strategies.
            var whole = ConversationReply()
            whole.append(text)
            let values = [("whole", whole.speech), ("first", first)]
            for (strategy, speech) in round == 0 ? values : values.reversed() {
              try await render(speech, name: "\(round)-\(index)-\(strategy)")
            }
          }
        }
        report["stage"] = "completed"
        try save()
      } catch {
        report["stage"] = "failed"
        report["error"] = String(reflecting: error)
        try? save()
      }
      return true
    }
  }
#endif
