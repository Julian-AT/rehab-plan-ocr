import AVFoundation
import RehaCore
import SwiftUI

struct VoicePresentation {
  enum Phase: String { case idle, recording, processing, playback, confirmation, error }
  let phase: Phase
  let title: String
  let level: Double
  @MainActor init(model: VoiceModel, output: SpeechOutput) {
    if model.recorder.state == .recording {
      phase = .recording
      title = "Spracherkennung läuft"
      level = model.recorder.level
    } else if output.phase == .playing {
      phase = .playback
      title = "Antwort wird vorgelesen"
      level = output.level
    } else if model.recorder.state != .idle || model.busy || model.edits.busy {
      phase = .processing
      title = "Wird vorbereitet …"
      level = 0
    } else if output.phase == .preparing {
      phase = .processing
      title = "Stimme wird vorbereitet …"
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
      phase = .idle
      title = model.sessionState == .paused ? "Gespräch pausiert" : "Bereit zum Sprechen"
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
    let drift = 0.055 + energy * 0.07
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
    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 12)
    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 3)
  }
}

struct VoiceOrb: View {
  let state: VoicePresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    TimelineView(
      .animation(minimumInterval: 1.0 / 60, paused: reduceMotion || scenePhase != .active)
    ) { context in
      let energy = reduceMotion ? 0 : min(1, pow(max(0, state.level), 0.6))
      VoiceOrbSurface(
        energy: energy, time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
      )
      .frame(width: 224, height: 224)
      .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: energy)
    }.frame(width: 248, height: 248)
      .accessibilityHidden(true)
  }
}

struct VoiceView: View {
  let core: NativeApplication
  @Bindable var model: VoiceModel
  @State private var output = SpeechOutput.shared
  @State private var settings = false
  @State private var details = false
  @State private var alert: String?
  @State private var controlsHeight: CGFloat = 108
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  private var responseVisible: Bool {
    !model.response.isEmpty && (output.lineVisible || voiceOver)
  }
  private var failure: String? {
    model.failure ?? model.recorder.failure ?? model.edits.error
      ?? (output.phase == .failed ? output.status : nil)
  }
  var body: some View {
    let presentation = VoicePresentation(model: model, output: output)
    ZStack {
      GeometryReader { geometry in
        ZStack {
          VoiceOrb(state: presentation)
            .opacity(responseVisible ? 0 : 1)
          if !model.response.isEmpty {
            SpokenResponseLine(output: output, fullText: model.response)
              .padding(.horizontal, 28)
          }
        }
        .padding(
          .vertical,
          controlsHeight + max(geometry.safeAreaInsets.top, geometry.safeAreaInsets.bottom)
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .ignoresSafeArea(.container, edges: .vertical)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemBackground))
    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: responseVisible)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(presentation.title).accessibilityValue(presentation.phase.rawValue)
    .accessibilityIdentifier("voice-state")
    .overlay(alignment: .bottom) {
      Group {
        if model.isSessionRunning || model.busy || output.speaking || !model.response.isEmpty {
          HStack(spacing: 16) {
            MicrophoneWaveform(recorder: model.recorder)
            Button {
              model.cancelSession()
            } label: {
              Image(systemName: "stop.fill").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .background(AppPalette.tint, in: .circle).contentShape(.circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Gespräch stoppen")
            .accessibilityIdentifier("stop-speech")
            .disabled(model.edits.busy)
          }
          .padding(10).padding(.leading, 8)
          .background(AppPalette.tint.opacity(0.07), in: .capsule)
          .frame(maxWidth: 320)
        } else {
          Button("Gespräch starten") { Task { await model.beginTurn() } }
            .buttonStyle(AppPrimaryButtonStyle(capsule: true, foreground: .white))
            .accessibilityIdentifier("speak")
            .accessibilityHint("Startet das Mikrofon und hört nach jeder Antwort weiter zu.")
            .disabled(model.edits.busy || model.edits.proposal != nil)
        }
      }
      .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 20)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        controlsHeight = $0
      }
    }
    .toolbar {
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
    .onChange(of: failure) { _, message in if let message { alert = message } }
    .onChange(of: model.question) { _, question in if question == .event { details = true } }
    .onChange(of: model.edits.systemEvent?.id) { _, id in if id != nil { details = true } }
    .onChange(of: model.failures) { _, failures in if failures >= 2 { details = true } }
    .alert("Sprechen", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }))
    {
      Button("OK", role: .cancel) { alert = nil }
    } message: {
      Text(alert ?? "")
    }
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
        HStack(alignment: .center, spacing: 8) {
          TextField("Anliegen", text: $message, axis: .vertical).lineLimit(1...4)
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice-message")
          Button {
            let text = message
            message = ""
            Task { await model.submitText(text) }
          } label: {
            Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(AppPalette.tint)
              .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
          }
          .accessibilityLabel("Senden").buttonStyle(.plain)
          .disabled(
            message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy
              || model.edits.busy || model.edits.proposal != nil
          )
          .accessibilityIdentifier("voice-send")
        }.listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
      }
      if !model.recorder.transcript.isEmpty {
        Section("Erkannter Text") {
          Text(model.recorder.transcript).textSelection(.enabled).accessibilityIdentifier(
            "voice-transcript")
        }
      }
      if !model.response.isEmpty {
        Section("Antwort") {
          Text(model.response).textSelection(.enabled).accessibilityIdentifier(
            "voice-response-details")
          AppFormAction(title: "Wiederholen", systemImage: "arrow.counterclockwise") {
            model.repeatResponse()
          }
          .disabled(model.recorder.state != .idle || model.busy || model.edits.busy)
          .accessibilityIdentifier("repeat-speech")
          if output.speaking {
            AppFormAction(title: "Wiedergabe beenden", systemImage: "stop") { output.stop() }
          }
        }
      }
      if model.question == .event {
        Section("Passende Termine") {
          ForEach(model.candidates) { event in
            Button {
              Task { await model.choose(event) }
            } label: {
              CalendarAgendaRow(event: event, now: .now)
            }
          }
        }.disabled(model.busy || model.edits.busy)
      }
      Section("Manuell auswählen") {
        AppFormAction(title: "Nächster Termin") { Task { await model.submitAction(.next) } }
          .accessibilityIdentifier("voice-next")
        AppFormAction(title: "Heute") { Task { await model.submitAction(.list) } }
          .accessibilityIdentifier(
            "voice-today")
        AppFormAction(title: "Termin hinzufügen") { Task { await model.submitAction(.create) } }
          .accessibilityIdentifier("voice-create")
        AppFormAction(title: "Termin ändern") { Task { await model.submitAction(.update) } }
        AppFormAction(title: "Kalendereintrag löschen") {
          Task { await model.submitAction(.remove) }
        }
      }.disabled(model.busy || model.edits.busy)
      Section {
        if model.question == .title {
          TextField("Bezeichnung", text: $model.title)
          AppFormAction(title: "Bezeichnung übernehmen") { Task { await model.editSlots() } }
        }
        if model.question == .date {
          DatePicker("Datum", selection: $model.date, displayedComponents: .date)
            .environment(\.calendar, model.intent.calendar)
            .environment(\.timeZone, model.intent.calendar.timeZone)
          AppFormAction(title: "Datum übernehmen") { Task { await model.editSlots() } }
        }
        if model.question == .time {
          DatePicker("Uhrzeit", selection: $model.time, displayedComponents: .hourAndMinute)
            .environment(\.calendar, model.intent.calendar)
            .environment(\.timeZone, model.intent.calendar.timeZone)
          AppFormAction(title: "Uhrzeit übernehmen") { Task { await model.editSlots() } }
        }
        if model.question == .duration {
          TextField("Dauer in Minuten", value: $model.duration, format: .number).keyboardType(
            .numberPad)
          AppFormAction(title: "Dauer übernehmen") { Task { await model.editSlots() } }
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
        AppFormAction(title: "Angaben direkt bearbeiten") {
          editingEvent = model.selected
          model.cancelSession()
          editor = true
        }
        if let event = model.edits.systemEvent {
          AppFormAction(title: "Im Systemkalender öffnen") {
            Task { await model.edits.openSystem(event) }
          }
        }
        NavigationLink("Verlauf und Rückgängig") { EventHistoryView(core: core) }
      }.disabled(model.busy || model.edits.busy)
      if !model.rounds.isEmpty {
        Section {
          DisclosureGroup("Gesprächsverlauf") {
            ForEach(model.rounds) { round in
              VStack(alignment: .leading, spacing: 8) {
                Text(round.user).fontWeight(.medium)
                if !round.answer.isEmpty { Text(round.answer) }
              }.textSelection(.enabled)
            }
          }
        }
      }
      Section { Button("Gespräch abbrechen", role: .cancel) { model.cancelSession() } }
    }.pageTitle("Gesprächsdetails")
      .sheet(isPresented: $editor) { EventEditorView(core: core, original: editingEvent) {} }
  }
}

