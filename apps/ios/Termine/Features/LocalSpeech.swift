import AVFoundation
import AppleServices
@preconcurrency import Speech
import SwiftUI

/// The tap serializes conversion; the lock also protects request swaps and pre-roll.
/// Metering always reads the original buffer, independently of the VAD converter.
private final class SpeechInput: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var ring: [AVAudioPCMBuffer] = []
  private var detector: VoiceActivityDetector?
  private var audioTime = 0.0
  private var vadTime = 0.0
  private var published = 0.0
  private var frames: [AudioActivity] = []
  private var failed = false
  let frame: @Sendable (AudioActivityBatch) -> Void
  init(frame: @escaping @Sendable (AudioActivityBatch) -> Void) { self.frame = frame }
  func replace(_ next: SFSpeechAudioBufferRecognitionRequest?, preRoll: Bool = false) -> Double {
    lock.lock()
    defer { lock.unlock() }
    request?.endAudio()
    request = next
    if preRoll { for buffer in ring { next?.append(buffer) } }
    return audioTime
  }
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard !failed else { return }
    var level = 0.0
    do {
      guard buffer.format.sampleRate.isFinite, buffer.format.sampleRate > 0,
        buffer.format.channelCount > 0, buffer.frameLength > 0
      else {
        throw LocalSpeechError.message(
          "Das Mikrofon liefert kein gültiges Audiosignal. Bitte erneut starten.")
      }
      let count = Int(buffer.frameLength)
      var sum = 0.0
      if let samples = buffer.floatChannelData?[0] {
        for i in 0..<count { sum += pow(Double(samples[i * buffer.stride]), 2) }
      } else if let samples = buffer.int16ChannelData?[0] {
        for i in 0..<count { sum += pow(Double(samples[i * buffer.stride]) / 32768, 2) }
      } else {
        throw LocalSpeechError.message(
          "Das Mikrofonformat wird nicht unterstützt. Bitte erneut starten.")
      }
      guard sum.isFinite else {
        throw LocalSpeechError.message("Das Mikrofonsignal ist ungültig. Bitte erneut starten.")
      }
      level = min(1, pow(sqrt(sum / Double(count)) * 8, 0.65))
      audioTime += Double(count) / buffer.format.sampleRate
      request?.append(buffer)
      if detector == nil { detector = try VoiceActivityDetector(input: buffer.format) }
      try detector?.append(buffer) { voice, _ in
        vadTime += 0.02
        frames.append(AudioActivity(time: vadTime, speech: voice, duration: 0.02))
      }
      guard audioTime - vadTime < 0.5 else {
        throw LocalSpeechError.message(
          "Die Audioverarbeitung liefert keine Sprachaktivität. Bitte erneut starten.")
      }
      if audioTime - published >= 0.04 {
        frame(AudioActivityBatch(time: audioTime, level: level, frames: frames, failure: nil))
        frames.removeAll(keepingCapacity: true)
        published = audioTime
      }
      guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
      else {
        throw LocalSpeechError.message(
          "Der Sprachbeginn konnte nicht gepuffert werden. Bitte erneut starten.")
      }
      copy.frameLength = buffer.frameLength
      let from = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
      for (src, dst) in zip(from, to) {
        if let source = src.mData, let destination = dst.mData {
          memcpy(destination, source, Int(src.mDataByteSize))
        }
      }
      ring.append(copy)
      while ring.count > 1
        && ring.reduce(0.0, { $0 + Double($1.frameLength) / $1.format.sampleRate }) > 0.4
      { ring.removeFirst() }
    } catch {
      failed = true
      frame(
        AudioActivityBatch(
          time: audioTime, level: level, frames: frames, failure: error.localizedDescription))
    }
  }
}
enum LocalSpeechError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

