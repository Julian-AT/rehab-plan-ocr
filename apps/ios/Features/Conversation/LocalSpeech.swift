import AVFoundation
import AppleServices
@preconcurrency import Speech
import SwiftUI

@MainActor @Observable final class LocalSpeechRecorder {
  typealias State = VoiceRecordingState
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
  private var inputChannel: SpeechInputChannel?
  private var inputTask: Task<Void, Never>?
  private var levelPublication = InputLevelPublication()
  var turnID = UUID()
  private var provider: (any SpeechRecognitionProvider)?
  private var providerTask: Task<Void, Never>?
  private var completion: RecognitionCompletion?
  private var progress = RecognitionProgress()
  private var firstResult = false
  private var recognizerReady = false
  private var installingAssets = false
  private var readinessStartedAt = 0.0
  private var endpoint = SpeechEndpoint()
  private var onset: [Bool] = []
  private var endpointSent = false
  private var monitor = false
  private var monitoringSince = 0.0
  private var startedAt = 0.0
  private var microphoneID = UUID()
  private var watchdog = InputBufferWatchdog()
  private var watchdogTask: Task<Void, Never>?
  private var receivedBuffer = false
  private var lastLevelLog = 0.0
  private var configurationRecovery = AudioConfigurationRecovery()
  var contextualTitles: [String] = []
  #if DEBUG && targetEnvironment(simulator)
    private var previewInputTask: Task<Void, Never>?
  #endif

