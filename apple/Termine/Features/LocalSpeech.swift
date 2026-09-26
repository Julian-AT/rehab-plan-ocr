import SwiftUI
import AVFoundation
import Speech
import FoundationModels

@MainActor @Observable final class LocalSpeechAssets {
    var status = "Sprachdateien prüfen"
    var ready = false
    var busy = false
    var progress = 0.0
    private var task: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    static func transcriber() async throws -> SpeechTranscriber {
        let austrian = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "de-AT"))
        let german = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "de-DE"))
        guard SpeechTranscriber.isAvailable, let locale = austrian ?? german else {
            throw LocalSpeechError.message("Lokale deutsche Spracherkennung ist auf diesem Gerät nicht verfügbar.")
        }
        return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }
    func check() async {
        do {
            let module = try await Self.transcriber()
            ready = await AssetInventory.status(forModules: [module]) == .installed
            if ready {
                let analyzer = SpeechAnalyzer(modules: [module]); let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
                try await analyzer.prepareToAnalyze(in: format); await analyzer.cancelAndFinishNow()
            }
            try Task.checkCancellation()
            status = ready ? "Offline bereit" : "Sprachdateien einrichten. Dafür wird einmalig Internet benötigt."
        } catch { ready = false; status = error.localizedDescription }
    }
    func prepareAssets() {
        guard !busy else { return }; busy = true; ready = false; progress = 0; status = "Sprachdateien werden eingerichtet …"
        task = Task {
            defer { busy = false; progressTask?.cancel(); progressTask = nil }
            do {
                let module = try await Self.transcriber()
                for locale in module.selectedLocales { try await AssetInventory.reserve(locale: locale) }
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    progressTask = Task { while !Task.isCancelled { progress = request.progress.fractionCompleted; try? await Task.sleep(for: .milliseconds(200)) } }
                    try await request.downloadAndInstall()
                }
                try Task.checkCancellation(); await check()
            } catch { ready = false; status = Task.isCancelled ? "Einrichtung abgebrochen. Du kannst sie wiederholen." : error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); progressTask?.cancel(); ready = false; status = "Einrichtung abgebrochen." }
}
enum LocalSpeechError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}
/// The converter consumes one tap buffer synchronously. The lock also makes
/// the input block's single-delivery state safe under its Sendable contract.
private final class ConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard !supplied else { return nil }
        supplied = true; return buffer
    }
}
/// AVAudioConverter is confined to the audio tap's serial callback. Each yielded
/// output buffer is fresh and no longer mutated after the callback returns.
private final class AudioInputConverter: @unchecked Sendable {
    let converter: AVAudioConverter
    let target: AVAudioFormat
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let failed: @Sendable () -> Void
    init(source: AVAudioFormat, target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, failed: @escaping @Sendable () -> Void) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else { throw LocalSpeechError.message("Audioformat nicht verfügbar.") }
        self.converter = converter; self.target = target; self.continuation = continuation; self.failed = failed
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { failed(); return }
        let input = ConverterInput(buffer); var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let buffer = input.next() else { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData; return buffer
        }
        if error != nil { failed(); return }
        if output.frameLength > 0, case .dropped = continuation.yield(AnalyzerInput(buffer: output)) { failed() }
    }
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
        let level = min(1, pow(rms, 0.65))
        smoothed += (level - smoothed) * 0.4
        publish(smoothed)
    }
}
@MainActor @Observable final class LocalSpeechRecorder {
    enum State { case idle, preparing, recording, finishing }
    var state: State = .idle
    var transcript = ""
    private(set) var level = 0.0
    var failure: String?
    private var committed = ""
    private var generation = UUID()
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Error>?
    func beginTurn() async throws {
        guard state == .idle else { return }
        SpeechOutput.shared.stop(); state = .preparing; transcript = ""; committed = ""; failure = nil
        generation = UUID(); let generation = generation
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw LocalSpeechError.message("Mikrofonzugriff fehlt. Erlaube ihn in den Einstellungen.") }
            let module = try await LocalSpeechAssets.transcriber()
            guard await AssetInventory.status(forModules: [module]) == .installed else { throw LocalSpeechError.message("Sprachdateien fehlen. Bitte unter Sprechen → Einstellungen einrichten.") }
            guard self.generation == generation else { throw CancellationError() }
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP]); try audio.setActive(true)
            let engine = AVAudioEngine(); let source = engine.inputNode.outputFormat(forBus: 0)
            guard source.sampleRate > 0, source.channelCount > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: source) else { throw LocalSpeechError.message("Mikrofon ist nicht bereit.") }
            guard self.generation == generation else { throw CancellationError() }
            let stream = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(256))
            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer; self.continuation = stream.continuation; self.engine = engine
            try await analyzer.prepareToAnalyze(in: format)
            guard self.generation == generation else { await analyzer.cancelAndFinishNow(); throw CancellationError() }
            results = Task {
                for try await result in module.results {
                    guard self.generation == generation else { return }
                    let text = String(result.text.characters)
                    if result.isFinal { committed += text + " "; transcript = committed }
                    else { transcript = committed + text }
                }
            }
            try await analyzer.start(inputSequence: stream.stream)
            let converter = try AudioInputConverter(source: source, target: format, continuation: stream.continuation) { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    self.cancelTurn(); self.failure = "Audio wurde unterbrochen. Bitte noch einmal sprechen oder antippen."
                }
            }
            let meter = InputLevelMeter { [weak self] value in
                Task { @MainActor in
                    guard let self, self.generation == generation, self.state == .recording else { return }
                    self.level = value
                }
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: source) { buffer, _ in
                meter.append(buffer); converter.append(buffer)
            }
            engine.prepare(); try engine.start()
            guard self.generation == generation else { throw CancellationError() }
            state = .recording
        } catch { if self.generation == generation { cancelTurn() }; throw error }
    }
    func endTurn() async throws -> String {
        guard state == .recording, let analyzer else { return "" }
        state = .finishing; level = 0; let generation = generation
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil; continuation?.finish(); continuation = nil
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput(); try await results?.value
            guard self.generation == generation else { throw CancellationError() }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.analyzer = nil; results = nil; state = .idle
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return text
        } catch { if self.generation == generation { cancelTurn() }; throw error }
    }
    func cancelTurn() {
        generation = UUID(); engine?.stop()
        if engine != nil { engine?.inputNode.removeTap(onBus: 0) }
        engine = nil; continuation?.finish(); continuation = nil; results?.cancel(); results = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }; analyzer = nil
        state = .idle; level = 0; transcript = ""; committed = ""; failure = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
struct VoiceSettingsView: View {
    @State private var assets = LocalSpeechAssets()
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
                LabeledContent("Spracherkennung", value: assets.ready ? "Bereit" : "Einrichtung")
                Text(assets.status).foregroundStyle(.secondary)
                if assets.busy { ProgressView(value: assets.progress); Button("Abbrechen") { assets.cancel() } }
                else if !assets.ready { Button("Spracherkennung einrichten") { assets.prepareAssets() } }
            } footer: { Text("Für die Einrichtung ist eventuell einmalig Internet nötig. Aufnahme und Gespräch werden nicht gespeichert.") }
        }.pageTitle("Sprache")
            .onAppear { rate = output.rate }
            .task { await assets.check() }
            .onChange(of: rate) { output.stop(); output.rate = rate }
            .onDisappear { assets.cancel(); output.stop() }
    }
}
