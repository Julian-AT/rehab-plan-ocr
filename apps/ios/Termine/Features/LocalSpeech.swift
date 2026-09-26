import AVFoundation
@preconcurrency import Speech
import SwiftUI

/// The tap owns the VAD. A lock protects request swaps and the 400 ms pre-roll.
/// Audio exists only in memory and is discarded when the session ends.
private final class SpeechInput: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var ring: [AVAudioPCMBuffer] = []
  private var detector: VoiceActivityDetector?
  var frame: (@Sendable (Bool, Double) -> Void)?
  func replace(_ next: SFSpeechAudioBufferRecognitionRequest?, preRoll: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    request?.endAudio()
    request = next
    if preRoll { for buffer in ring { next?.append(buffer) } }
  }
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    if detector == nil { detector = try? VoiceActivityDetector(input: buffer.format) }
    detector?.append(buffer) { voice, level in frame?(voice, level) }
    request?.append(buffer)
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
    else { return }
    copy.frameLength = buffer.frameLength
    let from = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for (src, dst) in zip(from, to) {
      if let source = src.mData, let destination = dst.mData {
        memcpy(destination, source, Int(src.mDataByteSize))
      }
    }
    ring.append(copy)
    while ring.reduce(0.0, { $0 + Double($1.frameLength) / $1.format.sampleRate }) > 0.4 {
      ring.removeFirst()
    }
  }
}
enum LocalSpeechError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

@MainActor @Observable final class LocalSpeechRecorder {
  enum State { case idle, preparing, recording, finishing }
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
  private var recognizer: SFSpeechRecognizer?
  private var recognition: SFSpeechRecognitionTask?
  private var finished = false
  private var recognitionFailed = false
  private var endpoint = SpeechEndpoint()
  private var onset: [Bool] = []
  private var endpointSent = false
  private var monitor = false
  private var startedAt = 0.0

  static func makeRecognizer() -> SFSpeechRecognizer? {
    ["de-AT", "de-DE"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }.first {
      $0.supportsOnDeviceRecognition
    }
  }
  func beginTurn(preRoll: Bool = false) async throws {
    guard state == .idle else { return }
    state = .preparing
    transcript = ""
    committed = ""
    failure = nil
    let current = generation
    do {
      if !ConversationAudio.shared.microphoneActive {
        guard await AVAudioApplication.requestRecordPermission() else {
          throw LocalSpeechError.message("Mikrofonzugriff in den iPhone-Einstellungen erlauben.")
        }
        guard generation == current else { throw CancellationError() }
        let authorization = await withCheckedContinuation { continuation in
          SFSpeechRecognizer.requestAuthorization { @Sendable status in
            continuation.resume(returning: status)
          }
        }
        guard generation == current else { throw CancellationError() }
        guard authorization == .authorized else {
          throw LocalSpeechError.message(
            "Spracherkennung in den iPhone-Einstellungen erlauben. Texteingabe ist in den Gesprächsdetails möglich."
          )
        }
        guard let recognizer = Self.makeRecognizer() else {
          throw LocalSpeechError.message(
            "Die lokale deutsche Spracherkennung ist noch nicht verfügbar. Deutsch für die Diktierfunktion aktivieren. Texteingabe ist in den Gesprächsdetails möglich."
          )
        }
        self.recognizer = recognizer
        let input = SpeechInput()
        input.frame = { @Sendable [weak self] voice, level in
          Task { @MainActor in
            guard let self, self.generation == current else { return }
            self.receive(voice: voice, level: level)
          }
        }
        self.input = input
        try ConversationAudio.shared.startMicrophone { @Sendable buffer in input.append(buffer) }
      }
      guard generation == current else { throw CancellationError() }
      monitor = false
      onset = []
      endpoint = SpeechEndpoint(confirmedPreRoll: preRoll)
      endpointSent = false
      startedAt = ProcessInfo.processInfo.systemUptime
      state = .recording
      startSegment(preRoll: preRoll)
    } catch {
      if generation == current { cancelTurn() }
      throw error
    }
  }
  private func receive(voice: Bool, level: Double) {
    self.level += (level - self.level) * 0.4
    if monitor {
      onset.append(voice)
      if onset.count > 12 { onset.removeFirst() }
      // 200 ms of voiced evidence in 240 ms rejects short impacts/clicks.
      if onset.filter({ $0 }).count >= 10 {
        monitor = false
        onset = []
        onBargeIn?()
      }
    } else if state == .recording && !endpointSent {
      if endpoint.append(voice: voice, transcript: transcript) {
        endpointSent = true
        onEndpoint?()
      } else if ProcessInfo.processInfo.systemUptime - startedAt > 120 {
        // Bound even a continuously noisy input. Silence never creates a request.
        if endpoint.voicedFrames >= 5 {
          endpointSent = true
          onEndpoint?()
        } else {
          startedAt = ProcessInfo.processInfo.systemUptime
        }
      }
    }
  }
  func monitorForInterruption() {
    monitor = true
    onset = []
    level = 0
  }
  private func startSegment(preRoll: Bool = false) {
    guard let recognizer, state == .recording else { return }
    segment = UUID()
    let segment = segment
    let current = generation
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
    finished = false
    recognitionFailed = false
    input?.replace(request, preRoll: preRoll)
    recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal ?? false
      let noSpeech = (error as NSError?)?.code == 1110
      let failed = error != nil
      Task { @MainActor in
        guard let self, self.generation == current, self.segment == segment else { return }
        if let text { self.transcript = self.committed + text }
        guard final || failed else { return }
        self.finished = true
        if self.state == .finishing {
          self.recognitionFailed = failed && !final && !noSpeech
          return
        }
        if final || noSpeech {
          self.committed = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          if !self.committed.isEmpty { self.committed += " " }
          self.recognition?.cancel()
          self.startSegment()
        } else {
          let message =
            "Die Spracherkennung wurde unterbrochen. Bitte erneut starten oder in den Gesprächsdetails schreiben."
          self.cancelTurn()
          self.failure = message
          self.onFailure?(message)
        }
      }
    }
  }
  func endTurn() async throws -> String {
    guard state == .recording else { return "" }
    state = .finishing
    level = 0
    let current = generation
    input?.replace(nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !finished && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(40))
      guard generation == current else { throw CancellationError() }
    }
    guard generation == current else { throw CancellationError() }
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let failed = recognitionFailed || (!finished && text.isEmpty)
    recognition?.cancel()
    recognition = nil
    segment = UUID()
    state = .idle
    if failed {
      throw LocalSpeechError.message(
        "Die Aufnahme konnte nicht erkannt werden. Bitte erneut sprechen.")
    }
    return text
  }
  func cancelTurn() {
    generation = UUID()
    segment = UUID()
    monitor = false
    input?.replace(nil)
    input = nil
    if ConversationAudio.shared.microphoneActive {
      SpeechOutput.shared.stop()
      ConversationAudio.shared.shutdown()
    }
    recognition?.cancel()
    recognition = nil
    recognizer = nil
    state = .idle
    level = 0
    transcript = ""
    committed = ""
    failure = nil
  }
}
struct VoiceSettingsView: View {

