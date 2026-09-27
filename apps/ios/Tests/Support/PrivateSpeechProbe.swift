#if REHA_PRIVATE_VICTORIA
  import Foundation
  import RehaCore
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
        "processor_count": ProcessInfo.processInfo.activeProcessorCount,
        "system_version": UIDevice.current.systemVersion,
        "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
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
        func render(_ text: String, name: String, renderer: VictoriaSpeechRenderer, threads: Int)
          async throws
        {
          report["current_case"] = name
          try save()
          let before = ProcessInfo.processInfo.thermalState.rawValue
          let result = try await renderer.render(
            text: text, voice: renderer.voices[0], rate: 1.15, request: 1)
          let time = result.preparation.components
          cases.append([
            "case": name, "characters": text.count,
            "threads": threads, "thermal_before": before,
            "thermal_after": ProcessInfo.processInfo.thermalState.rawValue,
            "preparation_seconds": Double(time.seconds) + Double(time.attoseconds) / 1e18,
            "audio_seconds": result.duration, "word_marks": result.marks.count,
            "finite_samples": result.pcm.samples.allSatisfy(\.isFinite),
            "peak": result.pcm.samples.map { abs($0) }.max() ?? 0,
            "marks": result.marks.map { ["text": $0.text, "start": $0.start, "end": $0.end] },
          ])
          try save()
        }
        // Each variant owns one engine; release it before loading the next.
        // Latin-square ordering reduces warm-cache and thermal ordering bias.
        let fixtures = [
          "Hallo!", "Dein nächster Termin beginnt morgen um neun Uhr.",
          "Du kannst mir Fragen zu deinen nächsten Terminen stellen,",
        ]
        func variant(_ threads: Int, round: Int) async throws {
          let renderer = VictoriaSpeechRenderer(
            native: NativeSpeech.withThreads(
              modelDirectory: Bundle.main.bundleURL.appendingPathComponent("kokoro-german").path,
              threads: UInt32(threads)))
          renderer.setRequest(1)
          let start = ContinuousClock.now
          try await renderer.prepare(request: 1)
          let load = start.duration(to: .now).components
          cases.append([
            "case": "\(round)-load", "threads": threads,
            "preparation_seconds": Double(load.seconds) + Double(load.attoseconds) / 1e18,
          ])
          for (index, text) in fixtures.enumerated() {
            try await render(
              text, name: "\(round)-\(index)-prepared", renderer: renderer, threads: threads)
          }
          for (index, text) in fixtures.enumerated().reversed() {
            try await render(
              text, name: "\(round)-\(index)-warm", renderer: renderer, threads: threads)
          }
        }
        for (round, order) in [[2, 4, 6], [6, 2, 4], [4, 6, 2]].enumerated() {
          for threads in order {
            try await variant(threads, round: round)
            try await Task.sleep(for: .milliseconds(300))
          }
        }
        // Cancellation must invalidate work even when preparation loaded a
        // reusable engine. Never play a stale phrase after Stop.
        let stale = VictoriaSpeechRenderer()
        stale.setRequest(2)
        do {
          try await stale.prepare(request: 1)
          throw SystemSpeechError.invalidAudio
        } catch is CancellationError {
          report["stale_preparation_rejected"] = true
        }
        do {
          _ = try await stale.render(text: "Hallo!", voice: stale.voices[0], rate: 1.15, request: 1)
          throw SystemSpeechError.invalidAudio
        } catch is CancellationError {
          report["stale_render_rejected"] = true
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
