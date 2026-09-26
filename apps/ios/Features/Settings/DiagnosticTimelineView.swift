import AppleServices
import SwiftUI

struct DiagnosticTimelineView: View {
  @State private var events: [DiagnosticEvent] = []
  @State private var error: String?
  @State private var export = TemporaryDiagnosticExport()
  @State private var busy = false
  @State private var limit = 100
  var body: some View {
    List {
      Section {
        AppFormAction(
          title: "Diagnoseexport vorbereiten", systemImage: "square.and.arrow.up"
        ) {
          guard !busy else { return }
          busy = true
          Task {
            defer { busy = false }
            do {
              try await export.write { try await LocalDiagnostics.shared.redactedExport() }
              error = nil
            } catch is CancellationError {
            } catch { self.error = userMessage(error) }
          }
        }.disabled(busy)
        if let url = export.url { ShareLink("Export teilen", item: url) }
        if let error { Text(error).foregroundStyle(AppPalette.destructive) }
      } header: {
        AppSectionHeader(
          title: "Technisches Protokoll",
          help: "Der Export enthält keine Termine, Gespräche oder Audiodaten.")
      }
      ForEach(events.prefix(limit)) { event in
        VStack(alignment: .leading, spacing: 6) {
          Text(event.step.title).font(.headline)
          Text(event.code).font(.caption.monospaced())
          Text(event.time.formatted(date: .abbreviated, time: .standard))
          Text("Vorgang \(event.correlation.prefix(8))").font(.caption)
          if let duration = event.durationMs { Text("\(duration) ms") }
          if let count = event.count { Text("Anzahl: \(count)") }
        }.foregroundStyle(.secondary)
      }
      if events.count > limit { Button("Weitere Einträge anzeigen") { limit += 100 } }
    }.pageTitle("Technischer Verlauf")
      .task { await load() }
      .refreshable { await load() }
      .onDisappear { Task { await export.close() } }
  }
  private func load() async {
    do {
      events = try await LocalDiagnostics.shared.snapshot()
      error = nil
    } catch { self.error = userMessage(error) }
  }
}
extension DiagnosticStep {
  fileprivate var title: String {
    switch self {
    case .recognitionReadiness: "Spracherkennung vorbereiten"
    case .recognitionLocale: "Erkennungssprache"
    case .recognitionProgress: "Erkennungsfortschritt"
    case .recognitionPartial: "Vorläufiges Sprachergebnis"
    case .recognitionFinal: "Bestätigtes Sprachergebnis"
    case .recognitionFinalization: "Spracherkennung abschließen"
    case .speechEndpoint: "Sprechpause"
    case .audioPCMFormat: "Audioformat"
    case .voiceProcessing: "Echounterdrückung"
    case .microphonePermission: "Mikrofonfreigabe"
    case .speechPermission: "Spracherkennungsfreigabe"
    case .inputRoute: "Audioeingang"
    case .audioEngine: "Audioengine"
    case .audioConfiguration: "Audiokonfiguration"
    case .audioBuffer: "Mikrofonpuffer"
    case .audioSampleRate: "Abtastrate"
    case .audioChannels: "Audiokanäle"
    case .audioLevel: "Mikrofonpegel"
    case .audioConversion: "Audioverarbeitung"
    case .audioRestart: "Mikrofon neu vorbereiten"
    case .intake: "Eingang"
    case .preparation: "Bildaufbereitung"
    case .ocr: "Texterkennung"
    case .mapping: "Zeilen und Spalten"
    case .interpretation: "Termininterpretation"
    case .refinement: "Nachprüfung"
    case .confirmation: "Formularbestätigung"
    case .calendarRead: "Kalender lesen"
    case .calendarWrite: "Kalender schreiben"
    case .reminderSettings: "Erinnerungseinstellungen"
    case .reminderSelection: "Erinnerungsauswahl"
    case .reminderPlan: "Mitteilungen planen"
    case .reminderConfirmed: "Ausstehende Mitteilungen prüfen"
    case .speechSession: "Sprachsitzung"
    case .speechRecognition: "Spracherkennung"
    case .tools: "Kalenderwerkzeuge"
    case .synthesis: "Sprachsynthese"
    case .playback: "Wiedergabe"
    case .interruption: "Unterbrechung"
    }
  }
}
