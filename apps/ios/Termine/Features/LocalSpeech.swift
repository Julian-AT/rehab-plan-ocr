import AVFoundation
import AppleServices
@preconcurrency import Speech
import SwiftUI

/// Request swaps, detector state and pre-roll share a lock. Callbacks are
/// immutable and enqueue values only; no tap buffer crosses to the main actor.
private final class SpeechInput: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var ring: [AVAudioPCMBuffer] = []
  private var detector: VoiceActivityDetector?
  private var failed = false
  private let meter: @Sendable (Double, Double, Int) -> Void
  private let frame: @Sendable (Bool) -> Void
  private let failure: @Sendable (InputAudioError) -> Void
  init(
    meter: @escaping @Sendable (Double, Double, Int) -> Void,
    frame: @escaping @Sendable (Bool) -> Void,
    failure: @escaping @Sendable (InputAudioError) -> Void
  ) {
    self.meter = meter
    self.frame = frame
    self.failure = failure
  }
  func replace(_ next: SFSpeechAudioBufferRecognitionRequest?, preRoll: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    request?.endAudio()
    request = next
    if preRoll { for buffer in ring { next?.append(buffer) } }
  }
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard !failed else { return }
    do {
      guard let level = try InputAudioLevel.measure(buffer) else { return }
      meter(level, buffer.format.sampleRate, Int(buffer.format.channelCount))
      if let detector, detector.inputFormat != buffer.format {
        // A recognition request cannot mix PCM formats. Reprepare the graph
        // and request together instead of appending an incompatible buffer.
        throw InputAudioError.invalidFormat
      }
      if detector == nil { detector = try VoiceActivityDetector(input: buffer.format) }
      request?.append(buffer)
      try detector?.append(buffer, frame: frame)
      guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
      else { throw InputAudioError.conversion }
      copy.frameLength = buffer.frameLength
      let from = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
      for (src, dst) in zip(from, to) {
        if let source = src.mData, let destination = dst.mData {
          memcpy(destination, source, Int(src.mDataByteSize))
        }
      }
      ring.append(copy)
      while ring.reduce(0.0, { $0 + Double($1.frameLength) / $1.format.sampleRate }) > 0.4 {
        ring.removeFirst()
      }
    } catch {
      failed = true
      failure(error as? InputAudioError ?? .conversion)
    }
  }
}

@MainActor @Observable final class LocalSpeechRecorder {
  enum State { case idle, preparing, recording, finishing }
  private(set) var state: State = .idle
  private(set) var transcript = ""
  private(set) var level = 0.0
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
  private var microphoneID = UUID()
  private var watchdog = InputBufferWatchdog()
  private var watchdogTask: Task<Void, Never>?
  private var receivedBuffer = false
  private var lastLevelLog = 0.0
  private var configurationRetryUsed = false
  #if DEBUG && targetEnvironment(simulator)
    private var previewInputTask: Task<Void, Never>?
  #endif

