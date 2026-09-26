import AVFoundation
import Foundation
import os

struct LocalVoice: Identifiable, Sendable, Equatable {
  let id: String
  let name: String
  let language: String
}

struct OutputWord: Sendable {
  let text: String
  let start: Double
  let end: Double
}

struct RenderedSpeech: Sendable {
  let pcm: SpeechPCM
  let marks: [OutputWord]
  let voice: LocalVoice
  let preparation: Duration
  var duration: Double { Double(pcm.samples.count) / Double(SpeechPCM.sampleRate) }
}

/// Prepared text enters here; playback, progress and interruption remain owned
/// by SpeechOutput and its shared microphone/output graph.
@MainActor protocol LocalSpeechRendering: AnyObject {
  var preferenceKey: String { get }
  var voices: [LocalVoice] { get }
  func selectedVoice(_ identifier: String?) -> LocalVoice?
  func render(text: String, voice: LocalVoice, rate: Float, request: UInt64) async throws
    -> RenderedSpeech
  func setRequest(_ request: UInt64)
}

extension LocalSpeechRendering {
  var preferenceKey: String { "voice.system.id" }
}

enum SystemSpeechError: LocalizedError {
  case unavailable, invalidAudio, missingProgress, timeout
  var errorDescription: String? {
    switch self {
    case .unavailable:
      "Eine deutsche Systemstimme ist nicht verfügbar. Bitte in den iPhone-Einstellungen eine deutsche Stimme laden."
    case .invalidAudio: "Die Systemstimme hat keine vollständige Sprachaufnahme geliefert."
    case .missingProgress: "Der Wortfortschritt der Systemstimme ist nicht verfügbar."
    case .timeout: "Die Vorbereitung der Stimme dauert zu lange. Bitte erneut versuchen."
    }
  }
}

/// Only enumerated voices are used. Asset installation is a system setup step;
/// a missing selected voice is reported instead of silently changing identity.
@MainActor final class SystemSpeechRenderer: LocalSpeechRendering {
  private var generation: UInt64 = 0
  private var active: [UUID: AVSpeechSynthesizer] = [:]

  var voices: [LocalVoice] {
    AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("de-") }
      .sorted {
        // Prefer the standard German voice family over novelty voices. Human
        // comparison may select another installed voice without changing text.
        let a = $0.identifier.hasPrefix("com.apple.voice.")
        let b = $1.identifier.hasPrefix("com.apple.voice.")
        if a != b { return a }
        if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
        return $0.identifier < $1.identifier
      }.map { LocalVoice(id: $0.identifier, name: $0.name, language: $0.language) }
  }

  func selectedVoice(_ identifier: String?) -> LocalVoice? {
    let available = voices
    if let identifier { return available.first { $0.id == identifier } }
    return available.first
  }

  func setRequest(_ request: UInt64) {
    generation = request
    let previous = active.values
    active.removeAll()
    for synthesizer in previous { synthesizer.stopSpeaking(at: .immediate) }
  }

  func render(text: String, voice: LocalVoice, rate: Float, request: UInt64) async throws
    -> RenderedSpeech
  {
    try Task.checkCancellation()
    guard generation == request else { throw CancellationError() }
    guard !text.isEmpty, text.utf16.count <= 4_000, rate.isFinite, (0.75...1.25).contains(rate),
      voices.contains(voice), let nativeVoice = AVSpeechSynthesisVoice(identifier: voice.id)
    else { throw SystemSpeechError.unavailable }
    let started = ContinuousClock.now
    let id = UUID()
    let synthesizer = AVSpeechSynthesizer()
    let collector = SpeechBufferCollector(text: text)
    synthesizer.delegate = collector
    active[id] = synthesizer
    defer {
      active.removeValue(forKey: id)
      synthesizer.stopSpeaking(at: .immediate)
      synthesizer.delegate = nil
    }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = nativeVoice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
    synthesizer.write(utterance) { collector.append($0) }
    while !collector.finished {
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      guard started.duration(to: .now) < .seconds(30) else { throw SystemSpeechError.timeout }
      try await Task.sleep(for: .milliseconds(10))
    }
    try Task.checkCancellation()
    guard generation == request else { throw CancellationError() }
    let captured = try collector.result()
    let conversion = Task.detached(priority: .userInitiated) {
      try SystemSpeechConversion.convert(captured.samples, rate: captured.rate)
    }
    let pcm = try await withTaskCancellationHandler {
      try await conversion.value
    } onCancel: {
      conversion.cancel()
    }
    try Task.checkCancellation()
    guard generation == request else { throw CancellationError() }
    let duration = Double(pcm.samples.count) / Double(SpeechPCM.sampleRate)
    let marks = captured.words.enumerated().map { index, word in
      OutputWord(
        text: word.text, start: min(duration, word.time),
        end: min(
          duration, index + 1 < captured.words.count ? captured.words[index + 1].time : duration))
    }
    return RenderedSpeech(
      pcm: pcm, marks: marks, voice: voice, preparation: started.duration(to: .now))
  }
}

