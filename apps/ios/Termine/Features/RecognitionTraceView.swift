import PhotosUI
import RehaCore
import SwiftUI
import UniformTypeIdentifiers

struct RecognitionTraceView: View {
  let core: NativeApplication
  @Environment(ScanModel.self) private var scanner
  @State private var model = RecognitionTraceModel()
  @State private var photo: PhotosPickerItem?
  @State private var files = false
  @State private var selection: RecognitionTrace.Step?
  @State private var loadingPhoto = false
  @State private var inputError: String?
  @State private var timezone = TimeZone.current.identifier
  var body: some View {
    List {
      Section {
        PhotosPicker(selection: $photo, matching: .images) {
          AppActionLabel(title: "Bild aus Fotos auswählen", systemImage: "photo")
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityIdentifier("trace-photos")
        AppFormAction(title: "Bild aus Dateien auswählen", systemImage: "doc") { files = true }
          .accessibilityIdentifier("trace-files")
      } header: {
        AppSectionHeader(
          title: "Bild-Tracing",
          help:
            "Untersucht ein Bild ohne Archiveintrag. Beim Verlassen wird es gelöscht."
        )
      }
      .disabled(model.busy || loadingPhoto || scanner.running)
      if model.busy || loadingPhoto {
        Section {
          ProgressView(loadingPhoto ? "Bild laden …" : model.progress)
            .accessibilityIdentifier("trace-progress")
          if model.busy {
            AppFormAction(title: "Erkennung abbrechen", systemImage: "stop") { model.cancel() }
              .accessibilityIdentifier("trace-cancel")
          }
        }
      }
      if let error = inputError ?? model.error {
        Section { Text(error).foregroundStyle(AppPalette.destructive) }
      }
      if let trace = model.trace {
        Section {
          LabeledContent("Erkannt", value: "\(trace.appointments.count) Termine")
          LabeledContent("Dauer", value: "\(trace.totalMs) ms")
          LabeledContent("Bild", value: "\(Int(trace.pageWidth)) × \(Int(trace.pageHeight)) px")
        }
        Section("Verarbeitungsschritte") {
          ForEach(trace.steps) { step in
            Button {
              selection = step
            } label: {
              HStack(spacing: 12) {
                Image(
                  systemName: step.stage.status == "failed"
                    ? "exclamationmark.circle" : "viewfinder"
                )
                .foregroundStyle(
                  step.stage.status == "failed" ? AppPalette.destructive : AppPalette.tint)
                VStack(alignment: .leading, spacing: 3) {
                  Text(step.title).foregroundStyle(AppPalette.text)
                  Text("\(traceStatus(step.stage.status)) · \(step.stage.durationMs) ms")
                    .font(.caption).foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppPalette.secondaryText)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
            }
            .accessibilityIdentifier("trace-step-\(step.stage.name)")
          }
        }
      } else if !model.busy && !loadingPhoto && inputError == nil && model.error == nil {
        ContentUnavailableView(
          "Bild auswählen", systemImage: "viewfinder",
          description: Text("Ein Terminbild Schritt für Schritt untersuchen."))
      }
    }
    .pageTitle("Tracing")
    .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url):
        inputError = nil
        model.start(url, timezone: timezone)
      case .failure(let error): inputError = userMessage(error)
      }
    }
    .task(id: photo) {
      guard let photo else { return }
      loadingPhoto = true
      defer {
        loadingPhoto = false
        self.photo = nil
      }
      do {
        guard let bytes = try await photo.loadTransferable(type: Data.self), !bytes.isEmpty,
          bytes.count <= 40 * 1024 * 1024
        else { throw AppError.Validation(message: "Bitte ein Bild bis 40 MB auswählen.") }
        try Task.checkCancellation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(
            photo.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
        try bytes.write(
          to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        inputError = nil
        model.start(url, timezone: timezone)
        // The model owns its own copy before ingestion; keep this selection
        // until that copy is made, then dispose it with the view's task.
        stagedPhoto = url
      } catch is CancellationError {
      } catch { inputError = userMessage(error) }
    }
    .sheet(item: $selection) { step in
      if let trace = model.trace, let application = model.core {
        NavigationStack {
          RecognitionTraceStepView(
            trace: trace, step: step, original: model.original,
            page: model.page, core: application)
        }
      }
    }
    .task { timezone = (try? await core.preferences().timezone) ?? TimeZone.current.identifier }
    .onDisappear {
      model.close()
      if let stagedPhoto { try? FileManager.default.removeItem(at: stagedPhoto) }
    }
    .onChange(of: model.busy) {
      if !model.busy, let stagedPhoto {
        try? FileManager.default.removeItem(at: stagedPhoto)
        self.stagedPhoto = nil
      }
    }
  }
  @State private var stagedPhoto: URL?
}

private struct RecognitionTraceStepView: View {
  let trace: RecognitionTrace
  let step: RecognitionTrace.Step
  let original: URL?
  let page: URL?
  let core: NativeApplication
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var imageError: String?
  @State private var selectedID: String?
  @State private var selectedPolygons: [[RecognitionTrace.Point]]?
  @State private var zoom = false
  private var polygons: [[Point]] {
    (selectedPolygons ?? trace.polygons(for: step)).map { $0.map { Point(x: $0.x, y: $0.y) } }
  }
  private var dimensions: CGSize {
    step.original
      ? (image?.size ?? CGSize(width: 1, height: 1))
      : CGSize(width: trace.pageWidth, height: trace.pageHeight)
  }
  var body: some View {
    ScrollViewReader { scroll in
      List {
        Section {
          if let image {
            Button {
              zoom = true
            } label: {
              Image(uiImage: image).resizable().scaledToFit()
                .overlay {
                  GeometryReader { geometry in
                    Path { path in
                      for polygon in polygons where !polygon.isEmpty {
                        path.addLines(
                          polygon.map {
                            CGPoint(
                              x: $0.x * geometry.size.width / dimensions.width,
                              y: $0.y * geometry.size.height / dimensions.height)
                          })
                        path.closeSubpath()
                      }
                    }.stroke(.orange, lineWidth: 1.5)
                  }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityLabel(
              "Bild mit \(polygons.count) \(polygons.count == 1 ? "Markierung" : "Markierungen") vergrößern"
            )
            .accessibilityIdentifier("trace-image")
          } else if let imageError {
            Text(imageError).foregroundStyle(AppPalette.destructive)
          } else {
            ProgressView("Bild laden …")
          }
          LabeledContent("Status", value: traceStatus(step.stage.status))
          LabeledContent("Dauer", value: "\(step.stage.durationMs) ms")
          if selectedPolygons != nil {
            AppFormAction(title: "Alle Markierungen zeigen", systemImage: "viewfinder") {
              selectedPolygons = nil
              selectedID = nil
            }
          }
        }
        .id("trace-image-section")
        Section {
          Text(step.stage.detail).textSelection(.enabled)
        } header: {
          Text("Protokoll dieses Schritts")
        }
        if step.stage.name == "recognition" || step.stage.name == "detection" {
          observations(trace.initialObservations)
        }
        if step.reread {
          Section("Nachgelesene Ausschnitte") {
            if trace.refinementAttempts.isEmpty { Text("Keine Nachlese erforderlich.") }
            ForEach(trace.refinementAttempts) { attempt in
              evidenceButton(
                id: attempt.id, title: attempt.variant,
                subtitle: "\(traceStatus(attempt.status)) · \(attempt.reason)",
                polygons: [attempt.polygon])
              DisclosureGroup("Ergebnis des Ausschnitts") {
                TraceCrop(core: core, scanID: scanID, name: "region-\(attempt.id).png")
                Text(attempt.detail).textSelection(.enabled)
                ForEach(trace.observations.filter { attempt.observationIds.contains($0.id) }) {
                  observation in
                  Text(observation.text).textSelection(.enabled)
                }
              }
            }
          }
        }
        if step.layout {
          Section("Zugeordnete Termine") {
            ForEach(trace.appointments) { appointment in
              DisclosureGroup(appointment.title.isEmpty ? "Termin ohne Titel" : appointment.title) {
                Text(
                  [appointment.date, appointment.start, appointment.end].compactMap { $0 }.joined(
                    separator: " · "))
                ForEach(appointment.fields.keys.sorted(), id: \.self) { name in
                  if let field = appointment.fields[name] {
                    let value = appointment.value(for: name).flatMap { $0.isEmpty ? nil : $0 }
                    evidenceButton(
                      id: appointment.id + name, title: traceField(name),
                      subtitle: "\(value ?? "Kein Wert") · \(field.state)",
                      polygons: field.frame == "page" ? [field.polygon] : [])
                    let ids = appointment.provenance[name] ?? []
                    let text = trace.observations.filter { ids.contains($0.id) }.map(\.text).joined(
                      separator: " · ")
                    if !text.isEmpty { Text(text).font(.caption).textSelection(.enabled) }
                    if !field.reasons.isEmpty {
                      Text(field.reasons.joined(separator: "\n")).font(.caption)
                    }
                  }
                }
              }
            }
          }
          if !trace.issues.isEmpty {
            Section("Prüfhinweise") {
              ForEach(trace.issues) { issue in
                Label(
                  issue.message,
                  systemImage: issue.blocking ? "exclamationmark.triangle" : "info.circle")
              }
            }
          }
        }
        if step.stage.artifacts.contains(where: { $0.hasSuffix(".png") }) && !step.original
          && step.stage.name != "preprocessing"
        {
          Section("Gespeicherte Ausschnitte") {
            ForEach(step.stage.artifacts.filter { $0.hasSuffix(".png") }, id: \.self) { name in
              TraceCrop(core: core, scanID: scanID, name: name)
            }
          }
        }
      }
      .onChange(of: selectedID) {
        withAnimation { scroll.scrollTo("trace-image-section", anchor: .top) }
      }
    }
    .pageTitle(step.title)
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    .sheet(isPresented: $zoom) {
      NavigationStack {
        if let image {
          ZoomImage(image: image, polygons: polygons, dimensions: dimensions)
            .pageTitle("Bild und Markierungen")
            .toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Fertig") { zoom = false } }
            }
        }
      }
    }
    .task {
      do {
        guard let url = step.original ? original : page else {
          throw AppError.Validation(message: "Für diesen Schritt wurde noch kein Bild erzeugt.")
        }
        image = try await DisplayImage.load(url)
      } catch { imageError = userMessage(error) }
    }
  }
  private var scanID: String { trace.document.id }
  private func observations(_ observations: [RecognitionTrace.Observation]) -> some View {
    Section("Text und Bildbereiche · \(observations.count)") {
      ForEach(observations) { observation in
        evidenceButton(
          id: observation.id,
          title: observation.text.isEmpty ? "Kein Text erkannt" : observation.text,
          subtitle: observation.score.map { "Engine-Signal: \(Int($0 * 100)) %" }
            ?? observation.engine,
          polygons: trace.polygons(for: observation))
      }
    }
  }
  private func evidenceButton(
    id: String, title: String, subtitle: String, polygons: [[RecognitionTrace.Point]]
  ) -> some View {
    Button {
      selectedID = id
      selectedPolygons = polygons
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(title).foregroundStyle(AppPalette.text)
          Text(subtitle).font(.caption).foregroundStyle(AppPalette.secondaryText)
        }
        Spacer()
        Image(systemName: selectedID == id ? "checkmark.circle.fill" : "viewfinder")
          .foregroundStyle(AppPalette.tint)
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
    }.buttonStyle(.plain).accessibilityHint("Markiert die zugehörige Stelle im Bild.")
      .accessibilityIdentifier("trace-evidence-\(id)")
  }
}

private struct TraceCrop: View {
  let core: NativeApplication
  let scanID: String
  let name: String
  @State private var image: UIImage?
  @State private var error: String?
  var body: some View {
    VStack(alignment: .leading) {
      if let image {
        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(
          "Erkennungsausschnitt \(name)"
        )
        .accessibilityIdentifier("trace-crop-\(name)")
      } else if let error {
        Text(error).foregroundStyle(AppPalette.secondaryText)
      } else {
        ProgressView("Ausschnitt laden …")
      }
      Text(name).font(.caption.monospaced())
    }.task {
      do {
        let path = try await core.traceArtifactPath(id: scanID, artifact: name)
        image = try await DisplayImage.load(URL(fileURLWithPath: path), maximum: 1024)
      } catch { self.error = userMessage(error) }
    }
  }
}

private func traceStatus(_ value: String) -> String {
  switch value {
  case "complete", "completed": "Abgeschlossen"
  case "partial": "Teilweise"
  case "failed": "Fehlgeschlagen"
  case "skipped": "Übersprungen"
  case "unavailable": "Nicht verfügbar"
  case "cancelled": "Abgebrochen"
  case "budget_exhausted": "Zeitbudget erreicht"
  default: value
  }
}
private func traceField(_ value: String) -> String {
  switch value {
  case "title": "Bezeichnung"
  case "date": "Datum"
  case "start": "Beginn"
  case "end": "Ende"
  case "duration_minutes": "Dauer"
  case "location": "Raum"
  case "therapist": "Therapeut:in"
  default: value
  }
}
