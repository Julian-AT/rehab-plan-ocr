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

/// Only measured input/playback energy changes this orb. Loading has no motion.
struct VoiceOrb: View {
    let state: VoicePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let level = reduceMotion ? 0 : min(1, max(0, state.level))
        ZStack {
            Circle().fill(.white.opacity(scheme == .dark ? 0.12 : 0.65))
            Circle().fill(RadialGradient(colors: [.white, Color(red: 0.83, green: 0.91, blue: 0.99), Color(red: 0.20, green: 0.65, blue: 0.95)], center: .topLeading, startRadius: 12, endRadius: 210))
            Ellipse().fill(.white.opacity(0.72)).frame(width: 124, height: 96)
                .blur(radius: 20).offset(x: -17 + level * 10, y: -22 + level * 24)
            Ellipse().fill(Color(red: 0.05, green: 0.48, blue: 0.95).opacity(0.48))
                .frame(width: 105 + level * 35, height: 85).blur(radius: 21).offset(x: 29, y: 39 - level * 35)
            Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }.frame(width: 180, height: 180).clipShape(.circle)
            .scaleEffect(1 + level * 0.09)
            .shadow(color: .black.opacity(0.06), radius: 13, y: 8)
            .frame(width: 214, height: 214)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
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
            HStack {
                Button {
                    Task { if model.recorder.state == .recording { await model.endTurn() } else { await model.beginTurn() } }
                } label: {
                    Label(model.recorder.state == .recording ? "Fertig" : "Sprechen", systemImage: model.recorder.state == .recording ? "checkmark" : "mic")
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityIdentifier(model.recorder.state == .recording ? "finish-speaking" : "speak")
                    .accessibilityHint(model.recorder.state == .recording ? "Aufnahme beenden und auswerten" : "Aufnahme starten")
                    .disabled(model.busy || model.edits.busy || (model.recorder.state != .idle && model.recorder.state != .recording) || model.failures >= 2 || model.edits.proposal != nil)
                Spacer()
                Button("Gesprächsdetails", systemImage: "ellipsis") { details = true }
                    .labelStyle(.iconOnly).controlHeight().foregroundStyle(.secondary)
                    .accessibilityIdentifier("voice-details")
                Spacer()
                Button { model.cancelSession() } label: {
                    Label("Abbrechen", systemImage: "xmark").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityIdentifier("stop-speech")
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .toolbar {
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
    var body: some View {
        Form {
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
