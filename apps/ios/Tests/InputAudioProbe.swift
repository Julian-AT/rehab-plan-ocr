import AVFoundation
import Foundation

@main struct InputAudioProbe {
  static func main() throws {
    for rate in [16_000.0, 44_100, 48_000] {
      for channels: AVAudioChannelCount in [1, 2] {
        for interleaved in [false, true] {
          let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: channels, interleaved: interleaved)!
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 50))!
          buffer.frameLength = buffer.frameCapacity
          let detector = try VoiceActivityDetector(input: format)
          var frames = 0
          for _ in 0..<10 {
            for frame in 0..<Int(buffer.frameLength) {
              for channel in 0..<Int(channels) {
                buffer.floatChannelData![interleaved ? 0 : channel][
                  interleaved ? frame * Int(channels) + channel : frame] =
                  channel == Int(channels) - 1
                  ? Float(0.1 * sin(2 * .pi * 220 * Double(frame) / rate)) : 0
              }
            }
            let level = try InputAudioLevel.measure(buffer)
            precondition(level! > 0.5)
            try detector.append(buffer) { _ in frames += 1 }
          }
          precondition(frames >= 8, "Conversion must produce 20 ms frames: \(rate), \(channels)")
          for data in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            memset(data.mData!, 0, Int(data.mDataByteSize))
          }
          let silence = try InputAudioLevel.measure(buffer)
          precondition(silence == 0, "Digital silence is valid input")
          buffer.frameLength = 0
          let empty = try InputAudioLevel.measure(buffer)
          precondition(empty == nil, "Empty buffers do not start recording")
        }
      }
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let invalid = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960)!
    invalid.frameLength = 960
    invalid.floatChannelData![0][0] = .nan
    do {
      _ = try InputAudioLevel.measure(invalid)
      preconditionFailure("NaN accepted")
    } catch InputAudioError.invalidSamples {}
    let detector = try VoiceActivityDetector(
      input: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!)
    do {
      try detector.append(invalid) { _ in }
      preconditionFailure("Format change silently accepted")
    } catch InputAudioError.invalidFormat {}
    for (status, error) in [
      (AVAudioConverterOutputStatus.error, nil),
      (.haveData, NSError(domain: NSOSStatusErrorDomain, code: -50)),
    ] {
      do {
        try InputAudioConversion.validate(status, error: error)
        preconditionFailure("Conversion error swallowed")
      } catch InputAudioError.conversion {}
    }
    try InputAudioConversion.validate(.inputRanDry, error: nil)
    var watch = InputBufferWatchdog()
    watch.start(at: 0)
    precondition(watch.check(at: 1.99) == .wait)
    precondition(watch.check(at: 2) == .restart)
    watch.start(at: 2)
    precondition(watch.check(at: 4) == .fail)
    watch = InputBufferWatchdog()
    watch.start(at: 0)
    for time in 1...10 {
      watch.received(at: Double(time))  // Includes silent but valid PCM buffers.
      precondition(watch.check(at: Double(time)) == .wait)
    }
    precondition(watch.check(at: 12) == .restart)
    watch.cancel()  // Stopp / background / interruption invalidates pending retry.
    precondition(watch.check(at: 100) == .wait)
    configurationRecovery()
    print(
      "PCM: 16/44.1/48 kHz mono/stereo, interleaving, silence, empty and corrupt buffers, format change, one retry and cancellation passed"
    )
  }
  private static func configurationRecovery() {
    var recovery = AudioConfigurationRecovery()
    recovery.start()
    // iPhone trace: first notification ~150 ms after engine start, no buffers.
    recovery.changed(at: 0.15)
    recovery.changed(at: 0.20)  // Duplicate must not postpone recovery indefinitely.
    precondition(recovery.check(at: 0.29, running: false, matchingFormats: true) == .wait)
    precondition(recovery.check(at: 0.31, running: false, matchingFormats: true) == .restart)
    // A late notification after restarting the same healthy graph is harmless.
    recovery.changed(at: 0.4)
    precondition(recovery.check(at: 0.6, running: true, matchingFormats: true) == .none)
    recovery.changed(at: 0.7)
    precondition(recovery.check(at: 0.9, running: false, matchingFormats: true) == .fail)

    recovery.start()
    recovery.changed(at: 0, needsNewInput: true)
    precondition(recovery.check(at: 0.2, running: true, matchingFormats: true) == .restart)
    recovery.received(at: 0.3)
    recovery.received(at: 2)  // Isolated buffers do not reset the retry budget.
    recovery.changed(at: 2)
    precondition(recovery.check(at: 2.2, running: true, matchingFormats: false) == .fail)
    for time in stride(from: 2.3, through: 3.5, by: 0.1) { recovery.received(at: time) }
    recovery.changed(at: 3.6)
    precondition(recovery.check(at: 3.8, running: true, matchingFormats: false) == .restart)

    recovery.changed(at: 4)
    recovery.cancel()  // Stopp, background and interruptions invalidate deferred work.
    recovery.changed(at: 4.1)
    precondition(!recovery.isPending)
    precondition(recovery.check(at: 100, running: false, matchingFormats: false) == .none)
    print(
      "Audio configuration: startup trace, coalescing, healthy graph, format changes, stable buffers and cancellation passed"
    )
  }
}