@MainActor @Observable final class LocalSpeechRecorder {
  enum State { case idle, preparing, recording, finishing }
  private(set) var state: State = .idle
  private(set) var transcript = ""
  private(set) var level = 0.0
  private(set) var userSpeaking = false
  private(set) var failure: String?
  var onEndpoint: (() -> Void)?
  var onBargeIn: (() -> Void)?
  var onFailure: ((String) -> Void)?
  private var committed = ""
  private var generation = UUID()
  private var segment = UUID()
  private var input: SpeechInput?
  private var recognizer: SFSpeechRecognizer?
  private var recognition: SFSpeechRecognitionTask?
  private var finished = false
  private var recognitionFailed = false
  private var endpoint = SpeechEndpoint()
  private var onset: [Bool] = []
  private var endpointSent = false
  private var monitor = false
  private var startedAt = 0.0
  private var minimumAudioTime = 0.0
  private var watchdog = AudioWatchdog(lastBuffer: 0)
  private var watchdogTask: Task<Void, Never>?
  private var lastVoiceTime = -1.0
  private var receivedAudio = false
  var correlation = UUID().uuidString

  static func makeRecognizer() -> SFSpeechRecognizer? {
    ["de-AT", "de-DE"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }.first {
      $0.supportsOnDeviceRecognition
    }
  }
  func beginTurn(preRoll: Bool = false) async throws {
    guard state == .idle else { return }
    state = .preparing
    transcript = ""
    committed = ""
    failure = nil
    let current = generation
    do {
      if !ConversationAudio.shared.microphoneActive {
        guard await AVAudioApplication.requestRecordPermission() else {
          throw LocalSpeechError.message("Mikrofonzugriff in den iPhone-Einstellungen erlauben.")
        }
        guard generation == current else { throw CancellationError() }
        let authorization = await withCheckedContinuation { continuation in
          SFSpeechRecognizer.requestAuthorization { @Sendable status in
            continuation.resume(returning: status)
          }
        }
        guard generation == current else { throw CancellationError() }
        guard authorization == .authorized else {
          throw LocalSpeechError.message(
            "Spracherkennung in den iPhone-Einstellungen erlauben. Texteingabe ist in den Gesprächsdetails möglich."
          )
        }
        guard let recognizer = Self.makeRecognizer() else {
          throw LocalSpeechError.message(
            "Die lokale deutsche Spracherkennung ist noch nicht verfügbar. Deutsch für die Diktierfunktion aktivieren. Texteingabe ist in den Gesprächsdetails möglich."
          )
        }
        self.recognizer = recognizer
        let input = SpeechInput { @Sendable [weak self] batch in
          Task { @MainActor in
            guard let self, self.generation == current else { return }
            self.receive(batch)
          }
        }
        self.input = input
        try ConversationAudio.shared.startMicrophone { @Sendable buffer in input.append(buffer) }
        receivedAudio = false
        watchdog = AudioWatchdog(lastBuffer: ProcessInfo.processInfo.systemUptime)
        watchdogTask = Task { [weak self] in
          while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.generation == current else { return }
            if self.watchdog.stalled(at: ProcessInfo.processInfo.systemUptime) {
              self.fail("Das Mikrofon liefert kein Audio mehr. Bitte erneut starten.")
              return
            }
          }
        }
      }
      guard generation == current else { throw CancellationError() }
      monitor = false
      onset = []
      endpoint = SpeechEndpoint(confirmedPreRoll: preRoll)
      endpointSent = false
      startedAt = ProcessInfo.processInfo.systemUptime
      state = .recording
      receivedAudio = false
      startSegment(preRoll: preRoll)
    } catch {
      if generation == current { cancelTurn() }
      throw error
    }
  }
  private func receive(_ batch: AudioActivityBatch) {
    watchdog.lastBuffer = ProcessInfo.processInfo.systemUptime
    if !receivedAudio {
      receivedAudio = true
      LocalDiagnostics.shared.record(.audioInput, .started, correlation: correlation)
    }
    level += (batch.level - level) * 0.65
    if let message = batch.failure {
      fail(message)
      return
    }
    for frame in batch.frames where frame.time >= minimumAudioTime {
      if frame.speech { lastVoiceTime = frame.time }
      userSpeaking = frame.time - lastVoiceTime < 0.15
      if monitor {
        onset.append(frame.speech)
        if onset.count > 12 { onset.removeFirst() }
        if onset.filter({ $0 }).count >= 10 {
          monitor = false
          onset = []
          LocalDiagnostics.shared.record(.bargeIn, .completed, correlation: correlation)
          onBargeIn?()
          return
        }
      } else if state == .recording && !endpointSent {
        if endpoint.append(voice: frame.speech, transcript: transcript, duration: frame.duration)
          || frame.time - startedAt >= 120
        {
          endpointSent = true
          LocalDiagnostics.shared.record(
            .speechEndpoint, .completed, correlation: correlation,
            durationMs: Int(endpoint.silenceDuration * 1000))
          onEndpoint?()
          return
        }
      }
    }
  }
  private func fail(_ message: String) {
    LocalDiagnostics.shared.record(.audioInput, .failed, correlation: correlation)
    cancelTurn()
    failure = message
    onFailure?(message)
  }
  func monitorForInterruption() {
    monitor = true
    onset = []
    level = 0
  }
  private func startSegment(preRoll: Bool = false) {
    guard let recognizer, state == .recording else { return }
    segment = UUID()
    let segment = segment
    let current = generation
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
    finished = false
    recognitionFailed = false
    let audioTime = input?.replace(request, preRoll: preRoll) ?? 0
    if committed.isEmpty {
      minimumAudioTime = audioTime
      startedAt = audioTime
    }
    recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal ?? false
      let noSpeech = (error as NSError?)?.code == 1110
      let failed = error != nil
      Task { @MainActor in
        guard let self, self.generation == current, self.segment == segment else { return }
        if let text { self.transcript = self.committed + text }
        guard final || failed else { return }
        self.finished = true
        if self.state == .finishing {
          self.recognitionFailed = failed && !final && !noSpeech
          return
        }
        if final || noSpeech {
          self.committed = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          if !self.committed.isEmpty { self.committed += " " }
          self.recognition?.cancel()
          self.startSegment()
        } else {
          let message =
            "Die Spracherkennung wurde unterbrochen. Bitte erneut starten oder in den Gesprächsdetails schreiben."
          self.cancelTurn()
          self.failure = message
          self.onFailure?(message)
        }
      }
    }
  }
  func endTurn() async throws -> String {
    guard state == .recording else { return "" }
    state = .finishing
    level = 0
    userSpeaking = false
    let current = generation
    _ = input?.replace(nil)
    recognition?.finish()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !finished && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(40))
      guard generation == current else { throw CancellationError() }
    }
    guard generation == current else { throw CancellationError() }
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let failed = recognitionFailed || !finished
    recognition?.cancel()
    recognition = nil
    segment = UUID()
    state = .idle
    if failed {
      throw LocalSpeechError.message(
        "Die Aufnahme konnte nicht erkannt werden. Bitte erneut sprechen.")
    }
    return text
  }
  func cancelTurn() {
    generation = UUID()
    segment = UUID()
    monitor = false
    watchdogTask?.cancel()
    watchdogTask = nil
    userSpeaking = false
    lastVoiceTime = -1
    _ = input?.replace(nil)
    input = nil
    if ConversationAudio.shared.microphoneActive {
      SpeechOutput.shared.stop()
      ConversationAudio.shared.shutdown()
    }
    recognition?.cancel()
    recognition = nil
    recognizer = nil
    state = .idle
    level = 0
    transcript = ""
    committed = ""
    failure = nil
  }
}
struct VoiceSettingsView: View {