/// A short, centered window of words follows the actual player position.
private struct SpokenResponseLine: View {
  let output: SpeechOutput
  let fullText: String
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        Text(
          voiceOver
            ? fullText
            : output.words.suffix(typeSize.isAccessibilitySize ? 6 : 12).map(\.text).joined(
              separator: " ")
        )
        .font(.title2.weight(.medium)).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
        .accessibilityLabel(fullText).accessibilityIdentifier("voice-response")
        #if DEBUG && targetEnvironment(simulator)
          .accessibilityValue(
            ProcessInfo.processInfo.arguments.contains("--audio-evidence")
              ? String(output.words.last?.id ?? -1) : "")
        #endif
        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
      }.scrollIndicators(.hidden)
    }
    .opacity(output.lineVisible || voiceOver ? 1 : 0)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: output.words.last?.id)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: output.lineVisible)
  }
}

/// Only microphone levels enter this short, in-memory history. Silence adds
/// flat marks; playback volume and decorative oscillators never drive it.
private struct MicrophoneWaveform: View {
  let recorder: any VoiceRecording
  @State private var levels = Array(repeating: 0.0, count: 40)
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Canvas { context, size in
      let step = size.width / CGFloat(levels.count)
      let width = max(1, step * 0.52)
      for (index, sample) in levels.enumerated() {
        let level = reduceMotion ? (levels.last ?? 0) : sample
        let height = 3 + (size.height - 6) * min(1, max(0, level))
        let rect = CGRect(
          x: CGFloat(index) * step + (step - width) / 2,
          y: (size.height - height) / 2, width: width, height: height)
        context.fill(
          Path(roundedRect: rect, cornerRadius: width / 2), with: .color(AppPalette.tint))
      }
    }
    .frame(height: 44)
    .accessibilityElement(children: .ignore).accessibilityLabel("Mikrofonpegel")
    .accessibilityValue(recorder.level > 0.02 ? "Ton erkannt" : "Still")
    .accessibilityIdentifier("microphone-waveform")
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        levels.removeFirst()
        levels.append(recorder.level.isFinite ? min(1, max(0, recorder.level)) : 0)
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
      }
    }
  }
}