/// AVSpeech's built-in voices deliver willSpeakRange while writing PCM but do
/// not necessarily supply marker callbacks. Capture the current PCM boundary
/// for each UTF-16 word range. This is buffer-boundary progress, not phoneme
/// alignment; callbacks and bytes are serialized by this lock. No AV buffer
/// escapes its callback and no mutable platform object crosses an actor.
final class SpeechBufferCollector: NSObject, AVSpeechSynthesizerDelegate, Sendable {
  struct Word: Sendable {
    let text: String
    let time: Double
  }
  struct Capture: Sendable {
    var samples: [Float] = []
    var rate = 0.0
    var words: [Word] = []
    var ranges: Set<NSRange> = []
    var completed = false
    var error: SystemSpeechError?
  }
  private let text: String
  private let state = OSAllocatedUnfairLock(initialState: Capture())
  init(text: String) { self.text = text }
  var finished: Bool { state.withLock { $0.completed || $0.error != nil } }

  func append(_ buffer: AVAudioBuffer) {
    guard let pcm = buffer as? AVAudioPCMBuffer else {
      state.withLock { $0.error = .invalidAudio }
      return
    }
    let frames = Int(pcm.frameLength)
    if frames == 0 { return }  // didFinish follows the final word callback.
    let rate = pcm.format.sampleRate
    guard rate.isFinite, (8_000...192_000).contains(rate),
      pcm.format.channelCount == 1, pcm.format.commonFormat == .pcmFormatFloat32,
      frames <= 192_000, let channel = pcm.floatChannelData?[0]
    else {
      state.withLock { $0.error = .invalidAudio }
      return
    }
    let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
    guard samples.allSatisfy(\.isFinite) else {
      state.withLock { $0.error = .invalidAudio }
      return
    }
    state.withLock { capture in
      guard !capture.completed, capture.error == nil else { return }
      guard capture.rate == 0 || capture.rate == rate,
        capture.samples.count + samples.count <= Int(rate * 300)
      else {
        capture.error = .invalidAudio
        return
      }
      capture.rate = rate
      capture.samples.append(contentsOf: samples)
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
    utterance: AVSpeechUtterance
  ) {
    guard let swiftRange = Range(range, in: text) else {
      state.withLock { $0.error = .missingProgress }
      return
    }
    let word = String(text[swiftRange])
    state.withLock { capture in
      guard !capture.completed, capture.error == nil, capture.ranges.insert(range).inserted else {
        return
      }
      capture.words.append(
        Word(text: word, time: capture.rate == 0 ? 0 : Double(capture.samples.count) / capture.rate)
      )
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    state.withLock { $0.completed = true }
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    state.withLock { $0.error = .invalidAudio }
  }
  func result() throws -> Capture {
    try state.withLock { capture in
      if let error = capture.error { throw error }
      guard capture.completed, !capture.samples.isEmpty, capture.rate > 0 else {
        throw SystemSpeechError.invalidAudio
      }
      guard !capture.words.isEmpty else { throw SystemSpeechError.missingProgress }
      return capture
    }
  }
}

enum SystemSpeechConversion {
  static func convert(_ samples: [Float], rate: Double) throws -> SpeechPCM {
    try Task.checkCancellation()
    guard rate.isFinite, (8_000...192_000).contains(rate), !samples.isEmpty,
      Double(samples.count) / rate <= 300, samples.allSatisfy(\.isFinite)
    else { throw SystemSpeechError.invalidAudio }
    if rate == Double(SpeechPCM.sampleRate) { return SpeechPCM(samples: samples) }
    guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
      let outputFormat = AVAudioFormat(
        standardFormatWithSampleRate: Double(SpeechPCM.sampleRate), channels: 1),
      let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
      let output = AVAudioPCMBuffer(
        pcmFormat: outputFormat, frameCapacity: 4_096)
    else { throw SystemSpeechError.invalidAudio }
    let input = OSAllocatedUnfairLock(initialState: (offset: 0, failed: false))
    var converted: [Float] = []
    while true {
      try Task.checkCancellation()
      output.frameLength = 0
      var error: NSError?
      let status = converter.convert(to: output, error: &error) { requested, status in
        let range = input.withLock { state in
          let end = min(samples.count, state.offset + Int(requested))
          defer { state.offset = end }
          if requested == 0 && state.offset < samples.count { state.failed = true }
          return state.offset..<end
        }
        guard !range.isEmpty else {
          status.pointee = .endOfStream
          return nil
        }
        // The input format is reconstructed here; no non-Sendable AV object is
        // captured by the converter's callback.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)),
          let channel = buffer.floatChannelData?[0]
        else {
          // AVAudioConverter has no input-error status. Remember allocation
          // failure so its end-of-stream result cannot accept partial speech.
          input.withLock { $0.failed = true }
          status.pointee = .endOfStream
          return nil
        }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
          channel.update(
            from: source.baseAddress!.advanced(by: range.lowerBound), count: range.count)
        }
        status.pointee = .haveData
        return buffer
      }
      guard !input.withLock({ $0.failed }), error == nil, status != .error,
        converted.count + Int(output.frameLength) <= SpeechPCM.maximumFrames,
        let values = output.floatChannelData?[0]
      else { throw SystemSpeechError.invalidAudio }
      converted.append(
        contentsOf: UnsafeBufferPointer(start: values, count: Int(output.frameLength)))
      if status == .endOfStream { break }
      guard status == .haveData, output.frameLength > 0 else {
        throw SystemSpeechError.invalidAudio
      }
    }
    guard !converted.isEmpty, converted.allSatisfy(\.isFinite) else {
      throw SystemSpeechError.invalidAudio
    }
    return SpeechPCM(samples: converted)
  }
}
