import PhotosUI
import RehaCore
import SwiftUI

/// Buttons only: presentation belongs to NativeShell, which survives Menu dismissal.
struct CaptureActions: View {
  let scanner: ScanModel
  var parentID: String?
  var context = "capture"
  var body: some View {
    Button(
      parentID == nil ? "Foto aufnehmen" : "Weitere Seite fotografieren", systemImage: "camera"
    ) {
      scanner.presentCapture(.camera, parent: parentID)
    }.accessibilityIdentifier("\(context)-camera").disabled(
      !scanner.isReady || (parentID == nil && scanner.running))
    Button(
      parentID == nil ? "Aus Fotos wählen" : "Weitere Seite aus Fotos",
      systemImage: "photo.on.rectangle"
    ) {
      scanner.presentCapture(.photos, parent: parentID)
    }.accessibilityIdentifier("\(context)-photos").disabled(
      !scanner.isReady || (parentID == nil && scanner.running))
    Button("Datei importieren", systemImage: "folder") {
      scanner.presentCapture(.files, parent: parentID)
    }.accessibilityIdentifier("\(context)-files").disabled(!scanner.isReady || scanner.running)
  }
}

/// Each presentation has an immutable erasure ticket. Replacing this view cannot
/// authorize callbacks from an earlier camera, picker, or document provider.
struct CapturePresentation: View {
  let scanner: ScanModel
  let session: ScanModel.CaptureSession
  @State private var photo: PhotosPickerItem?
  @State private var camera = false
  @State private var photos = false
  @State private var files = false
  var body: some View {
    Color.clear.frame(width: 0, height: 0)
      .task {
        switch session.source {
        case .camera: camera = true
        case .photos: photos = true
        case .files: files = true
        }
      }
      .fullScreenCover(isPresented: $camera, onDismiss: { scanner.dismissCapture(session) }) {
        CaptureView(
          onShutter: {
            let id = scanner.beginCapture(parent: session.parent, ticket: session.ticket)
            camera = false
            return id
          }, onPhoto: { bytes, id in scanner.receive(bytes, id: id) },
          onFailure: { error, id in scanner.fail(error, id: id) })
      }
      .photosPicker(
        isPresented: $photos, selection: $photo, matching: .images, preferredItemEncoding: .current
      )
      .onChange(of: photo) { _, item in
        if let item {
          scanner.loadPhoto(item, session: session)
          photo = nil
        }
      }
      .fileImporter(isPresented: $files, allowedContentTypes: [.image, .pdf]) { result in
        if case .success(let url) = result {
          scanner.importFile(url, parent: session.parent, ticket: session.ticket)
        } else if case .failure(let error) = result, scanner.captureSession?.id == session.id {
          scanner.error = userMessage(error)
        }
        scanner.dismissCapture(session)
      }
  }
}

struct PlanDestination: View {
  let core: NativeApplication
  let scanner: ScanModel
  let id: String
  let changed: () -> Void
  var body: some View {
    let planID = id.replacingOccurrences(of: "plan:", with: "").replacingOccurrences(
      of: "page:", with: "")
    ReviewView(core: core, scanner: scanner, id: planID, changed: changed)
      .id(planID)
  }
}

struct PlanPagesView: View {
  @Environment(\.dismiss) private var dismiss
  let core: NativeApplication
  let scanner: ScanModel
  let id: String
  @State private var model = PlanPagesModel()
  private var pageIDs: [String] { model.snapshot.pageIDs }
  private var reviews: [String: ReviewSnapshot] { model.snapshot.reviews }
  @State private var calendar = false
  @State private var remove: String?
  @State private var original = false
  var body: some View {
    List {
      Section { Button("Originaldatei ansehen", systemImage: "doc") { original = true } }
      Section("Weitere Seite") { CaptureActions(scanner: scanner, parentID: id) }
      ForEach(Array(pageIDs.enumerated()), id: \.element) { index, page in
        Section("Seite \(index + 1)") {
          if let review = reviews[page] {
            ForEach(review.appointments, id: \.id) { appointment in
              NavigationLink(value: "page:\(page)") {
                VStack(alignment: .leading) {
                  Text(appointment.title)
                  Text(
                    "\(appointment.date ?? "Datum offen") · \(appointment.start ?? "Beginn offen")"
                  ).font(.subheadline)
                }
              }
            }
            NavigationLink("Seite prüfen und Original ansehen", value: "page:\(page)")
          } else {
            Text(
              scanner.activePageID == page
                ? "Erkennung läuft …"
                : scanner.running
                  ? "Seite gespeichert · wartet auf Erkennung"
                  : "Seite gespeichert · Erkennung noch offen")
            Button("Erneut versuchen") { scanner.retry(page) }.disabled(scanner.running)
            NavigationLink("Original und Details", value: "page:\(page)")
          }
          if index > 0 {
            Button("Seite aus Plan lösen", role: .destructive) { remove = page }.foregroundStyle(
              AppPalette.destructive
            ).disabled(
              scanner.running)
          }
        }
      }
      if let error = model.error { Text(error).foregroundStyle(AppPalette.destructive) }
    }
    .pageTitle("Seiten")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    .task { await load() }
    .onChange(of: scanner.finishedID) { _, _ in Task { await load() } }
    .onChange(of: scanner.sourceStored) { _, _ in Task { await load() } }
    .sheet(isPresented: $original) { SourceView(core: core, id: id, polygons: []) }
    .sheet(isPresented: $calendar, onDismiss: { Task { await load() } }) {
      if let first = pageIDs.first.flatMap({ reviews[$0] }) {
        CalendarView(core: core, original: first, pages: pageIDs.compactMap { reviews[$0] })
      }
    }
    .confirmationDialog(
      "Seite als eigenen Plan im Archiv behalten?",
      isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }),
      titleVisibility: .visible
    ) {
      Button("Seite aus Plan lösen") {
        guard let remove else { return }
        Task {
          do {
            _ = try await core.setPageGroup(id: id, pageIds: pageIDs.filter { $0 != remove })
            await load()
          } catch { model.error = userMessage(error) }
        }
      }
    }
  }
  private func load() async {
    await model.load(core: core, id: id)
  }
}
