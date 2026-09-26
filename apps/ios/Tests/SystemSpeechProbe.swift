import AVFoundation
import Foundation

@main struct SystemSpeechProbe {
  static func reject(_ action: () throws -> Void) throws {
    do {
      try action()
      fatalError("Expected rejected audio")
    } catch is SystemSpeechError {}
  }
  @MainActor static func main() async throws {
    for rate in [16_000.0, 22_050.0, 24_000.0, 44_100.0, 48_000.0] {
      let signal = (0..<Int(rate)).map { Float(sin(Double($0) * 2 * .pi * 440 / rate)) * 0.2 }
      let result = try SystemSpeechConversion.convert(signal, rate: rate)
      precondition(abs(result.samples.count - 24_000) <= 2)
      precondition(result.samples.allSatisfy(\.isFinite))
      let rms = sqrt(
        result.samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(result.samples.count))
      precondition((0.13...0.15).contains(rms))
    }
    try reject { _ = try SystemSpeechConversion.convert([], rate: 24_000) }
    try reject { _ = try SystemSpeechConversion.convert([.nan], rate: 24_000) }
    try reject { _ = try SystemSpeechConversion.convert([0], rate: .infinity) }
    let cancelled = Task {
      while !Task.isCancelled { await Task.yield() }
      return try SystemSpeechConversion.convert([0], rate: 24_000)
    }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      fatalError("Cancelled conversion ran")
    } catch is CancellationError {}

    let text = "Grüß dich 👋 morgen"
    let collector = SpeechBufferCollector(text: text)
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_400)!
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].initialize(repeating: 0, count: 2_400)
    for word in ["Grüß", "dich", "👋", "morgen"] {
      let range = (text as NSString).range(of: word)
      collector.speechSynthesizer(
        synthesizer, willSpeakRangeOfSpeechString: range, utterance: utterance)
      // Duplicate delegate callbacks must not duplicate spoken history.
      collector.speechSynthesizer(
        synthesizer, willSpeakRangeOfSpeechString: range, utterance: utterance)
      collector.append(buffer)
    }
    precondition(!collector.finished)
    collector.speechSynthesizer(synthesizer, didFinish: utterance)
    let capture = try collector.result()
    precondition(capture.words.map(\.text) == ["Grüß", "dich", "👋", "morgen"])
    precondition(capture.words.map(\.time) == [0, 0.1, 0.2, 0.3])
    precondition(capture.samples.count == 9_600)
    collector.append(buffer)
    let completed = try collector.result()
    precondition(completed.samples.count == 9_600)
    let invalid = SpeechBufferCollector(text: "Hallo")
    invalid.speechSynthesizer(
      synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 99, length: 2),
      utterance: utterance)
    try reject { _ = try invalid.result() }

    let renderer = SystemSpeechRenderer()
    precondition(renderer.selectedVoice("missing-installed-voice") == nil)
    renderer.setRequest(9)
    if let voice = renderer.selectedVoice(nil) {
      do {
        _ = try await renderer.render(text: "Hallo", voice: voice, rate: 1, request: 8)
        fatalError("Stale generation rendered")
      } catch is CancellationError {}
      if ProcessInfo.processInfo.arguments.contains("--live") {
        let spoken =
          "Guten Morgen. Ihr nächster Termin ist um neun Uhr in Raum zwei Punkt vierzehn."
        let result = try await renderer.render(text: spoken, voice: voice, rate: 0.95, request: 9)
        precondition(result.duration > 1 && result.duration < 30)
        precondition(result.marks.count >= 10)
        precondition(
          result.marks.allSatisfy {
            $0.start >= 0 && $0.end >= $0.start && $0.end <= result.duration
          })
        precondition(result.marks.map(\.text).joined(separator: " ") == spoken)
        let pending = Task {
          try await renderer.render(
            text: String(repeating: "Guten Morgen. ", count: 80), voice: voice, rate: 1, request: 9)
        }
        await Task.yield()
        renderer.setRequest(10)
        pending.cancel()
        do {
          _ = try await pending.value
          fatalError("Cancelled synthesis returned")
        } catch is CancellationError {}
        let resumed = try await renderer.render(
          text: "Guten Morgen.", voice: voice, rate: 1, request: 10)
        precondition(!resumed.pcm.samples.isEmpty)
        print(
          "Live system voice: \(voice.id), \(result.marks.count) words, \(result.duration) seconds; cancellation/restart passed. Host evidence only."
        )
      }
    } else if ProcessInfo.processInfo.arguments.contains("--live") {
      throw SystemSpeechError.unavailable
    }
    print(
      "System speech: bounded PCM conversion, UTF-16 ranges, duplicate progress, completion, missing voice and cancellation passed."
    )
  }
}