  static func makeRecognizer() -> SFSpeechRecognizer? {
    ["de-AT", "de-DE"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }.first {
      $0.supportsOnDeviceRecognition && $0.isAvailable
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
      #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-microphone") {
          try beginPreviewInput()
          return
        }
      #endif
      if !ConversationAudio.shared.microphoneActive {
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard generation == current, !Task.isCancelled else { throw CancellationError() }
        LocalDiagnostics.shared.record(
          .microphonePermission, microphoneAllowed ? .completed : .failed)
        guard microphoneAllowed else {
          throw LocalSpeechError.message("Mikrofonzugriff in den iPhone-Einstellungen erlauben.")
        }
        guard generation == current else { throw CancellationError() }
        let authorization = await withCheckedContinuation { continuation in
          SFSpeechRecognizer.requestAuthorization { @Sendable status in
            continuation.resume(returning: status)
          }
        }
        guard generation == current else { throw CancellationError() }
        LocalDiagnostics.shared.record(
          .speechPermission, authorization == .authorized ? .completed : .failed)
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
      }
      guard generation == current else { throw CancellationError() }
      monitor = false
      onset = []
      endpoint = SpeechEndpoint(confirmedPreRoll: preRoll)
      endpointSent = false
      startedAt = ProcessInfo.processInfo.systemUptime
      if input == nil {
        watchdog = InputBufferWatchdog()
        configurationRetryUsed = false
        try prepareMicrophone()
      } else {
        state = receivedBuffer ? .recording : .preparing
        startSegment(preRoll: preRoll)
      }
    } catch {
      if generation == current { cancelTurn() }
      throw error
    }
  }
  private func prepareMicrophone() throws {
    microphoneID = UUID()
    let id = microphoneID
    let current = generation
    receivedBuffer = false
    state = .preparing
    input?.replace(nil)
    recognition?.cancel()
    recognition = nil
    segment = UUID()
    let input = SpeechInput(
      meter: { @Sendable [weak self] level, rate, channels in
        Task { @MainActor in
          guard let self, self.generation == current, self.microphoneID == id else { return }
          self.receiveBuffer(level: level, rate: rate, channels: channels)
        }
      },
      frame: { @Sendable [weak self] voice in
        Task { @MainActor in
          guard let self, self.generation == current, self.microphoneID == id else { return }
          self.receive(voice: voice)
        }
      },
      failure: { @Sendable [weak self] error in
        Task { @MainActor in
          guard let self, self.generation == current, self.microphoneID == id else { return }
          LocalDiagnostics.shared.record(.audioConversion, .failed, correlation: current.uuidString)
          if error == .invalidFormat {
            self.configurationChanged()
          } else {
            self.failInput(
              "Die Mikrofondaten konnten nicht verarbeitet werden. Bitte das Gespräch erneut starten."
            )
          }
        }
      })
    self.input = input
    // The recognition task and receiver exist before any microphone audio flows.
    startSegment()
    try ConversationAudio.shared.startMicrophone { @Sendable buffer in input.append(buffer) }
    ConversationAudio.shared.onConfigurationChange = { [weak self] in self?.configurationChanged() }
    watchdog.start(at: ProcessInfo.processInfo.systemUptime)
    watchdogTask?.cancel()
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard let self, self.generation == current, self.microphoneID == id else { return }
        switch self.watchdog.check(at: ProcessInfo.processInfo.systemUptime) {
        case .wait: continue
        case .restart:
          LocalDiagnostics.shared.record(.audioRestart, .started, correlation: current.uuidString)
          self.restartMicrophone()
          return
        case .fail:
          LocalDiagnostics.shared.record(.audioBuffer, .failed, correlation: current.uuidString)
          self.failInput(
            "Vom Mikrofon kommen keine Audiodaten an. Bitte das Gespräch erneut starten.")
          return
        }
      }
    }
  }
  private func receiveBuffer(level: Double, rate: Double, channels: Int) {
    let now = ProcessInfo.processInfo.systemUptime
    watchdog.received(at: now)
    self.level += (level - self.level) * 0.4
    if !receivedBuffer {
      receivedBuffer = true
      if state == .preparing { state = .recording }
      LocalDiagnostics.shared.record(.audioBuffer, .completed, correlation: generation.uuidString)
      LocalDiagnostics.shared.record(
        .audioSampleRate, .completed, correlation: generation.uuidString, count: Int(rate))
      LocalDiagnostics.shared.record(
        .audioChannels, .completed, correlation: generation.uuidString, count: channels)
    }
    if now - lastLevelLog >= 1 {
      lastLevelLog = now
      LocalDiagnostics.shared.record(
        .audioLevel, .completed, correlation: generation.uuidString, count: Int(level * 1000))
    }
  }
  private func configurationChanged() {
    guard input != nil else { return }
    guard !configurationRetryUsed, !monitor, state == .recording || state == .preparing else {
      failInput("Die Audioverbindung wurde geändert. Bitte das Gespräch erneut starten.")
      return
    }
    configurationRetryUsed = true
    LocalDiagnostics.shared.record(.audioRestart, .started, correlation: generation.uuidString)
    restartMicrophone()
  }
  private func restartMicrophone() {
    guard input != nil, !monitor, state == .recording || state == .preparing else {
      failInput("Die Audioverbindung wurde unterbrochen. Bitte das Gespräch erneut starten.")
      return
    }
    committed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if !committed.isEmpty { committed += " " }
    endpoint = SpeechEndpoint()
    endpointSent = false
    startedAt = ProcessInfo.processInfo.systemUptime
    do { try prepareMicrophone() } catch {
      failInput("Das Mikrofon konnte nicht neu gestartet werden. Bitte erneut versuchen.")
    }
  }
  private func failInput(_ message: String) {
    cancelTurn()
    failure = message
    onFailure?(message)
  }
  private func receive(voice: Bool) {
    if monitor {
      onset.append(voice)
      if onset.count > 12 { onset.removeFirst() }
      // 200 ms of voiced evidence in 240 ms rejects short impacts/clicks.
      if onset.filter({ $0 }).count >= 10 {
        monitor = false
        onset = []
        onBargeIn?()
      }
    } else if state == .recording && !endpointSent {
      if endpoint.append(voice: voice, transcript: transcript) {
        endpointSent = true
        onEndpoint?()
      } else if ProcessInfo.processInfo.systemUptime - startedAt > 120 {
        // Bound even a continuously noisy input. Silence never creates a request.
        if endpoint.voicedFrames >= 5 {
          endpointSent = true
          onEndpoint?()
        } else {
          startedAt = ProcessInfo.processInfo.systemUptime
        }
      }
    }
  }
  func monitorForInterruption() {
    monitor = true
    onset = []
    level = 0
  }
  private func startSegment(preRoll: Bool = false) {
    guard let recognizer, state == .recording || state == .preparing else { return }
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
    input?.replace(request, preRoll: preRoll)
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
    let current = generation
    input?.replace(nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !finished && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(40))
      guard generation == current else { throw CancellationError() }
    }
    guard generation == current else { throw CancellationError() }
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let failed = recognitionFailed || (!finished && text.isEmpty)
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
    #if DEBUG && targetEnvironment(simulator)
      previewInputTask?.cancel()
      previewInputTask = nil
    #endif
    generation = UUID()
    microphoneID = UUID()
    watchdog.cancel()
    watchdogTask?.cancel()
    watchdogTask = nil
    receivedBuffer = false
    segment = UUID()
    monitor = false
    input?.replace(nil)
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

  #if DEBUG && targetEnvironment(simulator)
    /// Explicit simulator-only PCM fixture: exercise the real level detector
    /// without pretending the simulator has on-device speech recognition.
    private func beginPreviewInput() throws {
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
      let detector = try VoiceActivityDetector(input: format)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
      buffer.frameLength = 320
      let silent = ProcessInfo.processInfo.arguments.contains("--preview-microphone-silent")
      state = .preparing
      previewInputTask = Task { [weak self] in
        var frame = 0
        while !Task.isCancelled {
          guard let self else { return }
          let time = Double(frame) / 16_000
          let gain = silent ? 0 : 0.12 * (0.55 + 0.45 * sin(time * 3))
          for index in 0..<320 {
            buffer.floatChannelData![0][index] = Float(
              gain * sin(2 * .pi * 220 * Double(frame + index) / 16_000))
          }
          do {
            if let level = try InputAudioLevel.measure(buffer) {
              self.receiveBuffer(level: level, rate: 16_000, channels: 1)
            }
            try detector.append(buffer) { _ in self.receive(voice: false) }
          } catch {
            self.failInput("Die Testquelle konnte nicht verarbeitet werden.")
            return
          }
          frame += 320
          do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
      }
    }
  #endif
}
