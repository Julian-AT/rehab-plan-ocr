import AVFoundation
import CFvad
import Foundation

/// Access is serialized by the input tap. The pinned C VAD owns no audio device.
final class VoiceActivityDetector: @unchecked Sendable {
  private let detector: OpaquePointer
  private let converter: AVAudioConverter
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
  private var samples: [Int16] = []
  init(input: AVAudioFormat) throws {
    guard let detector = fvad_new() else {
      throw LocalSpeechError.message("Die Spracherkennung konnte nicht vorbereitet werden.")
    }
    guard let converter = AVAudioConverter(from: input, to: format) else {
      fvad_free(detector)
      throw LocalSpeechError.message("Das Mikrofonformat kann nicht verarbeitet werden.")
    }
    self.detector = detector
    self.converter = converter
    guard fvad_set_sample_rate(detector, 16_000) == 0, fvad_set_mode(detector, 2) == 0 else {
      throw LocalSpeechError.message(
        "Die Sprachaktivitätserkennung konnte nicht eingerichtet werden.")
    }
  }
  deinit { fvad_free(detector) }
  func append(_ buffer: AVAudioPCMBuffer, frame: (Bool, Double) -> Void) throws {
    let capacity = AVAudioFrameCount(
      ceil(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 320)
    guard buffer.format == converter.inputFormat,
      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    else {
      throw LocalSpeechError.message("Das Mikrofonformat hat sich geändert. Bitte erneut starten.")
    }
    let input = ConverterInput(buffer)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, status in input.take(status) }
    guard error == nil, status != .error, status != .endOfStream,
      let channel = output.int16ChannelData?[0]
    else {
      throw LocalSpeechError.message(
        "Das Mikrofonformat konnte nicht umgewandelt werden. Bitte erneut starten.")
    }
    samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    var offset = 0
    while samples.count - offset >= 320 {
      let part = Array(samples[offset..<(offset + 320)])
      let rms = sqrt(part.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / 320)
      let decision = part.withUnsafeBufferPointer { fvad_process(detector, $0.baseAddress!, 320) }
      guard decision >= 0 else {
        throw LocalSpeechError.message(
          "Die Sprachaktivitätserkennung wurde unterbrochen. Bitte erneut starten.")
      }
      frame(decision == 1 && rms > 0.003, min(1, pow(rms * 8, 0.65)))
      offset += 320
    }
    samples.removeFirst(offset)
  }
}

/// The converter receives the tap buffer once; access to consumption state is locked.
private final class ConverterInput: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: AVAudioPCMBuffer?
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  func take(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer else {
      status.pointee = .noDataNow
      return nil
    }
    self.buffer = nil
    status.pointee = .haveData
    return buffer
  }
}

/// A single graph provides the echo reference for microphone AND Victoria.
@MainActor final class ConversationAudio {
  static let shared = ConversationAudio()
  private(set) var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var completion: CheckedContinuation<Bool, Never>?
  private var playbackID = UUID()
  private(set) var microphoneActive = false
  private var tapped = false
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
  func startMicrophone(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
    shutdown()
    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(
        .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audio.setActive(true)
      let graph = AVAudioEngine()
      engine = graph
      try graph.inputNode.setVoiceProcessingEnabled(true)
      let format = graph.inputNode.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw LocalSpeechError.message("Das Mikrofon ist gerade nicht verfügbar.")
      }
      graph.inputNode.installTap(onBus: 0, bufferSize: 960, format: format) { @Sendable buffer, _ in
        receive(buffer)
      }
      tapped = true
      microphoneActive = true
      attachPlayer(graph)
      graph.prepare()
      try graph.start()
    } catch {
      shutdown()
      throw error
    }
  }
  private func attachPlayer(_ graph: AVAudioEngine) {
    let node = AVAudioPlayerNode()
    graph.attach(node)
    graph.connect(
      node, to: graph.mainMixerNode,
      format: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
    player = node
  }
  func play(wav: Data) async throws -> Bool {
    stopPlayback()
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
    // The internal renderer always emits a canonical 44-byte PCM16 WAV.
    guard wav.count > 44, wav.prefix(4) == Data("RIFF".utf8), let player,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!,
        frameCapacity: AVAudioFrameCount((wav.count - 44) / 2))
    else {
      throw LocalSpeechError.message("Die Sprachdatei ist ungültig.")
    }
    buffer.frameLength = buffer.frameCapacity
    wav.withUnsafeBytes { raw in
      for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![0][i] =
          Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 44 + i * 2, as: Int16.self)))
          / 32768
      }
    }
    pcm = buffer
    playbackDuration = Double(buffer.frameLength) / 24_000
    let id = UUID()
    playbackID = id
    return await withCheckedContinuation { continuation in
      completion = continuation
      player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
        @Sendable [weak self] _ in
        Task { @MainActor in
          guard let self, self.playbackID == id else { return }
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
    stopPlayback()
    engine?.stop()
    if tapped { engine?.inputNode.removeTap(onBus: 0) }
    tapped = false
    engine = nil
    player = nil
    microphoneActive = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
