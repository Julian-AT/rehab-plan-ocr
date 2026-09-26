import AVFoundation
import CryptoKit
import Foundation
import Speech

/// File-only host control through the shipping worker/provider. Only --setup
/// requests assets; microphone, legacy authorization and calendars are never used.
@main struct AppSpeechProviderProbe {
  @MainActor static func main() async throws {
    var args = Array(CommandLine.arguments.dropFirst())
    let setup = args.first == "--setup"
    if setup { args.removeFirst() }
    guard args.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let output = URL(fileURLWithPath: args[1]).standardizedFileURL.resolvingSymlinksInPath()
    let privateRoot = root.appendingPathComponent(".local").resolvingSymlinksInPath().path + "/"
    guard output.path.hasPrefix(privateRoot),
      !FileManager.default.fileExists(atPath: output.path)
    else { throw CocoaError(.fileWriteFileExists) }
    let audio = URL(fileURLWithPath: args[0])
    let sourceHash = hash(try Data(contentsOf: audio))
    var downloaded = false
    if setup {
      guard
        let locale = await SpeechTranscriber.supportedLocale(
          equivalentTo: Locale(identifier: "de-AT"))
      else { throw RecognitionFailure.unsupportedLocale }
      let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        try await request.downloadAndInstall()
        downloaded = true
      }
    }
    let started = ProcessInfo.processInfo.systemUptime
    let provider = try await SpeechRecognitionProviders.ready(titles: [])
    guard provider.diagnosticCode == 1 else { throw RecognitionFailure.assetsMissing }
    var resultCount = 0
    var finalCount = 0
    var firstResultMS: Double?
    var completion: RecognitionCompletion?
    var voicedFrames = 0
    var workerError: String?
    let sink = try await provider.start { event in
      switch event {
      case .result(let result):
        resultCount += 1
        if result.isFinal { finalCount += 1 }
        if firstResultMS == nil { firstResultMS = (result.receivedAt - started) * 1000 }
      case .completed(let outcome): completion = outcome
      }
    }
    let channel = SpeechInputChannel()
    let worker = SpeechInput(channel: channel)
    worker.replace(sink)
    let observations = Task {
      do {
        for try await packet in channel.stream {
          try channel.checkActive()
          voicedFrames += packet.voicedFrames.filter { $0 }.count
        }
      } catch { workerError = String(describing: error) }
    }
    defer {
      worker.cancel()
      observations.cancel()
      provider.cancel()
    }
    // File I/O and pacing stay outside the UI/recognition executor. SpeechInput
    // owns each copied buffer before this feeder reuses its read buffer.
    let inputFormat = try await Task.detached {
      let file = try AVAudioFile(forReading: audio)
      guard file.length > 0,
        Double(file.length) / file.processingFormat.sampleRate <= 60,
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat,
          frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate / 50))
      else { throw RecognitionFailure.invalidAudio }
      while file.framePosition < file.length {
        try Task.checkCancellation()
        try file.read(into: buffer, frameCount: buffer.frameCapacity)
        worker.append(buffer)
        try await Task.sleep(for: .milliseconds(20))
      }
      worker.replace(nil)  // Ordered converter drain and explicit end-of-input.
      return "\(file.processingFormat.sampleRate) Hz / \(file.processingFormat.channelCount) ch"
    }.value
    let inputEnded = ProcessInfo.processInfo.systemUptime
    while completion == nil, ProcessInfo.processInfo.systemUptime - inputEnded < 12 {
      try await Task.sleep(for: .milliseconds(50))
    }
    let outcome = completion ?? .failed(.finalizationTimeout)
    var transcript: String?
    let state: String
    switch outcome {
    case .finalized(let text):
      state = "finalized"
      transcript = text
    case .noSpeech: state = "no_speech"
    case .cancelled: state = "cancelled"
    case .failed(let failure): state = failure.rawValue
    }
    var identities: [String: String] = [:]
    for name in [
      "SpeechRecognitionProvider", "RecognitionTurn", "InputAudio", "SpeechInput",
      "SpeechInputChannel", "CalendarVocabulary", "SpeechAssetReadiness",
    ] {
      let path = "apps/ios/Features/Conversation/\(name).swift"
      identities[path] = hash(try Data(contentsOf: root.appendingPathComponent(path)))
    }
    let report: [String: Any] = [
      "schema_version": 1, "provider": "Apple SpeechAnalyzer through app SpeechInput",
      "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
      "locale": provider.locale.identifier, "audio_sha256": sourceHash,
      "input_format": inputFormat, "source_identities": identities,
      "result_count": resultCount, "final_count": finalCount, "voiced_frames": voicedFrames,
      "first_result_ms": firstResultMS as Any? ?? NSNull(),
      "finish_to_completion_ms": (ProcessInfo.processInfo.systemUptime - inputEnded) * 1000,
      "outcome": state, "transcript": transcript as Any? ?? NSNull(),
      "worker_error": workerError as Any? ?? NSNull(), "physical_device": false,
      "microphone_used": false, "assets_downloaded": downloaded, "qualified": false,
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    guard case .finalized = outcome, workerError == nil else {
      throw RecognitionFailure.incomplete
    }
  }
  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
