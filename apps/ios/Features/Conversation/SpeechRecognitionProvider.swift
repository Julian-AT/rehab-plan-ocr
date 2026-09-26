import AVFoundation
import Foundation
@preconcurrency import Speech

struct RecognitionCapabilities: Sendable {
  let contextualPhrases: Bool
  let incrementalResults: Bool
  let onDevice: Bool
}

/// Sinks are exclusively consumed by SpeechInput's serial worker. They never
/// retain a borrowed microphone buffer. Finish is ordered after the last append.
protocol RecognitionAudioSink: Sendable {
  func append(_ buffer: AVAudioPCMBuffer) throws
  func finish() throws
}

@MainActor protocol SpeechRecognitionProvider: AnyObject {
  var diagnosticCode: Int { get }
  var locale: Locale { get }
  var capabilities: RecognitionCapabilities { get }
  func start(_ receive: @escaping @MainActor (RecognitionEvent) -> Void) async throws
    -> any RecognitionAudioSink
  func cancel()
}

/// Setup is permitted only before microphone startup. Listening never downloads
/// assets or falls back to server recognition. Missing analyzer assets must not
/// silently select the legacy engine; it remains a hardware/locale fallback.
@MainActor enum SpeechRecognitionProviders {
  static func ready(
    titles: [String], allowInstallation: Bool = false,
    observe: (RecognitionPreparation) -> Void = { _ in }
  ) async throws -> any SpeechRecognitionProvider {
    let legacyRequested = ProcessInfo.processInfo.arguments.contains("--speech-legacy-trial")
    if !legacyRequested, SpeechTranscriber.isAvailable {
      for identifier in ["de-AT", "de-DE"] {
        try Task.checkCancellation()
        guard
          let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: identifier))
        else { continue }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard
          try await SpeechAssetReadiness.ensure(
            AnalyzerAssets(transcriber: transcriber, locale: locale),
            allowInstallation: allowInstallation, observe: observe)
        else { continue }
        guard
          let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { throw RecognitionFailure.invalidAudio }
        try Task.checkCancellation()
        return AnalyzerRecognitionProvider(transcriber: transcriber, locale: locale, format: format)
      }
    }
    if !legacyRequested { observe(.assets(.unsupported)) }
    guard
      let recognizer = ["de-AT", "de-DE"]
        .compactMap({ SFSpeechRecognizer(locale: Locale(identifier: $0)) })
        .first(where: { $0.supportsOnDeviceRecognition && $0.isAvailable })
    else { throw RecognitionFailure.assetsMissing }
    return LegacyRecognitionProvider(recognizer: recognizer, titles: titles)
  }
}

@MainActor private struct AnalyzerAssets: RecognitionAssets {
  let transcriber: SpeechTranscriber
  let locale: Locale
  func status() async -> RecognitionAssetStatus {
    switch await AssetInventory.status(forModules: [transcriber]) {
    case .unsupported: .unsupported
    case .supported: .supported
    case .downloading: .downloading
    case .installed: .installed
    @unknown default: .unsupported
    }
  }
  func reserve() async throws { _ = try await AssetInventory.reserve(locale: locale) }
  func install() async throws {
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
  }
}

@MainActor final class AnalyzerRecognitionProvider: SpeechRecognitionProvider {
  let diagnosticCode = 1
  let locale: Locale
  // SpeechTranscriber does not advertise DictationTranscriber's phrase biasing.
  let capabilities = RecognitionCapabilities(
    contextualPhrases: false, incrementalResults: true, onDevice: true)
  private let transcriber: SpeechTranscriber
  private let format: AVAudioFormat
  private var analyzer: SpeechAnalyzer?
  private var analysisTask: Task<Void, Never>?
  private var resultsTask: Task<RecognitionCompletion, Never>?
  private var generation = UUID()

  init(transcriber: SpeechTranscriber, locale: Locale, format: AVAudioFormat) {
    self.transcriber = transcriber
    self.locale = locale
    self.format = format
  }
  func start(_ receive: @escaping @MainActor (RecognitionEvent) -> Void) async throws
    -> any RecognitionAudioSink
  {
    let id = generation
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.analyzer = analyzer
    try await analyzer.prepareToAnalyze(in: format)
    try Task.checkCancellation()
    guard generation == id else { throw CancellationError() }
    let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(
      bufferingPolicy: .bufferingOldest(32))
    let sink = AnalyzerAudioSink(format: format, continuation: continuation)
    let results = Task { [weak self, transcriber] () -> RecognitionCompletion in
      var transcript = RecognitionTranscript()
      do {
        for try await result in transcriber.results {
          try Task.checkCancellation()
          guard self?.generation == id else { return .cancelled }
          let start = result.range.start.seconds
          let end = result.range.end.seconds
          try transcript.receive(
            String(result.text.characters), start: start, end: end, final: result.isFinal)
          receive(
            .result(
              RecognitionUpdate(
                text: transcript.text, stableText: transcript.stable, audioStart: start,
                audioEnd: end,
                receivedAt: ProcessInfo.processInfo.systemUptime, isFinal: result.isFinal)))
        }
        return transcript.completion
      } catch is CancellationError {
        return .cancelled
      } catch { return .failed(error as? RecognitionFailure ?? .interrupted) }
    }
    resultsTask = results
    analysisTask = Task { [weak self] in
      let outcome: RecognitionCompletion
      do {
        try await analyzer.start(inputSequence: stream)
        // This waits for sink.finish(), drains input, and requests stable results.
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        outcome = await results.value
      } catch {
        results.cancel()
        await analyzer.cancelAndFinishNow()
        outcome =
          Task.isCancelled ? .cancelled : .failed(error as? RecognitionFailure ?? .interrupted)
      }
      guard self?.generation == id, !Task.isCancelled else { return }
      receive(.completed(outcome))
    }
    return sink
  }
  func cancel() {
    generation = UUID()
    analysisTask?.cancel()
    resultsTask?.cancel()
    analysisTask = nil
    resultsTask = nil
    if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    analyzer = nil
  }
}