  func beginTurn(preRoll: Bool = false) async throws {
    guard state == .idle else { return }
    state = .preparing
    transcript = ""
    committed = ""
    failure = nil
    let current = generation
    progress = RecognitionProgress()
    firstResult = false
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
          .microphonePermission, microphoneAllowed ? .completed : .failed,
          correlation: self.turnID.uuidString)
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
          .speechPermission, authorization == .authorized ? .completed : .failed,
          correlation: self.turnID.uuidString)
        guard authorization == .authorized else {
          throw LocalSpeechError.message(
            "Spracherkennung in den iPhone-Einstellungen erlauben. Texteingabe ist in den Gesprächsdetails möglich."
          )
        }
      }
      guard generation == current else { throw CancellationError() }
      monitor = false
      onset = []
      endpoint = SpeechEndpoint(confirmedPreRoll: preRoll)
      endpointSent = false
      startedAt = ProcessInfo.processInfo.systemUptime
      if input == nil {
        watchdog = InputBufferWatchdog()
        configurationRecovery.start()
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
  private func prepareMicrophone(recovering: Bool = false) throws {
    microphoneID = UUID()
    let id = microphoneID
    let current = generation
    receivedBuffer = false
    state = .preparing
    inputChannel?.finish()
    inputTask?.cancel()
    levelPublication = InputLevelPublication()
    input?.cancel()
    providerTask?.cancel()
    provider?.cancel()
    provider = nil
    segment = UUID()
    let channel = SpeechInputChannel()
    inputChannel = channel
    let input = SpeechInput(channel: channel)
    inputTask = Task { [weak self] in
      do {
        for try await packet in channel.stream {
          try Task.checkCancellation()
          try channel.checkActive()
          guard let self, self.generation == current, self.microphoneID == id else { return }
          self.receiveBuffer(
            level: packet.level, rate: packet.sampleRate, channels: packet.channels,
            capturedAt: packet.capturedAt)
          let observations = self.monitor ? packet.interruptionFrames : packet.voicedFrames
          for voice in observations {
            guard self.generation == current, self.microphoneID == id else { return }
            if packet.capturedAt < (self.monitor ? self.monitoringSince : self.startedAt) {
              continue
            }
            self.receive(voice: voice)
          }
        }
      } catch {
        guard !Task.isCancelled, let self, self.generation == current,
          self.microphoneID == id
        else { return }
        LocalDiagnostics.shared.record(
          .audioConversion, .failed, correlation: self.turnID.uuidString)
        if let error = error as? InputAudioError, error == .invalidFormat {
          self.configurationChanged(needsNewInput: true)
        } else {
          self.failInput(
            "Die Mikrofondaten konnten nicht verarbeitet werden. Bitte das Gespräch erneut starten."
          )
        }
      }
    }
    self.input = input
    startSegment {
      if recovering {
        try ConversationAudio.shared.restartMicrophone { @Sendable buffer in input.append(buffer) }
      } else {
        try ConversationAudio.shared.startMicrophone(correlation: self.turnID.uuidString) {
          @Sendable buffer in input.append(buffer)
        }
      }
      ConversationAudio.shared.onConfigurationChange = { [weak self] in self?.configurationChanged()
      }
      self.watchdog.start(at: ProcessInfo.processInfo.systemUptime)
    }
    watchdogTask?.cancel()
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard let self, self.generation == current, self.microphoneID == id else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !self.recognizerReady {
          if now - self.readinessStartedAt >= (self.installingAssets ? 120 : 10) {
            let reason: RecognitionFailure =
              self.installingAssets ? .assetSetupFailed : .unavailable
            LocalDiagnostics.shared.record(
              .recognitionReadiness, .failed, correlation: self.turnID.uuidString,
              count: reason.diagnosticCode)
            self.failInput(reason.message)
            return
          }
          continue
        }
        if self.configurationRecovery.isPending {
          let configuration = ConversationAudio.shared.microphoneConfiguration
          switch self.configurationRecovery.check(
            at: now, running: configuration.running, matchingFormats: configuration.matchingFormats)
          {
          case .wait: continue
          case .none:
            LocalDiagnostics.shared.record(
              .audioConfiguration, .completed, correlation: self.turnID.uuidString)
          case .restart:
            LocalDiagnostics.shared.record(
              .audioRestart, .started, correlation: self.turnID.uuidString)
            self.restartMicrophone()
            return
          case .fail:
            self.failInput(
              "Die Audioverbindung bleibt instabil. Bitte das Gespräch erneut starten.")
            return
          }
        }
        if self.state == .recording && !self.monitor && !self.endpointSent {
          if self.progress.shouldFinalize(at: now) {
            self.requestEndpoint(reason: 3)
          } else if self.progress.stalled(at: now) {
            LocalDiagnostics.shared.record(
              .recognitionProgress, .failed, correlation: self.turnID.uuidString,
              count: self.progress.voicedFrames)
            self.failInput(RecognitionFailure.noProgress.message)
            return
          }
        }
        switch self.watchdog.check(at: now) {
        case .wait: continue
        case .restart:
          LocalDiagnostics.shared.record(
            .audioRestart, .started, correlation: self.turnID.uuidString)
          self.restartMicrophone()
          return
        case .fail:
          LocalDiagnostics.shared.record(.audioBuffer, .failed, correlation: self.turnID.uuidString)
          self.failInput(
            "Vom Mikrofon kommen keine Audiodaten an. Bitte das Gespräch erneut starten.")
          return
        }
      }
    }
  }
  private func receiveBuffer(
    level: Double, rate: Double, channels: Int,
    capturedAt: Double = ProcessInfo.processInfo.systemUptime
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    watchdog.received(at: capturedAt)
    configurationRecovery.received(at: capturedAt)
    if let level = levelPublication.receive(level, at: now) { self.level = level }
    if !receivedBuffer {
      receivedBuffer = true
      if state == .preparing && recognizerReady { state = .recording }
      LocalDiagnostics.shared.record(.audioBuffer, .completed, correlation: self.turnID.uuidString)
      LocalDiagnostics.shared.record(
        .audioSampleRate, .completed, correlation: self.turnID.uuidString, count: Int(rate))
      LocalDiagnostics.shared.record(
        .audioChannels, .completed, correlation: self.turnID.uuidString, count: channels)
    }
    if now - lastLevelLog >= 1 {
      lastLevelLog = now
      LocalDiagnostics.shared.record(
        .audioLevel, .completed, correlation: self.turnID.uuidString, count: Int(level * 1000))
    }
  }
  private func configurationChanged(needsNewInput: Bool = false) {
    guard input != nil else { return }
    let configuration = ConversationAudio.shared.microphoneConfiguration
    LocalDiagnostics.shared.record(
      .audioConfiguration, .started, correlation: self.turnID.uuidString,
      count: (configuration.running ? 1 : 0) + (configuration.matchingFormats ? 2 : 0)
        + (needsNewInput ? 4 : 0))
    configurationRecovery.changed(
      at: ProcessInfo.processInfo.systemUptime, needsNewInput: needsNewInput)
  }
  private func restartMicrophone() {
    guard input != nil, !monitor, state == .recording || state == .preparing else {
      failInput("Die Audioverbindung wurde unterbrochen. Bitte das Gespräch erneut starten.")
      return
    }
    if !transcript.isEmpty || progress.voicedFrames > 0 {
      failInput(RecognitionFailure.interrupted.message)
      return
    }
    endpoint = SpeechEndpoint()
    endpointSent = false
    startedAt = ProcessInfo.processInfo.systemUptime
    do { try prepareMicrophone(recovering: true) } catch {
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
    } else if (state == .recording || state == .preparing) && !endpointSent {
      let ended = endpoint.append(voice: voice, transcript: transcript)
      if voice && endpoint.hasSpeech { progress.voice(at: ProcessInfo.processInfo.systemUptime) }
      if ended {
        requestEndpoint(reason: 1)
      } else if ProcessInfo.processInfo.systemUptime - startedAt > 120 {
        // Bound even a continuously noisy input. Silence never creates a request.
        if endpoint.hasSpeech && endpoint.voicedFrames >= 5 {
          requestEndpoint(reason: 2)
        } else {
          startedAt = ProcessInfo.processInfo.systemUptime
        }
      }
    }
  }
  private func requestEndpoint(reason: Int) {
    guard !endpointSent else { return }
    endpointSent = true
    LocalDiagnostics.shared.record(
      .speechEndpoint, .completed, correlation: turnID.uuidString, count: reason)
    if state == .recording { onEndpoint?() }
  }
  func monitorForInterruption() {
    monitor = true
    monitoringSince = ProcessInfo.processInfo.systemUptime
    input?.monitorForInterruption()
    onset = []
    level = 0
    levelPublication = InputLevelPublication()
  }
  private func startSegment(
    preRoll: Bool = false, startMicrophone: (@MainActor () throws -> Void)? = nil
  ) {
    segment = UUID()
    let segment = segment
    let current = generation
    completion = nil
    recognizerReady = false
    installingAssets = false
    readinessStartedAt = ProcessInfo.processInfo.systemUptime
    input?.beginPending(preRoll: preRoll)
    providerTask?.cancel()
    provider?.cancel()
    provider = nil
    state = .preparing
    providerTask = Task { [weak self] in
      guard let self else { return }
      let started = ProcessInfo.processInfo.systemUptime
      LocalDiagnostics.shared.record(
        .recognitionReadiness, .started, correlation: self.turnID.uuidString)
      do {
        let selected = try await SpeechRecognitionProviders.ready(
          titles: self.contextualTitles,
          allowInstallation: startMicrophone != nil && !ConversationAudio.shared.microphoneActive
        ) { [weak self] stage in
          guard let self, self.generation == current, self.segment == segment,
            !Task.isCancelled
          else { return }
          switch stage {
          case .assets(let status):
            LocalDiagnostics.shared.record(
              .recognitionAssets, .completed, correlation: self.turnID.uuidString,
              count: status.rawValue)
          case .installing(let active):
            self.installingAssets = active
            self.readinessStartedAt = ProcessInfo.processInfo.systemUptime
            LocalDiagnostics.shared.record(
              .recognitionAssets, active ? .started : .completed,
              correlation: self.turnID.uuidString)
          }
        }
        guard self.generation == current, self.segment == segment, !Task.isCancelled else {
          selected.cancel()
          return
        }
        self.provider = selected
        let sink = try await selected.start { [weak self] event in
          guard let self, self.generation == current, self.segment == segment else { return }
          self.receiveRecognition(event)
        }
        guard self.generation == current, self.segment == segment, !Task.isCancelled else {
          selected.cancel()
          return
        }
        LocalDiagnostics.shared.record(
          .recognitionReadiness, .completed, correlation: self.turnID.uuidString,
          durationMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
          count: selected.diagnosticCode)
        LocalDiagnostics.shared.record(
          .recognitionLocale, .completed, correlation: self.turnID.uuidString,
          count: selected.locale.region?.identifier == "AT" ? 1 : 2)
        self.input?.replace(sink, preRoll: preRoll)
        self.recognizerReady = true
        try startMicrophone?()
        self.state = self.receivedBuffer ? .recording : .preparing
        if self.endpointSent && self.state == .recording { self.onEndpoint?() }
      } catch {
        guard self.generation == current, self.segment == segment, !Task.isCancelled else { return }
        let reason = error as? RecognitionFailure ?? .unavailable
        LocalDiagnostics.shared.record(
          .recognitionReadiness, .failed, correlation: self.turnID.uuidString,
          count: reason.diagnosticCode)
        self.failInput(reason.message)
      }
    }
  }
  private func receiveRecognition(_ event: RecognitionEvent) {
    switch event {
    case .result(let result):
      transcript = RecognitionTranscript.join(committed, result.text)
      progress.result(text: transcript, at: result.receivedAt)
      if !firstResult || result.isFinal {
        LocalDiagnostics.shared.record(
          result.isFinal ? .recognitionFinal : .recognitionPartial,
          .completed, correlation: self.turnID.uuidString,
          durationMs: Int(max(0, result.receivedAt - startedAt) * 1000), count: result.text.count)
      }
      firstResult = true
    case .completed(let outcome):
      completion = outcome
      guard state != .finishing else { return }
      switch outcome {
      case .finalized(let text):
        committed = RecognitionTranscript.join(committed, text)
        input?.replace(nil)
        startSegment()
      case .noSpeech:
        // A provider that reports silence despite voiced evidence must not loop forever.
        if progress.voicedFrames > 0 {
          failInput(RecognitionFailure.noProgress.message)
        } else {
          input?.replace(nil)
          startSegment()
        }
      case .failed(let reason): failInput(reason.message)
      case .cancelled: failInput(RecognitionFailure.interrupted.message)
      }
    }
  }
  func endTurn() async throws -> String {
    guard state == .recording else { return "" }
    state = .finishing
    level = 0
    let current = generation
    input?.replace(nil)
    LocalDiagnostics.shared.record(
      .recognitionFinalization, .started, correlation: self.turnID.uuidString,
      count: progress.voicedFrames)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    do {
      while completion == nil && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
        guard generation == current else { throw CancellationError() }
      }
      try Task.checkCancellation()
      guard generation == current else { throw CancellationError() }
      let outcome = completion ?? .failed(.finalizationTimeout)
      provider?.cancel()
      provider = nil
      segment = UUID()
      state = .idle
      switch outcome {
      case .finalized(let text):
        LocalDiagnostics.shared.record(
          .recognitionFinalization, .completed, correlation: self.turnID.uuidString)
        return RecognitionTranscript.join(committed, text)
      case .noSpeech:
        if progress.voicedFrames > 0 && committed.isEmpty { throw RecognitionFailure.noProgress }
        return committed
      case .cancelled: throw CancellationError()
      case .failed(let reason): throw reason
      }
    } catch {
      if generation == current {
        LocalDiagnostics.shared.record(
          .recognitionFinalization, .failed, correlation: self.turnID.uuidString,
          count: (error as? RecognitionFailure)?.diagnosticCode)
        cancelTurn()
      }
      if let reason = error as? RecognitionFailure {
        throw LocalSpeechError.message(reason.message)
      }
      throw error
    }
  }
  func cancelTurn() {
    #if DEBUG && targetEnvironment(simulator)
      previewInputTask?.cancel()
      previewInputTask = nil
    #endif
    LocalDiagnostics.shared.record(.speechSession, .cancelled, correlation: self.turnID.uuidString)
    generation = UUID()
    microphoneID = UUID()
    watchdog.cancel()
    configurationRecovery.cancel()
    watchdogTask?.cancel()
    watchdogTask = nil
    receivedBuffer = false
    recognizerReady = false
    installingAssets = false
    segment = UUID()
    monitor = false
    inputChannel?.finish()
    inputChannel = nil
    inputTask?.cancel()
    inputTask = nil
    levelPublication = InputLevelPublication()
    input?.cancel()
    input = nil
    if ConversationAudio.shared.microphoneActive {
      SpeechOutput.shared.stop()
      ConversationAudio.shared.shutdown()
    }
    providerTask?.cancel()
    providerTask = nil
    provider?.cancel()
    provider = nil
    completion = .cancelled
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
      recognizerReady = true
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
