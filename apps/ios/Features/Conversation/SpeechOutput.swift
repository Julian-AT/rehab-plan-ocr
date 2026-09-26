import AVFoundation
import AppleServices
import SwiftUI

struct PlaybackWord: Identifiable {
  let id: Int
  let text: String
}
@MainActor @Observable final class SpeechOutput {
  enum Phase: String { case idle, preparing, playing, failed }
  static let shared = SpeechOutput()
  var turnID = UUID()
  var phase: Phase = .idle
  var status = "Bereit zum Vorlesen"
  var lastText = ""
  private(set) var preparedReply = ConversationReply()
  private(set) var level = 0.0
  private(set) var words: [PlaybackWord] = []
  private(set) var responseID = UUID()
  private(set) var spokenText = ""
  private(set) var lineVisible = false
  var onFinished: (() -> Void)?
  var onFailure: ((String) -> Void)?
  var speaking: Bool { phase == .playing || phase == .preparing }
  var voiceID: String {
    get {
      renderer.selectedVoice(preferredVoiceID)?.id ?? ""
    }
    set {
      preferredVoiceID = newValue
      UserDefaults.standard.set(newValue, forKey: renderer.preferenceKey)
    }
  }
  var availableVoices: [LocalVoice] { renderer.voices }
  var voiceName: String {
    renderer.selectedVoice(preferredVoiceID)?.name
      ?? "Nicht verfügbar"
  }
  var rate: Double {
    get {
      let v = UserDefaults.standard.double(forKey: "voice.neural.rate")
      return v == 0 ? 0.95 : min(1.25, max(0.75, v))
    }
    set { UserDefaults.standard.set(newValue, forKey: "voice.neural.rate") }
  }
  private let renderer: any LocalSpeechRendering
  private var preferredVoiceID: String?
  init(renderer: (any LocalSpeechRendering)? = nil) {
    #if REHA_PRIVATE_VICTORIA
      self.renderer = renderer ?? VictoriaSpeechRenderer()
    #else
      self.renderer = renderer ?? SystemSpeechRenderer()
    #endif
    preferredVoiceID = UserDefaults.standard.string(forKey: self.renderer.preferenceKey)
  }
  private var generation: UInt64 = 0
  private var task: Task<Void, Never>?
  private var meterTask: Task<Void, Never>?
  private var fadeTask: Task<Void, Never>?
  private var queue: [String] = []
  private var inputEnded = false
  private var wordIndex = 0
  private var currentMarks: [OutputWord] = []
  private var revealed = 0
  private var committed = 0
  private var announced = false
  #if DEBUG && targetEnvironment(simulator)
    private var measuredFrames = 0
    private var peakLevel = 0.0
    private func saveAudioEvidence() {
      guard ProcessInfo.processInfo.arguments.contains("--audio-evidence") else { return }
      let data: [String: Any] = [
        "playing_frames": measuredFrames, "peak_level": peakLevel, "spoken_text": spokenText,
        "visible_words": words.count,
      ]
      if let encoded = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys) {
        try? encoded.write(
          to: URL.documentsDirectory.appendingPathComponent("preview-audio-meter.json"),
          options: .atomic)
      }
    }
  #endif
  func speak(_ text: String) {
    speak(ConversationReply(text))
  }
  func speak(_ reply: ConversationReply) {
    beginResponse()
    for phrase in reply.phrases { appendPrepared(phrase) }
    finishResponse()
  }
  private func beginResponse() {
    stop()
    responseID = UUID()
    LocalDiagnostics.shared.record(.synthesis, .started, correlation: turnID.uuidString)
    words = []
    spokenText = ""
    lastText = ""
    preparedReply = ConversationReply()
    wordIndex = 0
    announced = UIAccessibility.isVoiceOverRunning
    phase = .preparing
    status = "Stimme wird vorbereitet …"
    inputEnded = false
    guard !announced else { return }
    let id = generation
    let speed = Float(rate)
    let renderer = renderer
    task = Task {
      do {
        guard
          let voice = renderer.selectedVoice(preferredVoiceID)
        else { throw SystemSpeechError.unavailable }
        var prepared: Task<RenderedSpeech, Error>?
        defer { prepared?.cancel() }
        while !Task.isCancelled && generation == id {
          if queue.isEmpty && prepared == nil {
            if inputEnded { break }
            try await Task.sleep(for: .milliseconds(25))
            continue
          }
          let audio: RenderedSpeech
          if let next = prepared {
            audio = try await next.value
            prepared = nil
          } else {
            let text = queue.removeFirst()
            audio = try await renderer.render(
              text: text, voice: voice, rate: speed, request: id)
          }
          guard generation == id else { return }
          try Task.checkCancellation()
          ConversationAudio.shared.stopPlayback()
          currentMarks = audio.marks
          revealed = 0
          committed = 0
          LocalDiagnostics.shared.record(.synthesis, .completed, correlation: turnID.uuidString)
          LocalDiagnostics.shared.record(.playback, .started, correlation: turnID.uuidString)
          phase = .playing
          status = "Wird vorgelesen"
          lineVisible = true
          if !queue.isEmpty {
            let text = queue.removeFirst()
            prepared = Task {
              try await renderer.render(
                text: text, voice: voice, rate: speed, request: id)
            }
          }
          meterTask = Task { [weak self] in
            while !Task.isCancelled {
              guard let self, self.generation == id else { return }
              self.updateWords(at: ConversationAudio.shared.playbackTime)
              self.level += (ConversationAudio.shared.level - self.level) * 0.4
              #if DEBUG && targetEnvironment(simulator)
                self.measuredFrames += 1
                self.peakLevel = max(self.peakLevel, self.level)
              #endif
              try? await Task.sleep(for: .milliseconds(30))
            }
          }
          let finished = try await ConversationAudio.shared.play(pcm: audio.pcm)
          meterTask?.cancel()
          meterTask = nil
          guard generation == id else { return }
          guard finished else { throw CancellationError() }
          updateWords(at: audio.duration)
          currentMarks = []
          phase = .preparing
          level = 0
        }
        guard generation == id, !Task.isCancelled else { return }
        complete()
      } catch {
        guard generation == id, !Task.isCancelled else { return }
        meterTask?.cancel()
        meterTask = nil
        level = 0
        lineVisible = false
        ConversationAudio.shared.stopPlayback()
        ConversationAudio.shared.releasePlayback()
        phase = .failed
        status = "Vorlesen fehlgeschlagen: \(userMessage(error))"
        onFailure?(status)
      }
    }
  }
  private func appendPrepared(_ phrase: ConversationReply.Phrase) {
    queue.append(phrase.speech)
    preparedReply.appendPrepared(phrase)
    lastText = preparedReply.text
  }
  private func finishResponse() {
    inputEnded = true
    if announced {
      UIAccessibility.post(notification: .announcement, argument: preparedReply.speech)
      phase = .idle
      status = "VoiceOver liest den Text vor"
      onFinished?()
    }
  }
  private func updateWords(at time: Double) {
    while revealed < currentMarks.count && currentMarks[revealed].start <= time {
      words.append(PlaybackWord(id: wordIndex, text: currentMarks[revealed].text))
      wordIndex += 1
      revealed += 1
      if words.count > 36 { words.removeFirst(words.count - 36) }
    }
    while committed < currentMarks.count && currentMarks[committed].end <= time {
      spokenText = joined(spokenText, currentMarks[committed].text)
      committed += 1
    }
  }
  private func joined(_ a: String, _ b: String) -> String { a.isEmpty ? b : a + " " + b }
  private func complete() {
    phase = .idle
    level = 0
    status = "Zu Ende vorgelesen"
    ConversationAudio.shared.releasePlayback()
    #if DEBUG && targetEnvironment(simulator)
      saveAudioEvidence()
    #endif
    onFinished?()
    fadeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      self?.lineVisible = false
    }
  }
  func stop() {
    updateWords(at: ConversationAudio.shared.playbackTime)
    generation &+= 1
    renderer.setRequest(generation)
    task?.cancel()
    task = nil
    meterTask?.cancel()
    meterTask = nil
    fadeTask?.cancel()
    fadeTask = nil
    ConversationAudio.shared.stopPlayback()
    ConversationAudio.shared.releasePlayback()
    currentMarks = []
    queue = []
    inputEnded = true
    lineVisible = false
    level = 0
    phase = .idle
    status = "Vorlesen beendet"
    #if DEBUG && targetEnvironment(simulator)
      saveAudioEvidence()
    #endif
  }
  func eraseSession() {
    stop()
    words = []
    spokenText = ""
    lastText = ""
    preparedReply = ConversationReply()
    wordIndex = 0
    status = "Bereit zum Vorlesen"
    onFinished = nil
    onFailure = nil
    UserDefaults.standard.removeObject(forKey: "voice.neural.id")
    UserDefaults.standard.removeObject(forKey: "voice.neural.rate")
    UserDefaults.standard.removeObject(forKey: "voice.system.id")
    preferredVoiceID = nil
    UserDefaults.standard.removeObject(forKey: VoiceAddress.key)
  }
  nonisolated static func phrases(_ text: String) -> [String] { SpeechPhrasing.phrases(text) }
}
