import AVFoundation
import CFvad
import Foundation

enum LocalSpeechError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

enum InputAudioError: Error { case invalidFormat, invalidSamples, conversion, detector }

enum InputAudioConversion {
  static func validate(_ status: AVAudioConverterOutputStatus, error: NSError?) throws {
    guard status != .error, error == nil else { throw InputAudioError.conversion }
  }
}

/// Measure the actual input, before conversion or voice detection. Silence is valid.
enum InputAudioLevel {
  static func measure(_ buffer: AVAudioPCMBuffer) throws -> Double? {
    guard buffer.format.sampleRate.isFinite, buffer.format.sampleRate > 0,
      buffer.format.channelCount > 0
    else { throw InputAudioError.invalidFormat }
    guard buffer.frameLength > 0 else { return nil }
    let channels = Int(buffer.format.channelCount)
    let interleaved = buffer.format.isInterleaved
    var peakRMS = 0.0
    for channel in 0..<channels {
      var energy = 0.0
      for frame in 0..<Int(buffer.frameLength) {
        let offset = interleaved ? frame * channels + channel : frame
        let pointer = interleaved ? 0 : channel
        let sample: Double
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
          guard let data = buffer.floatChannelData else { throw InputAudioError.invalidFormat }
          sample = Double(data[pointer][offset])
        case .pcmFormatFloat64:
          let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
          guard let data = buffers[pointer].mData else { throw InputAudioError.invalidFormat }
          sample = data.assumingMemoryBound(to: Double.self)[offset]
        case .pcmFormatInt16:
          guard let data = buffer.int16ChannelData else { throw InputAudioError.invalidFormat }
          sample = Double(data[pointer][offset]) / 32768
        case .pcmFormatInt32:
          guard let data = buffer.int32ChannelData else { throw InputAudioError.invalidFormat }
          sample = Double(data[pointer][offset]) / 2_147_483_648
        default: throw InputAudioError.invalidFormat
        }
        guard sample.isFinite else { throw InputAudioError.invalidSamples }
        energy += sample * sample
      }
      // A silent stereo channel must not hide the active microphone channel.
      peakRMS = max(peakRMS, sqrt(energy / Double(buffer.frameLength)))
    }
    return min(1, pow(peakRMS * 8, 0.65))
  }
}

/// Access is serialized by the input tap. The pinned C VAD owns no audio device.
final class VoiceActivityDetector: @unchecked Sendable {
  private let detector: OpaquePointer
  let inputFormat: AVAudioFormat
  private let converter: AVAudioConverter
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
  private var samples: [Int16] = []
  init(input: AVAudioFormat) throws {
    inputFormat = input
    guard input.sampleRate > 0, input.channelCount > 0 else { throw InputAudioError.invalidFormat }
    guard let detector = fvad_new() else {
      throw LocalSpeechError.message("Die Spracherkennung konnte nicht vorbereitet werden.")
    }
    guard let converter = AVAudioConverter(from: input, to: format) else {
      fvad_free(detector)
      throw LocalSpeechError.message("Das Mikrofonformat kann nicht verarbeitet werden.")
    }
    self.detector = detector
    self.converter = converter
    fvad_set_sample_rate(detector, 16_000)
    fvad_set_mode(detector, 2)
  }
  deinit { fvad_free(detector) }
  func append(_ buffer: AVAudioPCMBuffer, frame: (Bool) -> Void) throws {
    guard buffer.format == inputFormat else { throw InputAudioError.invalidFormat }
    guard buffer.frameLength > 0 else { return }
    let capacity = AVAudioFrameCount(
      ceil(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 320)
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw InputAudioError.conversion
    }
    let input = ConverterInput(buffer)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, status in input.take(status) }
    try InputAudioConversion.validate(status, error: error)
    guard let channel = output.int16ChannelData?[0] else {
      throw InputAudioError.conversion
    }
    samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    var offset = 0
    while samples.count - offset >= 320 {
      let part = Array(samples[offset..<(offset + 320)])
      let rms = sqrt(part.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / 320)
      let decision = part.withUnsafeBufferPointer {
        fvad_process(detector, $0.baseAddress!, 320)
      }
      guard decision >= 0 else { throw InputAudioError.detector }
      frame(decision == 1 && rms > 0.003)
      offset += 320
    }
    samples.removeFirst(offset)
  }
}

/// The converter receives the tap buffer once; access to consumption state is locked.
private final class ConverterInput: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: AVAudioPCMBuffer?
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  func take(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer else {
      status.pointee = .noDataNow
      return nil
    }
    self.buffer = nil
    status.pointee = .haveData
    return buffer
  }
}