  @State private var rate = SpeechOutput.shared.rate
  @State private var output = SpeechOutput.shared
  var body: some View {
    Form {
      Section {
        LabeledContent("Stimme", value: "Victoria · Deutsch")
        VStack(alignment: .leading) {
          LabeledContent(
            "Sprechtempo", value: rate.formatted(.number.precision(.fractionLength(2))) + "×")
          Slider(value: $rate, in: 0.75...1.25, step: 0.05) { Text("Sprechtempo") }
        }
        Button(
          output.speaking ? "Wiedergabe beenden" : "Stimme anhören",
          systemImage: output.speaking ? "stop" : "play"
        ) {
          if output.speaking {
            output.stop()
          } else {
            output.speak("Am 14. September um 9 Uhr 15: Physiotherapie, Raum 2.14 in Laßnitzhöhe.")
          }
        }.accessibilityIdentifier("preview-voice").accessibilityValue(output.phase.rawValue)
        if output.phase == .preparing { ProgressView("Stimme vorbereiten …") }
        if output.phase == .failed { Text(output.status).foregroundStyle(AppPalette.destructive) }
      } header: {
        HStack {
          Text("Stimme")
          Spacer()
          ContextHelp(
            "Victoria",
            "Die Stimme ist bereits enthalten und funktioniert auf diesem iPhone ohne Internet.")
        }
      }
      Section {
        LabeledContent(
          "Spracherkennung",
          value: LocalSpeechRecorder.makeRecognizer() == nil
            ? "Nicht verfügbar" : "Auf diesem iPhone")
      } header: {
        HStack {
          Text("Spracherkennung")
          Spacer()
          ContextHelp(
            "Spracherkennung",
            "Nach etwa einer Sekunde Sprechpause beginnt die Antwort automatisch. Bei unfertigen Sätzen wartet die App länger. Hineinsprechen unterbricht die Wiedergabe. Das Gespräch kann jederzeit pausiert werden."
          )
        }
      }

    }.pageTitle("Sprache")
      .onAppear { rate = output.rate }
      .onChange(of: rate) {
        output.stop()
        output.rate = rate
      }
      .onDisappear { output.stop() }
  }
}

