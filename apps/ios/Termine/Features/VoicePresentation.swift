import AVFoundation
import RehaCore
import SwiftUI

struct VoicePresentation {
  enum Phase: String {
    case idle, listening, recording, processing, playback, paused, confirmation, error
  }
  let phase: Phase
  let title: String
  let level: Double
  @MainActor init(model: VoiceModel, output: SpeechOutput) {
    if model.recorder.state == .recording {
      phase = model.recorder.userSpeaking ? .recording : .listening
      title = model.recorder.userSpeaking ? "Du sprichst" : "Ich höre zu"
      level = model.recorder.level
    } else if output.phase == .playing {
      phase = .playback
      title = "Victoria spricht"
      level = output.level
    } else if model.recorder.state != .idle || model.busy || model.edits.busy {
      phase = .processing
      title = "Ich denke nach"
      level = 0
    } else if output.phase == .preparing {
      phase = .processing
      title = "Antwort vorbereiten"
      level = 0
    } else if model.recorder.failure != nil || model.failure != nil || output.phase == .failed
      || model.edits.error != nil
    {
      phase = .error
      title = "Bitte erneut versuchen"
      level = 0
    } else if model.edits.proposal != nil {
      phase = .confirmation
      title = "Bitte Angaben bestätigen"
      level = 0
    } else {
      phase = model.sessionState == .paused ? .paused : .idle
      title = model.sessionState == .paused ? "Pausiert" : "Bereit"
      level = 0
    }
  }
}

/// Audio changes interpolate independently of the clock, so incoming meter
/// samples never snap the surface. The silhouette always remains a circle.
@Animatable
private struct VoiceOrbSurface: View {
  var energy: Double
  @AnimatableIgnored var time: Double

  private static let mint = Color(red: 0.69, green: 0.97, blue: 0.80)
  private static let light = Color(red: 0.92, green: 1, blue: 0.95)
  private static let deep = Color(red: 0, green: 0.38, blue: 0.22)

  var body: some View {
    let drift = 0.095 + energy * 0.09
    let x = Float(sin(time * 0.55) * drift)
    let y = Float(cos(time * 0.43) * drift)
    MeshGradient(
      width: 4, height: 4,
      points: [
        [0, 0], [0.33, 0], [0.67, 0], [1, 0],
        [0, 0.33], [0.33 + x, 0.33 + y], [0.67 + y, 0.33 - x], [1, 0.33],
        [0, 0.67], [0.33 - y, 0.67 + x], [0.67 - x, 0.67 - y], [1, 0.67],
        [0, 1], [0.33, 1], [0.67, 1], [1, 1],
      ],
      colors: [
        Self.mint, Self.light, Self.mint, AppPalette.tint,
        Self.mint, Self.light, AppPalette.tint, Self.deep,
        AppPalette.tint, Self.mint, Self.mint, AppPalette.tint,
        Self.deep, AppPalette.tint, Self.deep, Self.deep,
      ]
    )
    .overlay {
      Ellipse().fill(Self.light.opacity(0.55))
        .frame(width: 180, height: 70 + energy * 30)
        .blur(radius: 22)
        .rotationEffect(.degrees(-35 + sin(time * 0.32) * 24))
        .offset(x: sin(time * 0.38) * 35, y: cos(time * 0.46) * 40)
    }
    .clipShape(.circle)
    .overlay {
      Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
    }
    .scaleEffect(1 + energy * 0.045)
    .shadow(color: AppPalette.tint.opacity(0.10 + energy * 0.05), radius: 18 + energy * 10, y: 6)
  }
}

