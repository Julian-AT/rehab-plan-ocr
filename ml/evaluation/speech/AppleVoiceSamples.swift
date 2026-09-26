import AVFoundation
import Foundation

/// AVSpeechSynthesizer may deliver buffers off the main thread. The lock owns
/// the file and all callback state; no buffer crosses into an unrelated task.
private final class AudioWriter: @unchecked Sendable {
  private let lock = NSLock()
  private var file: AVAudioFile?
  private var finished = false
  private var failure: String?
  private var frames: AVAudioFramePosition = 0
  private var sampleRate = 0.0
  private var firstBuffer: Duration?
  private let start = ContinuousClock.now
  private let url: URL

  init(url: URL) { self.url = url }
  func append(_ buffer: AVAudioBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
    if pcm.frameLength == 0 {
      finished = true
      file = nil
      return
    }
    do {
      if file == nil {
        firstBuffer = start.duration(to: .now)
        sampleRate = pcm.format.sampleRate
        file = try AVAudioFile(
          forWriting: url,
          settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: pcm.format.channelCount, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
          ], commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
      }
      try file?.write(from: pcm)
      frames += AVAudioFramePosition(pcm.frameLength)
    } catch {
      failure = error.localizedDescription
      finished = true
      file = nil
    }
  }
  func snapshot() -> (done: Bool, error: String?, frames: Int64, rate: Double, first: Double) {
    lock.lock()
    defer { lock.unlock() }
    let components = (firstBuffer ?? .zero).components
    let milliseconds = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    return (finished, failure, frames, sampleRate, milliseconds)
  }
}

@main struct AppleVoiceSamples {
  @MainActor static func main() throws {
    let args = ProcessInfo.processInfo.arguments
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("de-") }
    if args.dropFirst() == ["--inventory"] {
      let records: [[String: Any]] = voices.map {
        [
          "name": $0.name, "id": $0.identifier, "language": $0.language,
          "quality": $0.quality.rawValue,
        ]
      }
      FileHandle.standardOutput.write(
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
      return
    }
    guard args.count == 4, let voice = voices.first(where: { $0.identifier == args[1] }) else {
      throw NSError(
        domain: "Listening", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Usage: AppleVoiceSamples --inventory | AVAILABLE_VOICE_ID PREPARED_JSON NEW_OUTPUT"
        ])
    }
    let input = try JSONSerialization.jsonObject(
      with: Data(contentsOf: URL(fileURLWithPath: args[2])))
    guard let request = input as? [String: Any],
      let samples = request["samples"] as? [[String: Any]],
      !samples.isEmpty, samples.count <= 100
    else { throw CocoaError(.fileReadCorruptFile) }
    let output = URL(fileURLWithPath: args[3], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: output.path) else {
      throw CocoaError(.fileWriteFileExists)
    }
    var seen = Set<String>()
    for sample in samples {
      guard let id = sample["id"] as? String, (1...64).contains(id.count),
        id.utf8.allSatisfy({
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            || $0 == 95
        }),
        seen.insert(id).inserted, let text = sample["spoken_text"] as? String,
        !text.isEmpty, text.count <= 4000
      else { throw CocoaError(.fileReadCorruptFile) }
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    let synthesizer = AVSpeechSynthesizer()
    var records: [[String: Any]] = []
    for sample in samples {
      let id = sample["id"] as! String
      let text = sample["spoken_text"] as! String
      let file = "\(id).wav"
      let writer = AudioWriter(url: output.appendingPathComponent(file))
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = voice
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      let start = ContinuousClock.now
      synthesizer.write(utterance) { writer.append($0) }
      while !writer.snapshot().done && start.duration(to: .now) < .seconds(60) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      }
      let state = writer.snapshot()
      guard state.done, state.error == nil, state.frames > 0, state.rate > 0 else {
        synthesizer.stopSpeaking(at: .immediate)
        throw NSError(
          domain: "Listening", code: 2,
          userInfo: [
            NSLocalizedDescriptionKey:
              state.error ?? "No complete local audio for \(id)"
          ])
      }
      let elapsed = start.duration(to: .now).components
      records.append([
        "id": id, "spoken_text": text, "path": file, "frames": state.frames,
        "sample_rate": state.rate, "duration_seconds": Double(state.frames) / state.rate,
        "first_buffer_ms": state.first,
        "synthesis_ms": Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
      ])
    }
    let report: [String: Any] = [
      "schema_version": 1, "route": "host-avspeech-write", "shipping_ios_route": false,
      "audio_startup_measured": false, "voice": voice.identifier, "voice_name": voice.name,
      "quality": voice.quality.rawValue, "language": voice.language,
      "system": ProcessInfo.processInfo.operatingSystemVersionString,
      "rate": AVSpeechUtteranceDefaultSpeechRate, "samples": records,
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
  }
}