/// Conversion runs only on the input worker. Converted buffers transfer to the
/// analyzer and are not reused until consumption; the stream is bounded.
private final class AnalyzerAudioSink: RecognitionAudioSink, @unchecked Sendable {
  private let format: AVAudioFormat
  private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
  private var converter: AVAudioConverter?
  private var closed = false
  init(format: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation)
  {
    self.format = format
    self.continuation = continuation
  }
  func append(_ buffer: AVAudioPCMBuffer) throws {
    guard !closed else { throw RecognitionFailure.incomplete }
    if converter == nil { converter = AVAudioConverter(from: buffer.format, to: format) }
    guard let converter, converter.inputFormat == buffer.format else {
      throw InputAudioError.invalidFormat
    }
    let capacity = AVAudioFrameCount(
      ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1024)
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw RecognitionFailure.invalidAudio
    }
    let input = ConverterInput(buffer)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, status in input.take(status) }
    try InputAudioConversion.validate(status, error: error)
    try yield(output)
  }
  private func yield(_ buffer: AVAudioPCMBuffer) throws {
    guard buffer.frameLength > 0 else { return }
    switch continuation.yield(AnalyzerInput(buffer: buffer)) {
    case .enqueued: break
    case .dropped:
      closed = true
      continuation.finish(throwing: RecognitionFailure.overflow)
      throw RecognitionFailure.overflow
    case .terminated: throw CancellationError()
    @unknown default: throw RecognitionFailure.overflow
    }
  }
  func finish() throws {
    guard !closed else { return }
    defer { closed = true }
    do {
      if let converter {
        // Drain converter tail explicitly; otherwise a final syllable can vanish.
        for _ in 0..<8 {
          guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw RecognitionFailure.invalidAudio
          }
          var error: NSError?
          let status = converter.convert(to: output, error: &error) { _, status in
            status.pointee = .endOfStream
            return nil
          }
          try InputAudioConversion.validate(status, error: error)
          try yield(output)
          if status == .endOfStream || output.frameLength == 0 {
            continuation.finish()
            return
          }
        }
        throw RecognitionFailure.incomplete
      }
      continuation.finish()
    } catch {
      continuation.finish(throwing: error)
      throw error
    }
  }
}

@MainActor final class LegacyRecognitionProvider: SpeechRecognitionProvider {
  let diagnosticCode = 2
  var locale: Locale { recognizer.locale }
  let capabilities = RecognitionCapabilities(
    contextualPhrases: true, incrementalResults: true, onDevice: true)
  private let recognizer: SFSpeechRecognizer
  private let titles: [String]
  private var task: SFSpeechRecognitionTask?
  private var generation = UUID()
  private var completed = false
  private var sawText = false
  init(recognizer: SFSpeechRecognizer, titles: [String]) {
    self.recognizer = recognizer
    self.titles = titles
  }
  func start(_ receive: @escaping @MainActor (RecognitionEvent) -> Void) async throws
    -> any RecognitionAudioSink
  {
    try Task.checkCancellation()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
    request.contextualStrings = CalendarVocabulary.phrases(titles: titles)
    let id = generation
    task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal ?? false
      let start = result?.bestTranscription.segments.first?.timestamp ?? 0
      let last = result?.bestTranscription.segments.last
      let end = (last?.timestamp ?? 0) + (last?.duration ?? 0)
      let failed = error != nil
      let noSpeech = (error as NSError?)?.code == 1110
      Task { @MainActor in
        guard let self, self.generation == id, !self.completed else { return }
        if let text {
          self.sawText = self.sawText || !text.isEmpty
          receive(
            .result(
              RecognitionUpdate(
                text: text, stableText: final ? text : "", audioStart: start, audioEnd: end,
                receivedAt: ProcessInfo.processInfo.systemUptime, isFinal: final)))
        }
        if final || failed {
          self.completed = true
          let outcome: RecognitionCompletion
          if final, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outcome = .finalized(text)
          } else if !self.sawText && (final || noSpeech) {
            outcome = .noSpeech
          } else {
            outcome = .failed(.interrupted)
          }
          receive(.completed(outcome))
        }
      }
    }
    return LegacyAudioSink(request)
  }
  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
  }
}

/// Request append/end are serialized by SpeechInput. Speech owns consumption.
private final class LegacyAudioSink: RecognitionAudioSink, @unchecked Sendable {
  let request: SFSpeechAudioBufferRecognitionRequest
  init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
  func append(_ buffer: AVAudioPCMBuffer) throws { request.append(buffer) }
  func finish() throws { request.endAudio() }
}