struct VoiceOrb: View {
  let state: VoicePresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1.0 / 60,
        paused: reduceMotion || scenePhase != .active || state.phase == .paused)
    ) { context in
      let energy = reduceMotion ? 0 : min(1, pow(max(0, state.level), 0.6))
      VoiceOrbSurface(
        energy: energy,
        time: reduceMotion || state.phase == .paused
          ? 0 : context.date.timeIntervalSinceReferenceDate
      )
      .frame(width: 224, height: 224)
      .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: energy)
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
  @Environment(\.dynamicTypeSize) private var typeSize
  private var failure: String? {
    model.failure ?? model.recorder.failure ?? model.edits.error
      ?? (output.phase == .failed ? output.status : nil)
  }
  var body: some View {
    let presentation = VoicePresentation(model: model, output: output)
    VStack(spacing: 0) {
      Spacer(minLength: 12)
      VoiceOrb(state: presentation)
      Text(presentation.title).font(.subheadline).foregroundStyle(.secondary)
        .accessibilityIdentifier("voice-phase-title")
      if let failure {
        Text(failure).font(.callout).multilineTextAlignment(.center).padding(.horizontal)
      }
      Spacer(minLength: 12)
      if !model.response.isEmpty {
        SpokenResponseLine(output: output, fullText: model.response)
          .padding(.horizontal).padding(.bottom, 12)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemBackground))
    .safeAreaInset(edge: .bottom) {
      Button(
        model.mainButtonTitle,
        systemImage: model.sessionState == .paused
          ? "play" : model.sessionState == .stopped ? "mic" : "pause"
      ) {
        Task { await model.toggleSession() }
      }
      .buttonStyle(AppPrimaryButtonStyle(capsule: true)).buttonBorderShape(.capsule).controlSize(
        .extraLarge
      )
      .accessibilityIdentifier("speak")
      .accessibilityHint(
        "Einmal starten, automatisch antworten und weiter zuhören. Hineinsprechen unterbricht die Antwort."
      )
      .disabled(model.edits.busy || model.edits.proposal != nil)
      .padding(.horizontal).padding(.bottom, 24).padding(.top, 20)
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button("Abbrechen", systemImage: "xmark") { model.cancelSession() }
          .accessibilityIdentifier("stop-speech")
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Gesprächsdetails", systemImage: "text.bubble") {
          model.pauseSession()
          details = true
        }
        .accessibilityIdentifier("voice-details")
        Button("Spracheinstellungen", systemImage: "slider.horizontal.3") {
          model.cancelSession()
          settings = true
        }
        .accessibilityIdentifier("voice-settings")
      }
    }
    .navigationDestination(isPresented: $settings) { VoiceSettingsView() }
    .navigationDestination(isPresented: $details) { VoiceDetailsView(core: core, model: model) }
    .sheet(
      isPresented: Binding(
        get: { model.edits.proposal != nil },
        set: { if !$0 && model.edits.proposal != nil { model.cancelSession() } })
    ) {
      NavigationStack {
        Form {
          if let proposal = model.edits.proposal {
            ProposalCard(
              proposal: proposal, busy: model.edits.busy,
              confirm: { Task { await model.confirmProposal() } }, cancel: { model.cancelSession() }
            )
          }
          if let error = model.edits.error {
            Section { Text(error).foregroundStyle(AppPalette.destructive) }
          }
        }.pageTitle("Termin prüfen")
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Abbrechen") { model.cancelSession() }.disabled(model.edits.busy)
            }
          }
      }.interactiveDismissDisabled(model.edits.busy)
    }
    .onChange(of: model.question) { _, question in if question == .event { details = true } }
    .onChange(of: model.edits.systemEvent?.id) { _, id in if id != nil { details = true } }
    .onChange(of: model.failures) { _, failures in if failures >= 2 { details = true } }

  }
}

