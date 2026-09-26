import SwiftUI
import RehaCore
import AVFoundation

struct VoicePresentation {
    enum Phase: String { case idle, recording, processing, playback, confirmation, error }
    let phase: Phase
    let title: String
    let level: Double
    @MainActor init(model: VoiceModel, output: SpeechOutput) {
        if model.recorder.state == .recording {
            phase = .recording; title = "Ich höre zu"; level = model.recorder.level
        } else if model.recorder.state != .idle || model.busy || model.edits.busy {
            phase = .processing; title = "Wird vorbereitet …"; level = 0
        } else if output.phase == .playing {
            phase = .playback; title = "Antwort wird vorgelesen"; level = output.level
        } else if output.phase == .preparing {
            phase = .processing; title = "Stimme wird vorbereitet …"; level = 0
        } else if model.recorder.failure != nil || model.failure != nil || output.phase == .failed || model.edits.error != nil {
            phase = .error; title = "Bitte erneut versuchen"; level = 0
        } else if model.edits.proposal != nil {
            phase = .confirmation; title = "Bitte Angaben bestätigen"; level = 0
        } else {
            phase = .idle; title = "Bereit zum Sprechen"; level = 0
        }
    }
}

/// Slow organic motion gives the orb a living surface; measured microphone or
/// playback energy controls the stronger response. Reduce Motion freezes both.
private struct FluidOrbShape: Shape {
    let time: Double
    let energy: Double
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.43
        var path = Path()
        for index in 0...128 {
            let angle = Double(index) / 128 * .pi * 2
            let wave = sin(angle * 3 + time * 1.2) * 0.045 + sin(angle * 5 - time * 0.8) * 0.025
            let r = radius * (1 + wave * (0.5 + energy * 2.5))
            let point = CGPoint(x: rect.midX + cos(angle) * r, y: rect.midY + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath(); return path
    }
}
struct VoiceOrb: View {
    let state: VoicePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let energy = reduceMotion ? 0 : min(1, pow(max(0, state.level), 0.6))
            let shape = FluidOrbShape(time: t, energy: energy)
            ZStack {
                RadialGradient(colors: [Color(red: 0.8, green: 1, blue: 0.85), AppPalette.tint, Color(red: 0, green: 0.28, blue: 0.13)], center: .topLeading, startRadius: 5, endRadius: 255)
                Ellipse().fill(.white.opacity(0.7))
                    .frame(width: 130, height: 100).blur(radius: 24)
                    .offset(x: -28 + sin(t * 0.7) * 22, y: -40 + cos(t * 0.9) * 18)
                Ellipse().fill(Color(red: 0.25, green: 0.95, blue: 0.48).opacity(0.85))
                    .frame(width: 135 + energy * 60, height: 105).blur(radius: 22)
                    .rotationEffect(.radians(t * 0.35))
                    .offset(x: 35 * cos(t * 0.6), y: 35 + sin(t * 0.8) * 22)
            }.clipShape(shape)
                .overlay { shape.stroke(.white.opacity(0.28), lineWidth: 1) }
                .scaleEffect(reduceMotion ? 1 : 1 + sin(t * 1.1) * 0.018 + energy * 0.1)
                .shadow(color: AppPalette.tint.opacity(0.12), radius: 20, y: 8)
        }.frame(width: 248, height: 248)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.title).accessibilityValue(state.phase.rawValue)
            .accessibilityIdentifier("voice-state")
    }
}

struct VoiceView: View {
    let core: NativeApplication
    @Bindable var model: VoiceModel
    @State private var output = SpeechOutput.shared
    @State private var settings = false
    @State private var details = false
    @State private var alert: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var failure: String? {
        model.failure ?? model.recorder.failure ?? model.edits.error ?? (output.phase == .failed ? output.status : nil)
    }
    var body: some View {
        let presentation = VoicePresentation(model: model, output: output)
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VoiceOrb(state: presentation)
            Spacer(minLength: 12)
            if !model.response.isEmpty && model.edits.proposal == nil {
                Text(model.response).font(.body).multilineTextAlignment(.center)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 3).padding(.horizontal)
                    .accessibilityIdentifier("voice-response")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task { if model.recorder.state == .recording { await model.endTurn() } else { await model.beginTurn() } }
                } label: {
                    HStack(spacing: 12) {
                        Text(model.recorder.state == .recording ? "✓" : "🎙️").font(.largeTitle)
                        Text(model.recorder.state == .recording ? "Fertig" : "Sprechen").font(.title3.weight(.semibold))
                    }.frame(minWidth: 190, minHeight: 48)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .accessibilityLabel(model.recorder.state == .recording ? "Fertig" : "Sprechen")
                    .accessibilityIdentifier(model.recorder.state == .recording ? "finish-speaking" : "speak")
                    .accessibilityHint(model.recorder.state == .recording ? "Aufnahme beenden und auswerten" : "Aufnahme starten")
                    .disabled(model.busy || model.edits.busy || (model.recorder.state != .idle && model.recorder.state != .recording) || model.edits.proposal != nil)
                Button("Gesprächsdetails", systemImage: "ellipsis.bubble") { details = true }
                    .font(.subheadline).controlHeight().foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice-details")
            }.padding(.horizontal).padding(.bottom, 12).padding(.top, 16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Abbrechen", systemImage: "xmark") { model.cancelSession() }
                    .accessibilityIdentifier("stop-speech")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Spracheinstellungen", systemImage: "slider.horizontal.3") { model.cancelSession(); settings = true }
                    .accessibilityIdentifier("voice-settings")
            }
        }
        .navigationDestination(isPresented: $settings) { VoiceSettingsView() }
        .navigationDestination(isPresented: $details) { VoiceDetailsView(core: core, model: model) }
        .sheet(isPresented: Binding(get: { model.edits.proposal != nil }, set: { if !$0 && model.edits.proposal != nil { model.cancelSession() } })) {
            NavigationStack {
                Form {
                    if let proposal = model.edits.proposal {
                        ProposalCard(proposal: proposal, busy: model.edits.busy,
                                     confirm: { Task { await model.confirmProposal() } }, cancel: { model.cancelSession() })
                    }
                    if let error = model.edits.error { Section { Text(error).foregroundStyle(.red) } }
                }.pageTitle("Termin prüfen")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { model.cancelSession() }.disabled(model.edits.busy) } }
            }.interactiveDismissDisabled(model.edits.busy)
        }
        .onChange(of: failure) { _, message in if let message { alert = message } }
        .onChange(of: model.question) { _, question in if question == .event { details = true } }
        .onChange(of: model.edits.systemEvent?.id) { _, id in if id != nil { details = true } }
        .onChange(of: model.failures) { _, failures in if failures >= 2 { details = true } }
        .alert("Sprechen", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) { alert = nil }
        } message: { Text(alert ?? "") }
    }
}

