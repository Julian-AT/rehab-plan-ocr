import Foundation

@main struct OutputAudioProbe {
  static func fixture(_ samples: [Int16]) -> Data {
    var wav = Data("RIFF".utf8)
    func append<T: FixedWidthInteger>(_ value: T) {
      var value = value.littleEndian
      withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
    }
    append(UInt32(36 + samples.count * 2))
    wav.append(Data("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(24_000))
    append(UInt32(48_000))
    append(UInt16(2))
    append(UInt16(16))
    wav.append(Data("data".utf8))
    append(UInt32(samples.count * 2))
    for sample in samples { append(sample) }
    return wav
  }
  static func reject(_ wav: Data) throws {
    do {
      _ = try SpeechPCM.decode(wav)
      preconditionFailure("Malformed or overlong WAV accepted")
    } catch SpeechPCMError.invalidFile {}
  }
  static func main() async throws {
    let wav = fixture([.min, -1, 0, 1, .max])
    let pcm = try SpeechPCM.decode(wav)
    precondition(pcm.samples == [-1, -1 / 32768, 0, 1 / 32768, 32767 / 32768])
    for offset in [0, 4, 8, 12, 16, 20, 22, 24, 28, 32, 34, 36, 40] {
      var invalid = wav
      invalid[offset] ^= 1
      try reject(invalid)
    }
    try reject(wav.dropLast())
    try reject(wav + Data([0]))
    try reject(Data())
    try reject(Data(repeating: 0, count: 45 + SpeechPCM.maximumFrames * 2))
    let canceled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try SpeechPCM.decode(wav)
    }
    do {
      _ = try await canceled.value
      preconditionFailure("Canceled decoding delivered audio")
    } catch is CancellationError {}
    print(
      "Output PCM regressions passed: exact samples, complete WAV contract, bounds and cancellation."
    )
  }
}
