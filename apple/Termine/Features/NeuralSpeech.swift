import SwiftUI
import AVFoundation
import RehaCore

@MainActor @Observable final class SpeechOutput: NSObject, AVAudioPlayerDelegate {
    enum Phase: String { case idle, preparing, playing, failed }
    static let shared = SpeechOutput()
    var phase: Phase = .idle
    var status = "Bereit zum Vorlesen"
    var lastText = ""
    var speaking: Bool { phase == .playing || phase == .preparing }
    var voiceID: String {
        get { UserDefaults.standard.string(forKey: "voice.neural.id") ?? "F1" }
        set { UserDefaults.standard.set(newValue, forKey: "voice.neural.id") }
    }
    var rate: Double {
        get { let v = UserDefaults.standard.double(forKey: "voice.neural.rate"); return v == 0 ? 0.95 : min(1.25, max(0.75, v)) }
        set { UserDefaults.standard.set(newValue, forKey: "voice.neural.rate") }
    }
    private let renderer = NativeSpeech(modelDirectory: Bundle.main.resourceURL!.appendingPathComponent("supertonic-3").path)
    private var player: AVAudioPlayer?
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var playback: CheckedContinuation<Bool, Never>?
    private var cachedKey = ""
    private var cachedAudio: [Data] = []
    func speak(_ text: String) {
        stop(); lastText = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Kein Text zum Vorlesen"; return }
        if UIAccessibility.isVoiceOverRunning {
            status = "VoiceOver liest den Text vor"
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        let id = generation, voice = voiceID, speed = Float(rate)
        let key = "\(voice)|\(speed)|\(text)"
        let cached = cachedKey == key ? cachedAudio : []
        phase = .preparing; status = "Stimme wird vorbereitet …"
        task = Task {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try session.setActive(true)
                let phrases = Self.phrases(text)
                var rendered: [Data] = []
                var pending: Task<Data, Error>?
                defer { pending?.cancel() }
                for (index, phrase) in phrases.enumerated() {
                    try Task.checkCancellation()
                    let data: Data
                    if index < cached.count { data = cached[index] }
                    else if let prepared = pending { data = try await prepared.value; pending = nil }
                    else { data = Data(try await renderer.render(text: phrase, voice: voice, speed: speed, request: id)) }
                    guard generation == id else { return }
                    try Task.checkCancellation()
                    let player = try AVAudioPlayer(data: data)
                    self.player = player; player.delegate = self
                    player.prepareToPlay()
                    // Prepare the next phrase while this one plays, without saving audio.
                    if index + 1 < phrases.count && cached.isEmpty {
                        let next = phrases[index + 1], renderer = self.renderer
                        pending = Task { Data(try await renderer.render(text: next, voice: voice, speed: speed, request: id)) }
                    }
                    phase = .playing; status = "Wird vorgelesen"
                    let finished = await withCheckedContinuation { continuation in
                        playback = continuation
                        if !player.play() { playback = nil; continuation.resume(returning: false) }
                    }
                    guard generation == id else { return }
                    guard finished else { throw LocalSpeechError.message("Audio konnte nicht abgespielt werden. Bitte erneut versuchen.") }
                    rendered.append(data)
                }
                guard generation == id else { return }
                cachedKey = key; cachedAudio = rendered
                phase = .idle; status = "Zu Ende vorgelesen"; player = nil
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                player?.stop(); player = nil; phase = .failed
                status = "Vorlesen fehlgeschlagen: \(error.localizedDescription)"
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
    func stop() {
        generation &+= 1; renderer.setRequest(request: generation)
        task?.cancel(); task = nil; player?.stop(); player = nil
        playback?.resume(returning: false); playback = nil
        phase = .idle; status = "Vorlesen beendet"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == identifier else { return }
            self.playback?.resume(returning: flag); self.playback = nil
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == identifier else { return }
            self.playback?.resume(returning: false); self.playback = nil
        }
    }
    static func phrases(_ text: String) -> [String] {
        var chunks: [String] = [], current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if current.count + word.count > 220 && !current.isEmpty { chunks.append(current); current = "" }
            if !current.isEmpty { current += " " }; current += word
            if current.count > 40 && (word.hasSuffix("!") || word.hasSuffix("?") || (word.hasSuffix(".") && word.dropLast().last?.isNumber == false)) {
                chunks.append(current); current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

struct SpeechControls: View {
    let text: String
    @State private var output = SpeechOutput.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { buttons }
                VStack(alignment: .leading, spacing: 0) { buttons }
            }
            if output.lastText == text {
                Text(output.status).font(.caption).foregroundStyle(output.phase == .failed ? .red : .secondary)
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
