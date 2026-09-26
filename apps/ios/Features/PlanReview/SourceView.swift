import ImageIO
import PDFKit
import RehaCore
import SwiftUI

enum DisplayImage {
  static func load(_ url: URL, maximum: Int = 2048) async throws -> UIImage {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum,
          ] as CFDictionary)
      else { throw AppError.Validation(message: "Bild nicht verfügbar.") }
      try Task.checkCancellation()
      return UIImage(cgImage: image)
    }
    let image = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
    try Task.checkCancellation()
    return image
  }

  static func isPDF(_ url: URL) async throws -> Bool {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let isPDF = try file.read(upToCount: 5) == Data("%PDF-".utf8)
      try Task.checkCancellation()
      return isPDF
    }
    let isPDF = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
    try Task.checkCancellation()
    return isPDF
  }
}
struct SourceView: View {
  let core: NativeApplication
  let id: String
  let polygons: [[Point]]
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var pdfURL: URL?
  @State private var dimensions = CGSize(width: 1, height: 1)
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Group {
        if let pdfURL {
          SourcePDF(url: pdfURL)
        } else if let image {
          ZoomImage(image: image, polygons: polygons, dimensions: dimensions).accessibilityLabel(
            "Quellfoto. Zum Vergrößern aufziehen und zum Verschieben ziehen.")
        } else if let error {
          ContentUnavailableView(error, systemImage: "photo.badge.exclamationmark")
        } else {
          ProgressView("Foto laden …")
        }
      }
      .pageTitle("Quellfoto")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
      .task(id: id) {
        do {
          if let review = try? await core.loadScan(id: id) {
            try Task.checkCancellation()
            let path = try await core.artifactPath(id: id, artifact: "page.png")
            try Task.checkCancellation()
            let loaded = try await DisplayImage.load(URL(fileURLWithPath: path))
            try Task.checkCancellation()
            dimensions = CGSize(width: Int(review.pageWidth), height: Int(review.pageHeight))
            image = loaded
            pdfURL = nil
          } else {
            try Task.checkCancellation()
            let path = try await core.artifactPath(id: id, artifact: "source.bin")
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: path)
            let isPDF = try await DisplayImage.isPDF(url)
            try Task.checkCancellation()
            if isPDF {
              pdfURL = url
              image = nil
            } else {
              let loaded = try await DisplayImage.load(url)
              try Task.checkCancellation()
              dimensions = loaded.size
              image = loaded
              pdfURL = nil
            }
          }
        } catch {
          guard !Task.isCancelled else { return }
          self.error = userMessage(error)
        }
      }
    }
  }
}
final class ZoomScroll: UIScrollView {
  let picture = UIImageView()
  let overlay = CAShapeLayer()
  private var previousBounds = CGSize.zero
  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(picture)
    picture.layer.addSublayer(overlay)
    overlay.fillColor = UIColor.clear.cgColor
    overlay.strokeColor = UIColor.systemOrange.cgColor
    overlay.lineWidth = 2
    maximumZoomScale = 8
    backgroundColor = .systemBackground
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  func resetImageLayout() {
    previousBounds = .zero
    setNeedsLayout()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != previousBounds, picture.bounds.width > 0 {
      previousBounds = bounds.size
      minimumZoomScale = min(
        bounds.width / picture.bounds.width, bounds.height / picture.bounds.height)
      zoomScale = minimumZoomScale
      maximumZoomScale = max(8, minimumZoomScale * 8)
    }
    contentInset = UIEdgeInsets(
      top: max(0, (bounds.height - contentSize.height) / 2),
      left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
  }
}
struct ZoomImage: UIViewRepresentable {
  let image: UIImage
  let polygons: [[Point]]
  let dimensions: CGSize
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> ZoomScroll {
    let view = ZoomScroll()
    view.delegate = context.coordinator
    updateUIView(view, context: context)
    return view
  }
  func updateUIView(_ view: ZoomScroll, context: Context) {
    if view.picture.image !== image {
      view.setZoomScale(1, animated: false)
      view.picture.image = image
      view.picture.frame = CGRect(origin: .zero, size: image.size)
      view.contentSize = image.size
      view.resetImageLayout()
    }
    let path = UIBezierPath()
    for polygon in polygons where !polygon.isEmpty {
      let points = polygon.map {
        CGPoint(
          x: $0.x * image.size.width / max(1, dimensions.width),
          y: $0.y * image.size.height / max(1, dimensions.height))
      }
      path.move(to: points[0])
      for point in points.dropFirst() { path.addLine(to: point) }
      path.close()
    }
    view.overlay.path = path.cgPath
  }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      (scrollView as? ZoomScroll)?.picture
    }
  }
}
struct CorrectionView: View {
  let core: NativeApplication
  let scanner: ScanModel
  let id: String
  let width: UInt32
  let height: UInt32
  @Environment(\.dismiss) private var dismiss
  @State private var image: UIImage?
  @State private var sourcePath: String?
  @State private var turns = 0
  @State private var mirrored = false
  @State private var correctCorners = false
  @State private var corners = [
    Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1),
  ]
  @State private var error: String?
  private let labels = ["Oben links", "Oben rechts", "Unten rechts", "Unten links"]
  var body: some View {
    NavigationStack {
      List {
        if let image {
          Image(uiImage: image).resizable().scaledToFit()
            .overlay {
              if correctCorners {
                GeometryReader { geometry in
                  Path { path in
                    let points = corners.map {
                      CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height)
                    }
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()
                  }.stroke(.orange, lineWidth: 2)
                  ForEach(labels, id: \.self) { label in
                    let index = labels.firstIndex(of: label)!
                    Circle().fill(.orange).frame(width: 24, height: 24)
                      .frame(width: 44, height: 44).contentShape(.rect)
                      .position(
                        x: corners[index].x * geometry.size.width,
                        y: corners[index].y * geometry.size.height
                      )
                      .gesture(
                        DragGesture(coordinateSpace: .named("corners")).onChanged { value in
                          corners[index] = Point(
                            x: min(1, max(0, value.location.x / geometry.size.width)),
                            y: min(1, max(0, value.location.y / geometry.size.height)))
                        }
                      )
                      .accessibilityHidden(true)
                  }
                }.coordinateSpace(.named("corners"))
              }
            }
            .accessibilityLabel("Originalfoto zur Seitenkorrektur")
        }
        Section("Ausrichtung") {
          Picker("Drehung im Uhrzeigersinn", selection: $turns) {
            Text("0°").tag(0)
            Text("90°").tag(1)
            Text("180°").tag(2)
            Text("270°").tag(3)
          }
          Toggle("Spiegeln", isOn: $mirrored)
        }
        Section {
          Toggle("Seitenecken manuell setzen", isOn: $correctCorners)
          if correctCorners {
            ForEach(labels, id: \.self) { label in
              let index = labels.firstIndex(of: label)!
              VStack(alignment: .leading) {
                Text(label).font(.headline)
                Slider(value: $corners[index].x, in: 0...1) { Text("\(label), horizontal") }
                Slider(value: $corners[index].y, in: 0...1) { Text("\(label), vertikal") }
              }
            }
          }
        } header: {
          AppSectionHeader(
            title: "Seitenecken im Originalfoto",
            help:
              "Erkennt den korrigierten Ausschnitt erneut. Das Original bleibt erhalten."
          )
        }
        if let error { Text(error).foregroundStyle(AppPalette.destructive) }
      }
      .pageTitle("Foto korrigieren")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Neu erkennen") {
            guard let sourcePath else { return }
            let points =
              correctCorners
              ? corners.map { Point(x: $0.x * Double(width), y: $0.y * Double(height)) } : []
            scanner.start(
              URL(fileURLWithPath: sourcePath), turns: UInt8(turns), mirrored: mirrored,
              corners: points, force: true, removeStaged: false)
            dismiss()
          }.disabled(sourcePath == nil || scanner.running)
        }
      }
      .task(id: id) {
        do {
          let source = try await core.artifactPath(id: id, artifact: "source.bin")
          try Task.checkCancellation()
          let path = try await core.artifactPath(id: id, artifact: "original.png")
          try Task.checkCancellation()
          let loaded = try await DisplayImage.load(URL(fileURLWithPath: path))
          try Task.checkCancellation()
          sourcePath = source
          image = loaded
        } catch {
          guard !Task.isCancelled else { return }
          self.error = userMessage(error)
        }
      }
    }
  }
}
struct DiagnosticsView: View {
  let core: NativeApplication
  var id: String? = nil
  @State private var diagnostics: Diagnostics?
  @State private var capabilities: Capabilities?
  @State private var assistantName = "Wird geprüft …"
  @State private var assistantUnavailable: String?
  @State private var error: String?
  @State private var showSource = false
  var body: some View {
    Form {
      if let error { Text(error) }
      Section("Sprache") {
        LabeledContent("Stimme", value: SpeechOutput.shared.voiceName)
        LabeledContent("Audio", value: "24 kHz · lokal")
        LabeledContent("Gesprächsmodell", value: assistantName)
        if let assistantUnavailable { Text(assistantUnavailable) }
      }
      if let capabilities {
        Section("Verfügbarkeit") {
          Text(
            capabilities.recognitionAvailable
              ? "Lokale Erkennung verfügbar" : "Modelldateien oder Laufzeit fehlen")
          Text(capabilities.runtime).font(.subheadline)
        }
      }
      Section("Technische Vorgänge") {
        NavigationLink("Korrelierter Ablauf und bereinigter Export") { DiagnosticTimelineView() }
        LabeledContent(
          "App-Build",
          value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unbekannt")
        LabeledContent("iOS", value: UIDevice.current.systemVersion)
        if id != nil { Button("Original und Bildkoordinaten") { showSource = true } }
      }
      if let diagnostics {
        Section("Erkennung") {
          Text(diagnostics.engine)
          Text("Dauer: \(diagnostics.totalMs) ms")
          Text(diagnostics.sourceHash).font(.caption.monospaced()).textSelection(.enabled)
        }
        Section("Verarbeitungsschritte") {
          ForEach(Array(diagnostics.stages.enumerated()), id: \.offset) { _, stage in
            VStack(alignment: .leading) {
              Text("\(stage.name) · \(stage.status)").font(.headline)
              Text(stage.detail)
              Text("\(stage.durationMs) ms").font(.subheadline)
            }
          }
        }
        Section("Modellidentität") {
          Text(diagnostics.manifestJson).font(.caption.monospaced()).textSelection(.enabled)
        }
      }
    }.pageTitle("Diagnose")
      .sheet(isPresented: $showSource) {
        if let id { SourceView(core: core, id: id, polygons: []) }
      }
      .task {
        let provider = AssistantProviderSelection.make()
        assistantName =
          provider.identity.provider == "apple-intelligence"
          ? "Apple Intelligence" : "Lokales Testmodell"
        switch provider.availability {
        case .available: assistantUnavailable = nil
        case .unavailable(let reason): assistantUnavailable = reason
        }
        do {
          capabilities = try await core.capabilities()
          if let id { diagnostics = try await core.diagnostics(id: id) }
        } catch { self.error = userMessage(error) }
      }
  }
}

private struct SourcePDF: UIViewRepresentable {
  let url: URL
  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.document = PDFDocument(url: url)
    return view
  }
  func updateUIView(_ uiView: PDFView, context: Context) {}
}
