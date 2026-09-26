import SwiftUI
import AVFoundation
import RehaCore

struct PlaybackWord: Identifiable { let id: Int; let text: String }
@MainActor @Observable final class SpeechOutput {
    enum Phase: String { case idle, preparing, playing, failed }
    static let shared = SpeechOutput()
    var phase: Phase = .idle
    var status = "Bereit zum Vorlesen"
    var lastText = ""
    private(set) var level = 0.0
    private(set) var words: [PlaybackWord] = []
    private(set) var spokenText = ""
    private(set) var lineVisible = false
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var speaking: Bool { phase == .playing || phase == .preparing }
    var voiceID: String {
        get { "victoria" }
        set { UserDefaults.standard.set("victoria", forKey: "voice.neural.id") }
    }
    var rate: Double {
        get { let v = UserDefaults.standard.double(forKey: "voice.neural.rate"); return v == 0 ? 0.95 : min(1.25, max(0.75, v)) }
        set { UserDefaults.standard.set(newValue, forKey: "voice.neural.rate") }
    }
    private let renderer = NativeSpeech(modelDirectory: Bundle.main.resourceURL!.appendingPathComponent("kokoro-german").path)
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var queue: [String] = []
    private var inputEnded = false
    private var wordIndex = 0
    private var currentMarks: [SpeechWordMark] = []
    private var revealed = 0
    private var committed = 0
    private var announced = false
    #if DEBUG && targetEnvironment(simulator)
    private var measuredFrames = 0
    private var peakLevel = 0.0
    private func saveAudioEvidence() {
        guard ProcessInfo.processInfo.arguments.contains("--audio-evidence") else { return }
        let data: [String: Any] = ["playing_frames": measuredFrames, "peak_level": peakLevel, "spoken_text": spokenText, "visible_words": words.count]
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys) {
            try? encoded.write(to: URL.documentsDirectory.appendingPathComponent("preview-audio-meter.json"), options: .atomic)
        }
    }
    #endif
    func speak(_ text: String) {
        beginResponse()
        for phrase in Self.phrases(text) { appendPhrase(phrase) }
        finishResponse()
    }
    func beginResponse() {
        stop(); words = []; spokenText = ""; lastText = ""; wordIndex = 0
        announced = UIAccessibility.isVoiceOverRunning
        phase = .preparing; status = "Stimme wird vorbereitet …"; inputEnded = false
        guard !announced else { return }
        let id = generation, speed = Float(rate), renderer = renderer
        task = Task {
            do {
                var prepared: Task<SpeechRender, Error>?
                defer { prepared?.cancel() }
                while !Task.isCancelled && generation == id {
                    if queue.isEmpty && prepared == nil {
                        if inputEnded { break }
                        try await Task.sleep(for: .milliseconds(25)); continue
                    }
                    let audio: SpeechRender
                    if let next = prepared { audio = try await next.value; prepared = nil }
                    else { let text = queue.removeFirst(); audio = try await renderer.renderTimed(text: text, voice: "victoria", speed: speed, request: id) }
                    guard generation == id else { return }
                    try Task.checkCancellation()
                    ConversationAudio.shared.stopPlayback()
                    currentMarks = audio.marks; revealed = 0; committed = 0
                    phase = .playing; status = "Wird vorgelesen"; lineVisible = true
                    if !queue.isEmpty {
                        let text = queue.removeFirst()
                        prepared = Task { try await renderer.renderTimed(text: text, voice: "victoria", speed: speed, request: id) }
                    }
                    meterTask = Task { [weak self] in
                        while !Task.isCancelled {
                            guard let self, self.generation == id else { return }
                            self.updateWords(at: ConversationAudio.shared.playbackTime)
                            self.level += (ConversationAudio.shared.level - self.level) * 0.4
                            #if DEBUG && targetEnvironment(simulator)
                            self.measuredFrames += 1; self.peakLevel = max(self.peakLevel, self.level)
                            #endif
                            try? await Task.sleep(for: .milliseconds(30))
                        }
                    }
                    let finished = try await ConversationAudio.shared.play(wav: Data(audio.audio))
                    meterTask?.cancel(); meterTask = nil
                    guard generation == id else { return }
                    guard finished else { throw CancellationError() }
                    updateWords(at: audio.duration); currentMarks = []
                    phase = .preparing; level = 0
                }
                guard generation == id, !Task.isCancelled else { return }
                complete()
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                meterTask?.cancel(); meterTask = nil; level = 0; lineVisible = false
                ConversationAudio.shared.stopPlayback(); ConversationAudio.shared.releasePlayback()
                phase = .failed; status = "Vorlesen fehlgeschlagen: \(userMessage(error))"; onFailure?(status)
            }
        }
    }
    func appendPhrase(_ phrase: String) {
        guard !inputEnded, !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        queue.append(phrase); lastText = joined(lastText, phrase)
    }
    func finishResponse() {
        inputEnded = true
        if announced {
            UIAccessibility.post(notification: .announcement, argument: lastText)
            phase = .idle; status = "VoiceOver liest den Text vor"; onFinished?()
        }
    }
    private func updateWords(at time: Double) {
        while revealed < currentMarks.count && currentMarks[revealed].start <= time {
            words.append(PlaybackWord(id: wordIndex, text: currentMarks[revealed].text)); wordIndex += 1; revealed += 1
            if words.count > 36 { words.removeFirst(words.count - 36) }
        }
        while committed < currentMarks.count && currentMarks[committed].end <= time {
            spokenText = joined(spokenText, currentMarks[committed].text); committed += 1
        }
    }
    private func joined(_ a: String, _ b: String) -> String { a.isEmpty ? b : a + " " + b }
    private func complete() {
        phase = .idle; level = 0; status = "Zu Ende vorgelesen"
        ConversationAudio.shared.releasePlayback()
        #if DEBUG && targetEnvironment(simulator)
        saveAudioEvidence()
        #endif
        onFinished?()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }; self?.lineVisible = false
        }
    }
    func stop() {
        updateWords(at: ConversationAudio.shared.playbackTime)
        generation &+= 1; renderer.setRequest(request: generation)
        task?.cancel(); task = nil; meterTask?.cancel(); meterTask = nil; fadeTask?.cancel(); fadeTask = nil
        ConversationAudio.shared.stopPlayback(); ConversationAudio.shared.releasePlayback()
        currentMarks = []; queue = []; inputEnded = true; lineVisible = false; level = 0
        phase = .idle; status = "Vorlesen beendet"
        #if DEBUG && targetEnvironment(simulator)
        saveAudioEvidence()
        #endif
    }
    nonisolated static func phrases(_ text: String) -> [String] { SpeechPhrasing.phrases(text) }
}

struct SpeechControls: View {
    let text: String
    @State private var output = SpeechOutput.shared
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.section) { buttons }
                VStack(alignment: .leading, spacing: 0) { buttons }
            }
            if output.lastText == text {
                Text(output.status).font(.subheadline).foregroundStyle(output.phase == .failed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("speech-status").accessibilityValue(output.phase.rawValue)
            }
        }
        // Explicit styles isolate sibling actions inside List/Form rows.
        .buttonStyle(.borderless)
    }
    @ViewBuilder private var buttons: some View {
        Button { output.speak(text) } label: { Label("Vorlesen", systemImage: "speaker.wave.2").font(.subheadline).controlHeight() }.accessibilityIdentifier("read-aloud")
        Button { output.speak(text) } label: { Text("Wiederholen").font(.subheadline).controlHeight() }.accessibilityIdentifier("repeat-speech")
        Button { output.stop() } label: { Text("Stopp").font(.subheadline).controlHeight() }.disabled(!output.speaking).accessibilityIdentifier("stop-speech")
    }
}
