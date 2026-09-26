import Foundation

@main struct VictoriaPCMProbe {
  static func main() async throws {
    let expected: [Float] = [-1, -0.5, 0, 0.5, 1]
    let wave = try SpeechSampleFile.wav(SpeechPCM(samples: expected))
    let decoded = try VictoriaPCM.decode(wave)
    precondition(zip(expected, decoded.samples).allSatisfy { abs($0 - $1) < 0.0001 })
    var prefixed = Data([0, 0])
    prefixed.append(wave)
    let sliced = try VictoriaPCM.decode(prefixed.dropFirst(2))
    precondition(sliced.samples == decoded.samples)
    for offset in [0, 4, 8, 16, 20, 22, 24, 28, 32, 34, 36, 40] {
      var corrupted = wave
      corrupted[offset] ^= 255
      do {
        _ = try VictoriaPCM.decode(corrupted)
        preconditionFailure("Invalid WAV accepted")
      } catch is SpeechPCMError {}
    }
    for invalid in [Data(), wave.dropLast(), wave + Data([0, 0])] {
      do {
        _ = try VictoriaPCM.decode(invalid)
        preconditionFailure("Truncated or extended WAV accepted")
      } catch is SpeechPCMError {}
    }
    let cancelled = Task {
      while !Task.isCancelled { await Task.yield() }
      return try VictoriaPCM.decode(wave)
    }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      preconditionFailure("Cancelled decoding ran")
    } catch is CancellationError {}
    print(
      "Victoria PCM: pinned mono format, sample parity, slices, corrupt headers, truncation and cancellation passed"
    )
  }
}
