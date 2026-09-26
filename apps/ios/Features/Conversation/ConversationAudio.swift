import AVFoundation
import AppleServices
import Foundation

/// A single graph provides the echo reference for microphone and local speech.
@MainActor final class ConversationAudio {
  static let shared = ConversationAudio()
  private(set) var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var completion: CheckedContinuation<Bool, Never>?
  private var playbackID = UUID()
  private(set) var microphoneActive = false
  private var tapped = false
  private var graphGeneration = UUID()
  private var configurationObserver: NSObjectProtocol?
  private var inputFormat: AVAudioFormat?
  private var diagnosticID = UUID().uuidString
  var onConfigurationChange: (() -> Void)?
  private(set) var playbackDuration = 0.0
  private var pcm: AVAudioPCMBuffer?
  var playbackTime: Double {
    guard let player, let nodeTime = player.lastRenderTime,
      let time = player.playerTime(forNodeTime: nodeTime)
    else { return 0 }
    return min(playbackDuration, max(0, Double(time.sampleTime) / time.sampleRate))
  }
  var level: Double {
    guard let pcm, let values = pcm.floatChannelData?[0] else { return 0 }
    let start = min(Int(pcm.frameLength), Int(playbackTime * pcm.format.sampleRate))
    let end = min(Int(pcm.frameLength), start + 960)
    guard end > start else { return 0 }
    let rms = sqrt(
      (start..<end).reduce(0.0) { $0 + pow(Double(values[$1]), 2) } / Double(end - start))
    return min(1, pow(rms * 4, 0.65))
  }
  var microphoneConfiguration: (running: Bool, matchingFormats: Bool) {
    guard let engine, let inputFormat else { return (false, false) }
    return (
      engine.isRunning,
      inputFormat == engine.inputNode.outputFormat(forBus: 0)
        && inputFormat == engine.outputNode.inputFormat(forBus: 0)
    )
  }
  func startMicrophone(
    correlation: String, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) throws {
    shutdown()
    diagnosticID = correlation
    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(
        .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audio.setActive(true)
      guard !audio.currentRoute.inputs.isEmpty else {
        throw LocalSpeechError.message("Es ist kein Mikrofon als Audioeingang verfügbar.")
      }
      LocalDiagnostics.shared.record(
        .inputRoute, .completed, correlation: diagnosticID,
        count: audio.currentRoute.inputs.first?.portType == .builtInMic ? 1 : 2)
      let graph = AVAudioEngine()
      engine = graph
      LocalDiagnostics.shared.record(.audioEngine, .started, correlation: diagnosticID)
      let microphoneOnly = ProcessInfo.processInfo.arguments.contains("--microphone-only-trial")
      try graph.inputNode.setVoiceProcessingEnabled(!microphoneOnly)
      LocalDiagnostics.shared.record(
        .voiceProcessing, .completed, correlation: diagnosticID,
        count: microphoneOnly ? 0 : 1)
      attachPlayer(graph)
      let graphID = graphGeneration
      configurationObserver = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: graph, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.graphGeneration == graphID else { return }
          self.onConfigurationChange?()
        }
      }
      try prepareInput(graph, receive: receive)
      microphoneActive = true
    } catch {
      LocalDiagnostics.shared.record(
        .audioEngine, .failed, correlation: diagnosticID,
        count: Int(clamping: (error as NSError).code.magnitude))
      shutdown()
      throw error
    }
  }
  /// AVAudioEngine retains its nodes after an I/O change. Keep both the engine
  /// and active voice-processing session; recreating them retriggers routing.
  func restartMicrophone(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
    guard let engine, microphoneActive else {
      throw LocalSpeechError.message("Die Mikrofonverbindung ist nicht mehr verfügbar.")
    }
    stopPlayback()
    engine.stop()
    do {
      try prepareInput(engine, receive: receive)
    } catch {
      LocalDiagnostics.shared.record(
        .audioEngine, .failed, correlation: diagnosticID,
        count: Int(clamping: (error as NSError).code.magnitude))
      throw error
    }
  }
  private func prepareInput(
    _ graph: AVAudioEngine, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) throws {
    if tapped {
      graph.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    let format = graph.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0,
      !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty
    else { throw LocalSpeechError.message("Das Mikrofon ist gerade nicht verfügbar.") }
    // Voice processing requires identical formats on both I/O sides. The
    // mixer still converts prepared 24 kHz speech to this hardware format.
    graph.connect(graph.mainMixerNode, to: graph.outputNode, format: format)
    graph.inputNode.installTap(onBus: 0, bufferSize: 960, format: format) { @Sendable buffer, _ in
      receive(buffer)
    }
    tapped = true
    inputFormat = format
    LocalDiagnostics.shared.record(
      .audioSampleRate, .started, correlation: diagnosticID, count: Int(format.sampleRate))
    LocalDiagnostics.shared.record(
      .audioChannels, .started, correlation: diagnosticID, count: Int(format.channelCount))
    LocalDiagnostics.shared.record(
      .audioPCMFormat, .completed, correlation: diagnosticID,
      count: Int(format.commonFormat.rawValue) * 2 + (format.isInterleaved ? 1 : 0))
    graph.prepare()
    try graph.start()
    LocalDiagnostics.shared.record(.audioEngine, .completed, correlation: diagnosticID)
  }
  private func attachPlayer(_ graph: AVAudioEngine) {
    let node = AVAudioPlayerNode()
    graph.attach(node)
    graph.connect(
      node, to: graph.mainMixerNode,
      format: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
    player = node
  }
  func play(pcm decoded: SpeechPCM) async throws -> Bool {
    try Task.checkCancellation()
    stopPlayback()
    let id = playbackID
    guard !decoded.samples.isEmpty, decoded.samples.count <= SpeechPCM.maximumFrames else {
      throw SpeechPCMError.invalidFile
    }
    if engine == nil {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try audio.setActive(true)
      let graph = AVAudioEngine()
      engine = graph
      attachPlayer(graph)
      graph.prepare()
      try graph.start()
    }
    guard engine?.isRunning == true else {
      throw LocalSpeechError.message(
        "Die Audioausgabe wurde unterbrochen. Bitte das Gespräch erneut starten.")
    }
    guard let player,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!,
        frameCapacity: AVAudioFrameCount(decoded.samples.count))
    else {
      throw LocalSpeechError.message("Die Sprachdatei ist ungültig.")
    }
    buffer.frameLength = buffer.frameCapacity
    decoded.samples.withUnsafeBufferPointer { samples in
      buffer.floatChannelData![0].update(from: samples.baseAddress!, count: samples.count)
    }
    pcm = buffer
    playbackDuration = Double(buffer.frameLength) / 24_000
    return await withCheckedContinuation { continuation in
      completion = continuation
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
        @Sendable [weak self] _ in
        Task { @MainActor in
          guard let self, self.playbackID == id else { return }
          // Playback is finished even when the microphone keeps the graph alive.
          // Preserve duration/timing until SpeechOutput accounts for the final words.
          self.pcm = nil
          self.completion?.resume(returning: true)
          self.completion = nil
        }
      }
      player.play()
    }
  }
  func stopPlayback() {
    playbackID = UUID()
    player?.stop()
    pcm = nil
    playbackDuration = 0
    completion?.resume(returning: false)
    completion = nil
  }
  func releasePlayback() { if !microphoneActive { shutdown() } }
  func shutdown() {
    graphGeneration = UUID()
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    onConfigurationChange = nil
    stopPlayback()
    engine?.stop()
    if tapped { engine?.inputNode.removeTap(onBus: 0) }
    tapped = false
    inputFormat = nil
    engine = nil
    player = nil
    microphoneActive = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