#if DEBUG && targetEnvironment(simulator)
  /// Exercises the exact microphone pipeline with synthetic PCM; never records a user.
  private final class AudioProbeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AudioActivityBatch] = []
    func append(_ value: AudioActivityBatch) {
      lock.lock()
      values.append(value)
      lock.unlock()
    }
    func snapshot() -> [AudioActivityBatch] {
      lock.lock()
      defer { lock.unlock() }
      return values
    }
  }
  extension LocalSpeechRecorder {
    static func verifyAudioPipeline() throws {
      for rate in [16_000.0, 44_100.0, 48_000.0] {
        for channels: AVAudioChannelCount in [1, 2] {
          let sink = AudioProbeSink()
          let input = SpeechInput { sink.append($0) }
          let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
          let count = AVAudioFrameCount(rate * 0.02)
          for index in 0..<100 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            for channel in 0..<Int(channels) {
              for sample in 0..<Int(count) {
                buffer.floatChannelData![channel][sample] =
                  index < 50 ? Float(sin(Double(sample) * 0.11) * 0.1) : 0
              }
            }
            input.append(buffer)
          }
          let batches = sink.snapshot()
          precondition(
            batches.allSatisfy { $0.failure == nil },
            "PCM conversion failed at \(rate), \(channels)")
          precondition(batches.contains { $0.level > 0.1 } && batches.last!.level == 0)
          precondition(batches.count >= 30 && batches.count <= 51)
          precondition((batches.flatMap(\.frames).last?.time ?? 0) > 1.9)
          // A format change is visible; independent metering still has a real value.
          let badFormat = AVAudioFormat(
            standardFormatWithSampleRate: rate + 1000, channels: channels)!
          let bad = AVAudioPCMBuffer(pcmFormat: badFormat, frameCapacity: 960)!
          bad.frameLength = 960
          for channel in 0..<Int(channels) {
            for sample in 0..<960 { bad.floatChannelData![channel][sample] = 0.1 }
          }
          input.append(bad)
          precondition(sink.snapshot().last!.failure != nil && sink.snapshot().last!.level > 0)
        }
      }
      let report: [String: Any] = [
        "synthetic_pcm": true, "sample_rates": [16000, 44100, 48000], "channels": [1, 2],
        "meter_independent_of_vad": true, "format_change_detected": true, "real_microphone": false,
      ]
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(
          to: URL.documentsDirectory.appendingPathComponent("audio-pipeline-probe.json"),
          options: .atomic)
    }
  }
#endif
