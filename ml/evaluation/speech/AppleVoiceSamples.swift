import AVFoundation
import CryptoKit
import Foundation

@main struct AppleVoiceSamples {
  @MainActor static func main() async throws {
    let args = ProcessInfo.processInfo.arguments
    let renderer = SystemSpeechRenderer()
    let voices = renderer.voices
    if args.dropFirst() == ["--inventory"] {
      let records: [[String: Any]] = voices.map {
        [
          "name": $0.name, "id": $0.id, "language": $0.language,
          "quality": AVSpeechSynthesisVoice(identifier: $0.id)?.quality.rawValue ?? 0,
          "availability": "enumerated-by-local-system", "offline_device_verified": false,
        ]
      }
      FileHandle.standardOutput.write(
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]))
      return
    }
    guard args.count == 4, let voice = renderer.selectedVoice(args[1]) else {
      throw NSError(
        domain: "Listening", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Usage: AppleVoiceSamples --inventory | AVAILABLE_VOICE_ID PREPARED_JSON NEW_OUTPUT"
        ])
    }
    let prepared = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let input = try JSONSerialization.jsonObject(with: prepared)
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
        !text.isEmpty, text.utf16.count <= 4_000
      else { throw CocoaError(.fileReadCorruptFile) }
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
    var records: [[String: Any]] = []
    var failures = 0
    for (index, sample) in samples.enumerated() {
      let id = sample["id"] as! String
      let text = sample["spoken_text"] as! String
      let generation = UInt64(index + 1)
      renderer.setRequest(generation)
      let start = ContinuousClock.now
      do {
        let rendered = try await renderer.render(
          text: text, voice: voice, rate: 0.95, request: generation)
        let audio = try SpeechSampleFile.wav(rendered.pcm)
        let file = "\(id).wav"
        try audio.write(to: output.appendingPathComponent(file), options: .atomic)
        let elapsed = rendered.preparation.components
        records.append([
          "id": id, "status": "complete", "spoken_text": text, "path": file,
          "sha256": SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined(),
          "frames": rendered.pcm.samples.count, "sample_rate": SpeechPCM.sampleRate,
          "channels": 1, "duration_seconds": rendered.duration,
          "synthesis_ms": Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
          "marks": rendered.marks.map { ["text": $0.text, "start": $0.start, "end": $0.end] },
        ])
      } catch {
        failures += 1
        let elapsed = start.duration(to: .now).components
        records.append([
          "id": id, "status": "failed", "spoken_text": text,
          "error_type": String(reflecting: type(of: error)), "error": error.localizedDescription,
          "elapsed_ms": Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
        ])
      }
      // Keep every completed/error case if a later system voice operation is interrupted.
      let report: [String: Any] = [
        "schema_version": 2, "route": "host-product-system-speech-renderer",
        "renderer": "SystemSpeechRenderer", "shared_product_renderer": true,
        "shipping_ios_route": false, "physical_device": false,
        "audio_startup_measured": false, "first_buffer_measured": false,
        "status": records.count < samples.count
          ? "rendering" : failures == 0 ? "complete" : "failed",
        "expected_samples": samples.count, "failed_samples": failures,
        "voice": voice.id, "voice_name": voice.name, "language": voice.language,
        "quality": AVSpeechSynthesisVoice(identifier: voice.id)?.quality.rawValue ?? 0,
        "system": ProcessInfo.processInfo.operatingSystemVersionString,
        "rate_multiplier": 0.95, "sample_rate": SpeechPCM.sampleRate,
        "format": "PCM16-LE-mono-WAV",
        "word_progress_basis": "system-delegate-PCM-buffer-boundaries",
        "prepared_text_sha256": SHA256.hash(data: prepared).map { String(format: "%02x", $0) }
          .joined(),
        "samples": records,
      ]
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
    }
    renderer.setRequest(UInt64(samples.count + 1))
    if failures > 0 {
      throw NSError(
        domain: "Listening", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "\(failures) incomplete samples; see retained manifest"
        ])
    }
  }
}