private struct VoiceDetailsView: View {
    let core: NativeApplication
    @Bindable var model: VoiceModel
    @State private var output = SpeechOutput.shared
    @State private var editor = false
    @State private var editingEvent: CalendarEvent?
    @State private var message = ""
    var body: some View {
        Form {
            Section("Nachricht") {
                TextField("Dein Anliegen", text: $message, axis: .vertical).lineLimit(1...4).accessibilityIdentifier("voice-message")
                Button("Senden", systemImage: "arrow.up") {
                    let text = message; message = ""
                    Task { await model.submitText(text) }
                }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.edits.busy || model.edits.proposal != nil)
                    .accessibilityIdentifier("voice-send")
            }
            if !model.recorder.transcript.isEmpty {
                Section("Deine Worte") { Text(model.recorder.transcript).textSelection(.enabled).accessibilityIdentifier("voice-transcript") }
            }
            if !model.response.isEmpty {
                Section("Antwort") {
                    Text(model.response).textSelection(.enabled)
                    Button("Wiederholen", systemImage: "arrow.counterclockwise") { output.speak(model.response) }
                        .disabled(model.recorder.state != .idle || model.busy || model.edits.busy)
                        .accessibilityIdentifier("repeat-speech")
                    if output.speaking { Button("Wiedergabe beenden", systemImage: "stop") { output.stop() } }
                }
            }
            if model.question == .event {
                Section("Passende Termine") {
                    ForEach(model.candidates) { event in
                        Button { Task { await model.choose(event) } } label: { CalendarAgendaRow(event: event, now: .now) }
                    }
                }.disabled(model.busy || model.edits.busy)
            }
            Section("Manuell auswählen") {
                Button("Nächster Termin") { Task { await model.submitAction(.next) } }.accessibilityIdentifier("voice-next")
                Button("Heute") { Task { await model.submitAction(.list) } }.accessibilityIdentifier("voice-today")
                Button("Termin hinzufügen") { Task { await model.submitAction(.create) } }.accessibilityIdentifier("voice-create")
                Button("Termin ändern") { Task { await model.submitAction(.update) } }
                Button("Kalendereintrag löschen") { Task { await model.submitAction(.remove) } }
            }.disabled(model.busy || model.edits.busy)
            Section {
                if model.question == .title { TextField("Bezeichnung", text: $model.title); Button("Bezeichnung übernehmen") { Task { await model.editSlots() } } }
                if model.question == .date { DatePicker("Datum", selection: $model.date, displayedComponents: .date); Button("Datum übernehmen") { Task { await model.editSlots() } } }
                if model.question == .time { DatePicker("Uhrzeit", selection: $model.time, displayedComponents: .hourAndMinute); Button("Uhrzeit übernehmen") { Task { await model.editSlots() } } }
                if model.question == .duration { TextField("Dauer in Minuten", value: $model.duration, format: .number).keyboardType(.numberPad); Button("Dauer übernehmen") { Task { await model.editSlots() } } }
                if model.question != .event {
                    ForEach(model.candidates) { event in
                        Button { Task { await model.choose(event) } } label: { CalendarAgendaRow(event: event, now: .now) }
                    }
                }
                Button("Angaben direkt bearbeiten") { editingEvent = model.selected; model.cancelSession(); editor = true }
                if let event = model.edits.systemEvent { Button("Im Systemkalender öffnen") { Task { await model.edits.openSystem(event) } } }
                NavigationLink("Verlauf und Rückgängig") { EventHistoryView(core: core) }
            }.disabled(model.busy || model.edits.busy)
            Section { Button("Gespräch abbrechen", role: .cancel) { model.cancelSession() } }
        }.pageTitle("Gesprächsdetails")
            .sheet(isPresented: $editor) { EventEditorView(core: core, original: editingEvent) {} }
    }
}
