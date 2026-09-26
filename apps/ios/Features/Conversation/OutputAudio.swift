import Foundation

/// The local Rust renderer emits only canonical 24 kHz mono PCM16 WAV files.
/// Validate lengths and format before allocation; never guess or truncate audio.
struct SpeechPCM: Sendable {
  static let sampleRate = 24_000
  static let maximumFrames = sampleRate * 300
  let samples: [Float]

  static func decode(_ wav: Data) throws -> SpeechPCM {
    try Task.checkCancellation()
    guard wav.count >= 46, wav.count <= 44 + maximumFrames * 2 else {
      throw SpeechPCMError.invalidFile
    }
    return try wav.withUnsafeBytes { raw in
      func u16(_ offset: Int) -> UInt16 {
        UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
      }
      func u32(_ offset: Int) -> UInt32 {
        UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
      }
      guard u32(0) == 0x4646_4952, u32(8) == 0x4556_4157,
        u32(12) == 0x2074_6D66, u32(36) == 0x6174_6164,
        Int(u32(4)) == wav.count - 8, u32(16) == 16,
        u16(20) == 1, u16(22) == 1, u32(24) == sampleRate,
        u32(28) == sampleRate * 2, u16(32) == 2, u16(34) == 16,
        Int(u32(40)) == wav.count - 44, (wav.count - 44).isMultiple(of: 2)
      else { throw SpeechPCMError.invalidFile }
      let count = (wav.count - 44) / 2
      var samples = [Float](repeating: 0, count: count)
      for index in samples.indices {
        if index.isMultiple(of: 16_384) { try Task.checkCancellation() }
        samples[index] = Float(Int16(bitPattern: u16(44 + index * 2))) / 32768
      }
      return SpeechPCM(samples: samples)
    }
  }
}

enum SpeechPCMError: LocalizedError {
  case invalidFile
  var errorDescription: String? { "Die Sprachdatei ist ungültig." }
}
