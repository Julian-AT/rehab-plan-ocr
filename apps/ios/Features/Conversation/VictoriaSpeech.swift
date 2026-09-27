import Foundation

#if REHA_PRIVATE_VICTORIA
  import Foundation
  import RehaCore

  /// The user's pinned local voice. NativeSpeech serializes inference and
  /// cancels stale requests; SpeechOutput still owns playback and heard words.
  @MainActor final class VictoriaSpeechRenderer: LocalSpeechRendering {
    let preferenceKey = "voice.neural.id"
    let voices = [LocalVoice(id: "victoria", name: "Victoria", language: "de-DE")]
    private let native: any NativeSpeechProtocol
    private var generation: UInt64 = 0
    init(native: (any NativeSpeechProtocol)? = nil) {
      self.native =
        native
        ?? NativeSpeech(
          modelDirectory: Bundle.main.bundleURL.appendingPathComponent("kokoro-german").path)
    }
    func selectedVoice(_ identifier: String?) -> LocalVoice? {
      guard identifier == nil || identifier == "victoria" else { return nil }
      return voices.first
    }
    func setRequest(_ request: UInt64) {
      generation = request
      native.setRequest(request: request)
    }
    func prepare(request: UInt64) async throws {
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      try await native.prepare(request: request)
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
    }
    func render(text: String, voice: LocalVoice, rate: Float, request: UInt64) async throws
      -> RenderedSpeech
    {
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      guard voice == voices[0], !text.isEmpty, text.utf16.count <= 4_000,
        rate.isFinite, (0.75...1.25).contains(rate)
      else { throw SystemSpeechError.unavailable }
      let started = ContinuousClock.now
      let result = try await native.renderTimed(
        text: text, voice: voice.id, speed: rate, request: request)
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      // The pinned renderer emits a canonical mono PCM16 WAV, never a path or
      // compressed media. Decode off the UI executor and reject malformed audio.
      let pcm = try await Task.detached(priority: .userInitiated) {
        try VictoriaPCM.decode(result.audio)
      }.value
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      let duration = Double(pcm.samples.count) / Double(SpeechPCM.sampleRate)
      guard result.duration.isFinite, abs(result.duration - duration) < 0.001,
        !result.marks.isEmpty,
        result.marks.allSatisfy({
          !$0.text.isEmpty && $0.start.isFinite && $0.end.isFinite
            && $0.start >= 0 && $0.end >= $0.start && $0.end <= duration + 0.001
        }), zip(result.marks, result.marks.dropFirst()).allSatisfy({ $0.start <= $1.start })
      else { throw SystemSpeechError.missingProgress }
      return RenderedSpeech(
        pcm: pcm,
        marks: result.marks.map { OutputWord(text: $0.text, start: $0.start, end: $0.end) },
        voice: voice, preparation: started.duration(to: .now))
    }
  }
#endif

enum VictoriaPCM {
  static func decode(_ data: Data) throws -> SpeechPCM {
    try Task.checkCancellation()
    guard data.count >= 46, data.count <= 44 + SpeechPCM.maximumFrames * 2 else {
      throw SpeechPCMError.invalidFile
    }
    func bytes(_ offset: Int, _ count: Int) -> Data {
      let start = data.startIndex + offset
      return data.subdata(in: start..<(start + count))
    }
    func number(_ offset: Int, _ count: Int) -> UInt32 {
      (0..<count).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + offset + $1]) << ($1 * 8) }
    }
    guard bytes(0, 4) == Data("RIFF".utf8), bytes(8, 8) == Data("WAVEfmt ".utf8),
      number(4, 4) == data.count - 8, number(16, 4) == 16,
      number(20, 2) == 1, number(22, 2) == 1,
      number(24, 4) == SpeechPCM.sampleRate, number(28, 4) == SpeechPCM.sampleRate * 2,
      number(32, 2) == 2, number(34, 2) == 16,
      bytes(36, 4) == Data("data".utf8), number(40, 4) == data.count - 44,
      (data.count - 44).isMultiple(of: 2)
    else { throw SpeechPCMError.invalidFile }
    let samples: [Float] = try data.withUnsafeBytes { bytes in
      let count = (bytes.count - 44) / 2
      return try Array(unsafeUninitializedCapacity: count) { output, initialized in
        // PCM16 may begin at an unaligned address (including Data slices).
        // Pointers stay inside this synchronous closure and never cross tasks.
        for index in 0..<count {
          if index.isMultiple(of: 4096) { try Task.checkCancellation() }
          let sample = bytes.loadUnaligned(fromByteOffset: 44 + index * 2, as: Int16.self)
          output[index] = Float(Int16(littleEndian: sample)) / 32768
        }
        initialized = count
      }
    }
    return SpeechPCM(samples: samples)
  }
}
