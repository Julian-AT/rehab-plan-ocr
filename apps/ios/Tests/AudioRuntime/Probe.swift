import AVFoundation
import SwiftUI

@main struct AudioEngineProbe: App {
  var body: some Scene { WindowGroup { Text("Audio runtime probe").task { await run() } } }
  @MainActor func run() async {
    func stage(_ text: String) {
      print("AUDIO_PROBE \(text)")
      let identifier = ProcessInfo.processInfo.arguments.last ?? ""
      let report = ["stage": text, "run_id": identifier]
      if let data = try? JSONSerialization.data(withJSONObject: report) {
        try? data.write(
          to: URL.documentsDirectory.appendingPathComponent("audio-probe.json"), options: .atomic)
      }
    }
    do {
      stage("session")
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true)
      stage("engine")
      let graph = AVAudioEngine()
      let player = AVAudioPlayerNode()
      graph.attach(player)
      stage("mixer")
      let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
      graph.connect(player, to: graph.mainMixerNode, format: format)
      stage("prepare")
      graph.prepare()
      try graph.start()
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 6_000)!
      buffer.frameLength = buffer.frameCapacity
      for i in 0..<6_000 {
        buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 24_000)) * 0.02
      }
      stage("play")
      player.scheduleBuffer(buffer, completionHandler: nil)
      player.play()
      try await Task.sleep(for: .seconds(1))
      guard let rendered = player.lastRenderTime, player.playerTime(forNodeTime: rendered) != nil
      else {
        stage("no render time")
        exit(2)
      }
      player.stop()
      graph.stop()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
      stage("passed")
      exit(0)
    } catch {
      stage("failed: \(error)")
      exit(1)
    }
  }
}