  @State private var rate = SpeechOutput.shared.rate
  @State private var output = SpeechOutput.shared
  var body: some View {
    Form {
      Section {
        LabeledContent("Stimme", value: "Victoria · Deutsch")
        VStack(alignment: .leading) {
          LabeledContent(
            "Sprechtempo", value: rate.formatted(.number.precision(.fractionLength(2))) + "×")
          AppSlider(value: $rate, range: 0.75...1.25, step: 0.05, label: "Sprechtempo")
        }
        Button(
          output.speaking ? "Wiedergabe beenden" : "Stimme anhören",
          systemImage: output.speaking ? "stop" : "play"
        ) {
          if output.speaking {
            output.stop()
          } else {
            output.speak("Am 14. September um 9 Uhr 15: Physiotherapie, Raum 2.14 in Laßnitzhöhe.")
          }
        }.labelStyle(AppControlLabelStyle()).controlHeight()
          .accessibilityIdentifier("preview-voice").accessibilityValue(output.phase.rawValue)
        if output.phase == .preparing { ProgressView("Stimme vorbereiten …") }
        if output.phase == .failed { Text(output.status).foregroundStyle(AppPalette.destructive) }
      } footer: {
        Text("Die Stimme ist bereits enthalten und funktioniert auf diesem iPhone ohne Internet.")
          .foregroundStyle(AppPalette.secondaryText)
      }
      Section {
        LabeledContent(
          "Spracherkennung",
          value: LocalSpeechRecorder.makeRecognizer() == nil
            ? "Nicht verfügbar" : "Auf diesem iPhone")
      } footer: {
        Text(
          "Gespräch starten und Mikrofon sowie Spracherkennung erlauben. Zusätzliche Sprachdateien sind nicht nötig. Nach etwa 1,2 Sekunden Sprechpause beginnt die Antwort automatisch. Hineinsprechen unterbricht die Wiedergabe; das Gespräch kann jederzeit pausiert werden."
        ).foregroundStyle(AppPalette.secondaryText)
      }

    }.pageTitle("Sprache")
      .onAppear { rate = output.rate }
      .onChange(of: rate) {
        output.stop()
        output.rate = rate
      }
      .onDisappear { output.stop() }
  }
}
