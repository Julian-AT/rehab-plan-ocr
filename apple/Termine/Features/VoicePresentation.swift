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
            Circle().fill(RadialGradient(colors: [.white, Color(red: 0.83, green: 0.91, blue: 0.99), Color(red: 0.66, green: 0.77, blue: 0.90)], center: .topLeading, startRadius: 12, endRadius: 210))
            Ellipse().fill(.white.opacity(0.72)).frame(width: 124, height: 96)
                .blur(radius: 20).offset(x: -17 + level * 10, y: -22 + level * 24)
            Ellipse().fill(Color(red: 0.62, green: 0.77, blue: 0.96).opacity(0.48))
                .frame(width: 105 + level * 35, height: 85).blur(radius: 21).offset(x: 29, y: 39 - level * 35)
            Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }.frame(width: 180, height: 180).clipShape(.circle)
            .scaleEffect(1 + level * 0.09)
            .shadow(color: .black.opacity(0.06), radius: 13, y: 8)
            .frame(width: 214, height: 214)
            .accessibilityHidden(true)
    }
}

struct VoiceView: View {
    let core: NativeApplication
    @Bindable var model: VoiceModel
    @State private var output = SpeechOutput.shared
    @State private var settings = false
    @State private var editor = false
    @State private var history = false
    @State private var editingEvent: CalendarEvent?
    var body: some View {
        let presentation = VoicePresentation(model: model, output: output)
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                VoiceOrb(state: presentation)
                Text(presentation.title).font(.headline)
                    .accessibilityIdentifier("voice-state").accessibilityValue(presentation.phase.rawValue)
                if !model.recorder.transcript.isEmpty {
                    Text(model.recorder.transcript).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("voice-transcript")
                }
                Text(model.response).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("voice-response")
                if let failure = model.failure ?? model.recorder.failure {
                    Text(failure).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                }
                if output.phase == .failed { Text(output.status).foregroundStyle(.red) }
                if model.edits.proposal == nil {
                    if model.recorder.state == .recording {
                        Button { Task { await model.endTurn() } } label: {
                            Label("Fertig", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryActionStyle()).accessibilityIdentifier("finish-speaking")
                        Text("Lass dir Zeit. Tippe auf Fertig, wenn du fertig gesprochen hast.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Button { Task { await model.beginTurn() } } label: {
                            Label("Sprechen", systemImage: "mic").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryActionStyle()).accessibilityIdentifier("speak")
                            .disabled(model.busy || model.edits.busy || model.recorder.state != .idle || model.failures >= 2)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.section) { playbackControls }
                    VStack(spacing: AppSpacing.small) { playbackControls }
                }
                if let proposal = model.edits.proposal {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        ProposalCard(proposal: proposal, busy: model.edits.busy,
                            confirm: { Task { await model.confirmProposal() } }, cancel: { model.cancelSession() })
                    }
                } else {
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.medium) { quickActions }
                        VStack(alignment: .leading, spacing: AppSpacing.small) { quickActions }
                    }.frame(maxWidth: .infinity).disabled(model.busy || model.edits.busy)
                    contextualControls
                }
                if let error = model.edits.error { Text(error).foregroundStyle(.red) }
                if let event = model.edits.systemEvent { Button("Im Systemkalender öffnen") { Task { await model.edits.openSystem(event) } }.controlHeight() }
            }.padding(.horizontal, AppSpacing.section).padding(.vertical, AppSpacing.section)
        }
        .background(Color(uiColor: .systemBackground)).buttonStyle(.borderless)
        .pageTitle("Sprechen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.cancelSession(); settings = true } label: {
                    Label("Spracheinstellungen", systemImage: "gearshape").frame(minWidth: 44, minHeight: 44)
                }.accessibilityIdentifier("voice-settings")
            }
        }
        .onDisappear { model.cancelSession() }
        .sheet(isPresented: $settings) { NavigationStack { VoiceSettingsView() } }
        .sheet(isPresented: $editor) { EventEditorView(core: core, original: editingEvent) {} }
        .sheet(isPresented: $history) { NavigationStack { EventHistoryView(core: core) } }
    }
    @ViewBuilder private var playbackControls: some View {
        Button { model.cancelSession(preserveResponse: true) } label: { Label("Stopp", systemImage: "stop").controlHeight() }
            .disabled(!output.speaking && model.recorder.state == .idle && !model.busy && model.edits.proposal == nil)
            .accessibilityIdentifier("stop-speech")
        Button { output.speak(model.response) } label: { Label("Wiederholen", systemImage: "arrow.counterclockwise").controlHeight() }
            .disabled(model.recorder.state != .idle || model.busy || model.edits.busy)
            .accessibilityIdentifier("repeat-speech")
    }
    @ViewBuilder private var quickActions: some View {
        Button("Nächster Termin") { Task { await model.submitAction(.next) } }.controlHeight().accessibilityIdentifier("voice-next")
        Button("Heute") { Task { await model.submitAction(.list) } }.controlHeight().accessibilityIdentifier("voice-today")
        Button("Termin hinzufügen") { Task { await model.submitAction(.create) } }.controlHeight().accessibilityIdentifier("voice-create")
    }
    @ViewBuilder private var contextualControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            if model.question == .title { TextField("Bezeichnung", text: $model.title).textFieldStyle(.roundedBorder); Button("Bezeichnung übernehmen") { Task { await model.editSlots() } }.controlHeight() }
            if model.question == .date { DatePicker("Datum", selection: $model.date, displayedComponents: .date); Button("Datum übernehmen") { Task { await model.editSlots() } }.controlHeight() }
            if model.question == .time { DatePicker("Uhrzeit", selection: $model.time, displayedComponents: .hourAndMinute); Button("Uhrzeit übernehmen") { Task { await model.editSlots() } }.controlHeight() }
            if model.question == .duration { TextField("Dauer in Minuten", value: $model.duration, format: .number).keyboardType(.numberPad).textFieldStyle(.roundedBorder); Button("Dauer übernehmen") { Task { await model.editSlots() } }.controlHeight() }
            ForEach(model.candidates) { event in
                Button { Task { await model.choose(event) } } label: { CalendarAgendaRow(event: event, now: .now) }.buttonStyle(.plain).controlHeight()
                Divider()
            }
            if !model.candidates.isEmpty || model.failures > 0 {
                Button("Termin ändern", systemImage: "pencil") { Task { await model.submitAction(.update) } }.controlHeight()
                Button("Kalendereintrag löschen", systemImage: "trash") { Task { await model.submitAction(.remove) } }.controlHeight()
            }
            if model.question != .action || model.failures > 0 {
                Button("Angaben direkt bearbeiten") { editingEvent = model.selected; model.cancelSession(); editor = true }.controlHeight()
            }
            if model.edits.result != nil {
                Button("Verlauf und Rückgängig", systemImage: "clock.arrow.circlepath") { model.cancelSession(); history = true }.controlHeight()
            }
        }.disabled(model.busy || model.edits.busy)
    }
}
