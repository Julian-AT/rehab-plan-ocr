import SwiftUI
import AVFoundation
@preconcurrency import Speech

/// Audio requests are swapped under the same lock used by the audio tap.
/// No microphone buffers or recognition results are stored on disk.
private final class SpeechInput: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func replace(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = next
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}
enum LocalSpeechError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}
/// Confined to the serial input tap; publishes at most 25 scalar levels/second.
private final class InputLevelMeter: @unchecked Sendable {
    private var lastTime = 0.0
    private var smoothed = 0.0
    private let publish: @Sendable (Double) -> Void
    init(publish: @escaping @Sendable (Double) -> Void) { self.publish = publish }
    func append(_ buffer: AVAudioPCMBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= 0.04 else { return }
        lastTime = now
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        var sum = 0.0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { let value = Double(channels[channel][frame]); sum += value * value }
        }
        let rms = sqrt(sum / Double(buffer.frameLength) / Double(buffer.format.channelCount))
        let level = min(1, pow(rms * 8, 0.65))
        smoothed += (level - smoothed) * 0.4
        publish(smoothed)
    }
}

@MainActor @Observable final class LocalSpeechRecorder {
    enum State { case idle, preparing, recording, finishing }
    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var level = 0.0
    private(set) var failure: String?
    private var committed = ""
    private var generation = UUID()
    private var segment = UUID()
    private var engine: AVAudioEngine?
    private let input = SpeechInput()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var finished = false
    private var recognitionFailed = false

    static func makeRecognizer() -> SFSpeechRecognizer? {
        ["de-AT", "de-DE"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.supportsOnDeviceRecognition }
    }
    func beginTurn() async throws {
        guard state == .idle else { return }
        SpeechOutput.shared.stop(); state = .preparing; transcript = ""; committed = ""; failure = nil
        generation = UUID(); let current = generation
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw LocalSpeechError.message("Erlaube den Mikrofonzugriff in den iPhone-Einstellungen.") }
            guard generation == current else { throw CancellationError() }
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
            }
            guard generation == current else { throw CancellationError() }
            guard authorization == .authorized else { throw LocalSpeechError.message("Erlaube die Spracherkennung in den iPhone-Einstellungen. Du kannst dein Anliegen auch in den Gesprächsdetails eingeben.") }
            guard let recognizer = Self.makeRecognizer() else {
                throw LocalSpeechError.message("Die deutsche Spracherkennung ist auf diesem Gerät noch nicht verfügbar. Aktiviere Deutsch unter Einstellungen → Allgemein → Tastatur → Diktierfunktion. In den Gesprächsdetails kannst du auch schreiben.")
            }
            self.recognizer = recognizer
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP]); try audio.setActive(true)
            let engine = AVAudioEngine(); let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw LocalSpeechError.message("Das Mikrofon ist gerade nicht verfügbar. Bitte erneut versuchen.") }
            let meter = InputLevelMeter { [weak self] value in
                Task { @MainActor in
                    guard let self, self.generation == current, self.state == .recording else { return }
                    self.level = value
                }
            }
            let input = input
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in meter.append(buffer); input.append(buffer) }
            self.engine = engine
            state = .recording; startSegment()
            engine.prepare(); try engine.start()
        } catch { if generation == current { cancelTurn() }; throw error }
    }
    private func startSegment() {
        guard let recognizer, state == .recording else { return }
        segment = UUID(); let segment = segment, current = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        finished = false; recognitionFailed = false
        input.replace(request)
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
                if self.state == .finishing { self.recognitionFailed = failed && !final && !noSpeech; return }
                if final || noSpeech {
                    // Silence and native task boundaries don't end the user's turn.
                    self.committed = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !self.committed.isEmpty { self.committed += " " }
                    self.recognition?.cancel(); self.startSegment()
                } else {
                    self.cancelTurn()
                    self.failure = "Die Spracherkennung wurde unterbrochen. Bitte erneut sprechen. Du kannst dein Anliegen auch in den Gesprächsdetails eingeben."
                }
            }
        }
    }
    func endTurn() async throws -> String {
        guard state == .recording else { return "" }
        state = .finishing; level = 0; let current = generation
        stopMicrophone(); input.replace(nil)
        // Wait for the final transcription, bounded if Apple's service stops responding.
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !finished && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(40))
            guard generation == current else { throw CancellationError() }
        }
        guard generation == current else { throw CancellationError() }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let failed = recognitionFailed || !finished
        recognition?.cancel(); recognition = nil; recognizer = nil; segment = UUID(); state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if failed { throw LocalSpeechError.message("Die Aufnahme konnte nicht vollständig erkannt werden. Bitte erneut sprechen.") }
        return text
    }
    private func stopMicrophone() {
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
    }
    func cancelTurn() {
        generation = UUID(); segment = UUID(); stopMicrophone(); input.replace(nil)
        recognition?.cancel(); recognition = nil; recognizer = nil
        state = .idle; level = 0; transcript = ""; committed = ""; failure = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
                    LabeledContent("Sprechtempo", value: rate.formatted(.number.precision(.fractionLength(2))) + "×")
                    Slider(value: $rate, in: 0.75...1.25, step: 0.05) { Text("Sprechtempo") }
                }
                Button(output.speaking ? "Wiedergabe beenden" : "Stimme anhören", systemImage: output.speaking ? "stop" : "play") {
                    if output.speaking { output.stop() }
                    else { output.speak("Am 14. September um 9 Uhr 15: Physiotherapie, Raum 2.14 in Laßnitzhöhe.") }
                }.accessibilityIdentifier("preview-voice").accessibilityValue(output.phase.rawValue)
                if output.phase == .preparing { ProgressView("Stimme vorbereiten …") }
                if output.phase == .failed { Text(output.status).foregroundStyle(.red) }
            } footer: { Text("Die Stimme ist bereits enthalten und funktioniert auf diesem iPhone ohne Internet.") }
            Section {
                LabeledContent("Spracherkennung", value: LocalSpeechRecorder.makeRecognizer() == nil ? "Nicht verfügbar" : "Auf diesem iPhone")
            } footer: { Text("Sprechen antippen und Mikrofon sowie Spracherkennung erlauben. Du brauchst keine Sprachdateien in der App einzurichten. Die Aufnahme bleibt auf dem iPhone und endet mit Fertig.") }

        }.pageTitle("Sprache")
            .onAppear { rate = output.rate }
            .onChange(of: rate) { output.stop(); output.rate = rate }
            .onDisappear { output.stop() }
    }
}
