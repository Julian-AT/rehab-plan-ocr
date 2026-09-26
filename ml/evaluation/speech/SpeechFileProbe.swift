import AVFoundation
import CryptoKit
import Foundation
import Speech

/// Host-only file evaluation. Asset installation is an explicit, separate mode;
/// transcription never requests a microphone, authorization or asset download.
@main struct SpeechFileProbe {
  struct Request: Decodable {
    let runID: UUID
    let locale: String
    let audioPath: String
    let audioSHA256: String
  }
  struct Segment: Codable, Sendable {
    let text: String
    let start: Double
    let duration: Double
  }
  struct Transcript: Encodable {
    let runID: UUID
    let requestedLocale: String
    let resolvedLocale: String
    let audioSHA256: String
    let segments: [Segment]
    let seconds: Double
    let provider = "Apple SpeechTranscriber"
    let downloadRequested = false
    let microphoneUsed = false
    let physicalDevice = false
    let stage = "completed"
  }
  static func emit(_ value: Any) throws {
    FileHandle.standardOutput.write(
      try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]))
    print()
  }
  static func module(_ identifier: String) async throws -> (SpeechTranscriber, Locale) {
    guard SpeechTranscriber.isAvailable,
      let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: identifier))
    else { throw CocoaError(.featureUnsupported) }
    return (SpeechTranscriber(locale: locale, preset: .transcription), locale)
  }
  static func main() async throws {
    let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
    if args == ["--inventory"] {
      var entries: [[String: Any]] = []
      for identifier in ["de-AT", "de-DE"] {
        let (transcriber, locale) = try await module(identifier)
        let legacy = SFSpeechRecognizer(locale: locale)
        entries.append([
          "requested_locale": identifier, "resolved_locale": locale.identifier,
          "asset_status": String(
            describing: await AssetInventory.status(forModules: [transcriber])),
          "legacy_authorization": SFSpeechRecognizer.authorizationStatus().rawValue,
          "legacy_on_device": legacy?.supportsOnDeviceRecognition ?? false,
          "legacy_available": legacy?.isAvailable ?? false,
        ])
      }
      try emit([
        "system": ProcessInfo.processInfo.operatingSystemVersionString, "locales": entries,
        "download_requested": false, "microphone_used": false,
      ])
      return
    }
    if args.count == 2, args[0] == "--setup" {
      let (transcriber, locale) = try await module(args[1])
      let before = await AssetInventory.status(forModules: [transcriber])
      var requested = false
      if before != .installed,
        let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
      {
        requested = true
        try await request.downloadAndInstall()
      }
      let after = await AssetInventory.status(forModules: [transcriber])
      try emit([
        "locale": locale.identifier, "before": String(describing: before),
        "after": String(describing: after), "download_requested": requested,
        "microphone_used": false, "installed": after == .installed,
      ])
      return
    }
    guard args.count == 3, args[0] == "--transcribe" else {
      throw NSError(
        domain: "SpeechFileProbe", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Use --inventory, --setup LOCALE or --transcribe INPUT_JSON NEW_OUTPUT_JSON"
        ])
    }
    let output = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: output.path) else {
      throw CocoaError(.fileWriteFileExists)
    }
    let request = try JSONDecoder().decode(
      Request.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    let audioURL = URL(fileURLWithPath: request.audioPath)
    let audioHash = SHA256.hash(data: try Data(contentsOf: audioURL))
      .map { String(format: "%02x", $0) }.joined()
    guard audioHash == request.audioSHA256 else { throw CocoaError(.fileReadCorruptFile) }
    let (transcriber, locale) = try await module(request.locale)
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    let file = try AVAudioFile(forReading: audioURL)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let started = ContinuousClock.now
    let results = Task { () throws -> [Segment] in
      var segments: [Segment] = []
      for try await result in transcriber.results where result.isFinal {
        segments.append(
          Segment(
            text: String(result.text.characters), start: result.range.start.seconds,
            duration: result.range.duration.seconds))
      }
      return segments
    }
    do {
      guard let last = try await analyzer.analyzeSequence(from: file) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      try await analyzer.finalizeAndFinish(through: last)
      let segments = try await results.value
      let elapsed = started.duration(to: .now).components
      let transcript = Transcript(
        runID: request.runID, requestedLocale: request.locale, resolvedLocale: locale.identifier,
        audioSHA256: audioHash, segments: segments,
        seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(transcript).write(to: output, options: .atomic)
    } catch {
      results.cancel()
      await analyzer.cancelAndFinishNow()
      throw error
    }
  }
}