private struct VoiceDetailsView: View {
  let core: NativeApplication
  @Bindable var model: VoiceModel
  @State private var output = SpeechOutput.shared
  @State private var editor = false
  @State private var editingEvent: CalendarEvent?
  @State private var history = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var blocked: Bool {
    model.busy || model.edits.busy || model.edits.proposal != nil
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          if model.rounds.isEmpty {
            Text("Hier erscheint dein Gespräch.").foregroundStyle(.secondary)
          }
          ForEach(model.rounds) { round in
            VStack(alignment: .leading, spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Du").font(.caption).foregroundStyle(.secondary)
                Text(round.user)
              }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
              if !round.answer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Victoria").font(.caption).foregroundStyle(.secondary)
                  Text(round.answer)
                }.padding(.horizontal, 12)
              }
            }.textSelection(.enabled).id(round.id)
          }
          if !model.recorder.transcript.isEmpty {
            Text(model.recorder.transcript).textSelection(.enabled).accessibilityIdentifier(
              "voice-transcript")
          }
          if let failure = model.failure ?? model.recorder.failure ?? model.edits.error
            ?? (output.phase == .failed ? output.status : nil)
          {
            Text(failure).foregroundStyle(AppPalette.destructive)
          }
          if model.busy { ProcessingRow(text: "Antwort vorbereiten …") }
          if !model.response.isEmpty {
            HStack {
              Button("Wiederholen", systemImage: "arrow.counterclockwise") {
                output.speak(model.response)
              }
              .disabled(blocked).accessibilityIdentifier("repeat-speech")
              if output.speaking { Button("Stopp", systemImage: "stop") { output.stop() } }
            }.frame(minHeight: 44)
          }
          if model.question == .event {
            ForEach(model.candidates) { event in
              Button {
                Task { await model.choose(event) }
              } label: {
                CalendarAgendaRow(event: event, now: .now)
              }
              .buttonStyle(.plain).disabled(blocked)
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            if model.question == .title {
              TextField("Bezeichnung", text: $model.title)
              Button("Bezeichnung übernehmen") { Task { await model.editSlots() } }
            }
            if model.question == .date {
              DatePicker("Datum", selection: $model.date, displayedComponents: .date)
              Button("Datum übernehmen") { Task { await model.editSlots() } }
            }
            if model.question == .time {
              DatePicker("Uhrzeit", selection: $model.time, displayedComponents: .hourAndMinute)
              Button("Uhrzeit übernehmen") { Task { await model.editSlots() } }
            }
            if model.question == .duration {
              TextField("Dauer in Minuten", value: $model.duration, format: .number).keyboardType(
                .numberPad)
              Button("Dauer übernehmen") { Task { await model.editSlots() } }
            }
            if model.question != .event {
              ForEach(model.candidates) { event in
                Button {
                  Task { await model.choose(event) }
                } label: {
                  CalendarAgendaRow(event: event, now: .now)
                }
              }
            }
          }.disabled(model.busy || model.edits.busy)
          Color.clear.frame(height: 1).id("conversation-bottom")
        }.padding()
      }.accessibilityIdentifier("conversation-transcript")
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: model.rounds.count) { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
        .onChange(of: model.busy) { _, busy in
          if !busy {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
              proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
          }
        }
    }
    .safeAreaInset(edge: .bottom) {
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Nachricht schreiben", text: $model.messageDraft, axis: .vertical)
          .lineLimit(1...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("voice-message")
        Button {
          send()
        } label: {
          Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(AppPalette.tint, in: .circle)
        }.buttonStyle(.plain).accessibilityLabel("Senden").accessibilityIdentifier("voice-send")
          .disabled(
            blocked || model.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.padding(12).background(Color(uiColor: .systemBackground))
    }
    .pageTitle("Gesprächsdetails")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Fortsetzen", systemImage: "mic") {
          dismiss()
          Task { await model.beginTurn() }
        }.disabled(blocked).accessibilityIdentifier("resume-conversation")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Nächster Termin") { Task { await model.submitAction(.next) } }
            .accessibilityIdentifier("voice-next")
          Button("Heute") { Task { await model.submitAction(.list) } }.accessibilityIdentifier(
            "voice-today")
          Button("Termin hinzufügen") { Task { await model.submitAction(.create) } }
            .accessibilityIdentifier("voice-create")
          Button("Termin ändern") { Task { await model.submitAction(.update) } }
          Button("Kalendereintrag löschen") { Task { await model.submitAction(.remove) } }
          Divider()
          Button("Angaben direkt bearbeiten") {
            editingEvent = model.selected
            model.cancelSession()
            editor = true
          }
          if let event = model.edits.systemEvent {
            Button("Im Systemkalender öffnen") { Task { await model.edits.openSystem(event) } }
          }
          Button("Verlauf und Rückgängig") { history = true }
          Divider()
          Button("Gespräch abbrechen", role: .cancel) { model.cancelSession() }
        } label: {
          Image(systemName: "ellipsis.circle").foregroundStyle(AppPalette.tint)
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Kalenderaktionen").accessibilityIdentifier("voice-actions").disabled(
          blocked)
      }
    }
    .sheet(isPresented: $editor) { EventEditorView(core: core, original: editingEvent) {} }
    .navigationDestination(isPresented: $history) { EventHistoryView(core: core) }
  }
  private func send() {
    guard !blocked else { return }
    let text = model.messageDraft
    Task {
      let success = await model.submitText(text)
      if success && model.messageDraft == text { model.messageDraft = "" }
    }
  }
}

/// Word appearance is driven exclusively by rendered player sample position.
private struct SpokenResponseLine: View {
  let output: SpeechOutput
  let fullText: String
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize || reduceMotion {
        Text(output.words.suffix(18).map(\.text).joined(separator: " "))
          .font(.body).fixedSize(horizontal: false, vertical: true)
      } else {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            HStack(spacing: 6) {
              ForEach(output.words) { word in
                Text(word.text).font(.body).transition(.opacity).id(word.id)
              }
            }.padding(.leading, 24).padding(.trailing, 8)
          }.scrollIndicators(.hidden).scrollDisabled(true)
            .mask {
              LinearGradient(
                stops: [
                  .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                  .init(color: .black, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
            .onChange(of: output.words.last?.id) { _, id in
              if let id {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .trailing) }
              }
            }
        }.frame(height: 44)
      }
    }
    .opacity(output.lineVisible ? 1 : 0)
    .animation(.easeOut(duration: 0.15), value: output.words.last?.id)
    .animation(.easeOut(duration: 0.3), value: output.lineVisible)
    .accessibilityElement(children: .ignore).accessibilityLabel(fullText)
    .accessibilityIdentifier("voice-response")
  }
}
