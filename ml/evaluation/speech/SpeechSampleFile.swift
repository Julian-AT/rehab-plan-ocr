import Foundation

/// Serialize the app renderer's immutable 24 kHz mono samples for local listening.
/// PCM16 quantization clips to the representable range; no gain normalization is applied.
enum SpeechSampleFile {
  static func wav(_ pcm: SpeechPCM) throws -> Data {
    guard !pcm.samples.isEmpty, pcm.samples.count <= SpeechPCM.maximumFrames,
      pcm.samples.allSatisfy(\.isFinite)
    else { throw SpeechPCMError.invalidFile }
    let samples = pcm.samples.map { value in
      Int16((max(-1, min(1, value)) * 32_767).rounded()).littleEndian
    }
    let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
    var data = Data()
    func number<T: FixedWidthInteger>(_ value: T) {
      var littleEndian = value.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: "RIFF".utf8)
    number(byteCount + 36)
    data.append(contentsOf: "WAVEfmt ".utf8)
    number(UInt32(16))
    number(UInt16(1))
    number(UInt16(1))
    number(UInt32(SpeechPCM.sampleRate))
    number(UInt32(SpeechPCM.sampleRate * 2))
    number(UInt16(2))
    number(UInt16(16))
    data.append(contentsOf: "data".utf8)
    number(byteCount)
    samples.withUnsafeBytes { data.append(contentsOf: $0) }
    return data
  }
}
