import AppleServices
import PhotosUI
import RehaCore
import SwiftUI
import UniformTypeIdentifiers

struct StagedPhoto: Transferable, Sendable {
  let url: URL
  static var scratch: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "photo-transfers", isDirectory: true)
  }
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      let folder = Self.scratch
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try IntakeStaging.validateSize(received.file)
      let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(
        received.file.pathExtension)
      try FileManager.default.copyItem(at: received.file, to: destination)
      return StagedPhoto(url: destination)
    }
  }
}
@MainActor @Observable final class ScanModel {
  let core: NativeApplication
  enum CaptureSource { case camera, photos, files }
  struct CaptureSession: Identifiable {
    let id = UUID()
    let source: CaptureSource
    let parent: String?
    let ticket: IntakeAdmission.Ticket
  }
  var captureSession: CaptureSession?
  private let admission = IntakeAdmission()
  private var captureTickets: [String: IntakeAdmission.Ticket] = [:]
  private(set) var isReady = false
  private(set) var isErasing = false
  private(set) var erasureError: String?
  private(set) var erasedID = UUID()
  func presentCapture(_ source: CaptureSource, parent: String?) {
    guard let ticket = admission.ticket() else { return }
    captureSession = CaptureSession(source: source, parent: parent, ticket: ticket)
  }
  func dismissCapture(_ session: CaptureSession) {
    if captureSession?.id == session.id { captureSession = nil }
  }
  private func accepted(_ id: String) -> Bool { admission.accepts(captureTickets[id]) }
  private func producer(
    _ ticket: IntakeAdmission.Ticket?, operation: @escaping @MainActor () async -> Void
  ) {
    guard let lease = admission.begin(ticket) else { return }
    Task {
      defer { admission.end(lease) }
      await operation()
    }
  }
  func initialize(_ preferences: PreferencesStore) async {
    guard !isReady, !isErasing else { return }
    erasureError = nil
    do {
      let pending = try await Task.detached { try IntakeStaging.gate().snapshot().erasing }.value
      if pending {
        try await eraseLocalData(preferences)
      } else {
        admission.open()
        isReady = true
      }
    } catch { erasureError = userMessage(error) }
  }
  func eraseLocalData(_ preferences: PreferencesStore) async throws {
    guard erasureTask == nil else { return }
    isErasing = true
    isReady = false
    erasureError = nil
    admission.close()
    captureSession = nil
    captureTickets.removeAll()
    cancel()
    let task = Task { @MainActor in
      do {
        try await Task.detached { try IntakeStaging.gate().beginErasure() }.value
        _ = await preferences.flush()
        while !admission.isDrained || !tasks.isEmpty || core.recognitionBusy() {
          try await Task.sleep(for: .milliseconds(50))
        }
        try await core.eraseAll()
        try await LocalDiagnostics.shared.erase()
        try await Task.detached {
          let files = FileManager.default
          for folder in [
            try AppStorage.prepare().appendingPathComponent("inbox"), StagedPhoto.scratch,
          ] {
            if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
          }
          try IntakeStaging.gate().finishErasure()
        }.value
        await preferences.reset()
        progress = nil
        error = nil
        finishedID = nil
        presentedID = nil
        currentID = nil
        sourceStored = false
        parents.removeAll()
        cancelled.removeAll()
        queueOrder.removeAll()
        scheduledIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "agenda.density")
        UserDefaults.standard.removeObject(forKey: "agenda.list")
        erasedID = UUID()
        isErasing = false
        isReady = true
        admission.open()
        updateRunning()
      } catch {
        erasureError = userMessage(error)
        throw error
      }
    }
    erasureTask = task
    defer { erasureTask = nil }
    try await task.value
  }
  private var erasureTask: Task<Void, Error>?
  func loadPhoto(_ item: PhotosPickerItem, session: CaptureSession) {
    guard let id = beginCapture(parent: session.parent, ticket: session.ticket) else { return }
    producer(session.ticket) {
      do {
        guard let photo = try await item.loadTransferable(type: StagedPhoto.self) else {
          throw AppError.Validation(message: "Foto ist nicht lokal verfügbar.")
        }
        guard self.accepted(id) else {
          try? FileManager.default.removeItem(at: photo.url)
          return
        }
        let retained = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let destination = folder.appendingPathComponent(id).appendingPathExtension(
            photo.url.pathExtension)
          try FileManager.default.copyItem(at: photo.url, to: destination)
          try FileManager.default.removeItem(at: photo.url)
          return destination
        }.value
        guard self.accepted(id) else { return }
        self.start(retained, force: session.parent != nil, captureID: id)
      } catch { self.fail(error, id: id) }
    }
  }
  var progress: JobProgress?
  var running = false
  var error: String?
  var finishedID: String?
  var presentedID: String?
  var currentID: String?
  var sourceStored = false
  private var tasks: [String: Task<Void, Never>] = [:]
  private var processingID: String?
  var activePageID: String? { processingID }
  private var scheduledIDs = Set<String>()
  private var queueOrder: [String] = []
  private func finishQueue(_ id: String) {
    scheduledIDs.remove(id)
    queueOrder.removeAll { $0 == id }
  }
  private var parents: [String: String] = [:]
  private var pendingIntakes = 0
  private var documentJobs = 0
  private var documentGeneration = UUID()
  private var recoveringShares = false
  private var awaitingBytes = Set<String>()
  private var suspended = false
  func suspend() {
    suspended = true
    cancel()
  }
  func resume() { suspended = false }
  private func updateRunning() {
    running = !tasks.isEmpty || pendingIntakes > 0 || documentJobs > 0 || !awaitingBytes.isEmpty
  }
  private var cancelled = Set<String>()
  init(core: NativeApplication) { self.core = core }
  @discardableResult func beginCapture(parent: String? = nil, ticket: IntakeAdmission.Ticket? = nil)
    -> String?
  {
    guard let ticket = ticket ?? admission.ticket(), admission.accepts(ticket) else { return nil }
    if parent == nil { cancel() }
    let id = UUID().uuidString
    captureTickets[id] = ticket
    LocalDiagnostics.shared.record(.intake, .started, correlation: id)
    if let parent { parents[id] = parent }
    awaitingBytes.insert(id)
    currentID = id
    presentedID = parent.map { "plan:\($0)" } ?? id
    running = true
    sourceStored = false
    error = nil
    finishedID = nil
    progress = nil
    return id
  }
  func receive(_ bytes: Data, id: String) {
    guard accepted(id) else { return }
    producer(captureTickets[id]) { [self] in
      do {
        let url = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let url = folder.appendingPathComponent(id).appendingPathExtension("jpg")
          try bytes.write(to: url, options: .atomic)
          return url
        }.value
        start(url, captureID: id)
      } catch { fail(error, id: id) }
    }
  }
  func fail(_ failure: Error, id: String) {
    guard accepted(id), currentID == id else { return }
    awaitingBytes.remove(id)
    updateRunning()
    error = userMessage(failure)
  }
  func start(
    _ url: URL, turns: UInt8 = 0, mirrored: Bool = false, corners: [Point] = [],
    force: Bool = false, removeStaged: Bool = true, captureID: String? = nil
  ) {
    guard let id = captureID ?? beginCapture(), accepted(id) else { return }
    guard !scheduledIDs.contains(id) else { return }
    scheduledIDs.insert(id)
    queueOrder.append(id)
    awaitingBytes.remove(id)
    pendingIntakes += 1
    updateRunning()
    // Persist even a late callback from an abandoned capture, but never let it
    // change the active result, edits or navigation.
    producer(captureTickets[id]) { [self] in
      defer {
        pendingIntakes -= 1
        if tasks[id] == nil { finishQueue(id) }
        updateRunning()
      }
      do {
        _ = try await core.stagePhoto(id: id, path: url.path)
        if removeStaged { try? FileManager.default.removeItem(at: url) }
        guard accepted(id) else { return }
        guard accepted(id) else { return }
        if let parent = parents[id] {
          _ = try await core.appendPages(id: parent, pages: [id])
        }
        guard accepted(id), !cancelled.contains(id), !suspended else { return }
        if currentID == id { sourceStored = true }
        let retained = try await core.artifactPath(id: id, artifact: "source.bin")
        guard accepted(id) else { return }
        tasks[id] = Task {
          while queueOrder.first != id || processingID != nil || core.recognitionBusy() {
            do { try await Task.sleep(for: .milliseconds(100)) } catch {
              tasks[id] = nil
              finishQueue(id)
              updateRunning()
              return
            }
          }
          guard !Task.isCancelled else {
            tasks[id] = nil
            finishQueue(id)
            updateRunning()
            return
          }
          processingID = id
          let poll = Task {
            while !Task.isCancelled {
              if currentID == id { progress = core.jobProgress(id: id) }
              try? await Task.sleep(for: .milliseconds(100))
            }
          }
          defer {
            poll.cancel()
            processingID = nil
            tasks[id] = nil
            finishQueue(id)
            updateRunning()
            if currentID == id { progress = nil }
          }
          do {
            let preferences = try await core.preferences()
            guard accepted(id), !Task.isCancelled else { return }
            let result = try await withTaskCancellationHandler {
              try await core.importPhoto(
                request: PhotoRequest(
                  id: id, path: retained, timezone: preferences.timezone, quarterTurns: turns,
                  mirrored: mirrored, pageCorners: corners, force: force))
            } onCancel: { [core] in
              try? core.cancelJob(id: id)
            }
            if result.duplicate && currentID == id { presentedID = result.scan.document.id }
            LocalDiagnostics.shared.record(
              .interpretation, .completed, correlation: id, count: result.scan.appointments.count)
            if let diagnostics = try? await core.diagnostics(id: result.scan.document.id) {
              for stage in diagnostics.stages {
                let step: DiagnosticStep =
                  stage.name.contains("refin")
                  ? .refinement
                  : stage.name.contains("ocr")
                    ? .ocr
                    : stage.name.contains("pars")
                      ? .interpretation : stage.name.contains("column") ? .mapping : .preparation
                LocalDiagnostics.shared.record(
                  step, stage.status == "failed" ? .failed : .completed, correlation: id,
                  durationMs: Int(stage.durationMs))
              }
            }
            guard !Task.isCancelled, !cancelled.contains(id) else { return }
            finishedID = result.scan.document.id
          } catch {
            guard currentID == id else { return }
            self.error = userMessage(error)
            if let draft = try? await core.loadScan(id: id) { finishedID = draft.document.id }
          }
        }
      } catch { fail(error, id: id) }
    }
  }
  func retry(_ id: String) {
    guard !running, let ticket = admission.ticket() else { return }
    captureTickets[id] = ticket
    currentID = id
    running = true
    sourceStored = true
    finishedID = nil
    error = nil
    cancelled.remove(id)
    tasks[id] = Task {
      let poll = Task {
        while !Task.isCancelled {
          progress = core.jobProgress(id: id)
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
      defer {
        poll.cancel()
        tasks[id] = nil
        updateRunning()
        progress = nil
      }
      do {
        let path = try await core.artifactPath(id: id, artifact: "source.bin")
        let url = URL(fileURLWithPath: path)
        let pdf = try await Task.detached {
          let file = try FileHandle(forReadingFrom: url)
          defer { try? file.close() }
          return try file.read(upToCount: 5) == Data("%PDF-".utf8)
        }.value
        if pdf {
          await ingestFile(url, id: id, navigate: false)
          return
        }
        guard accepted(id) else { return }
        let review = try await core.retryCapture(id: id)
        guard accepted(id) else { return }
        finishedID = review.document.id
      } catch { self.error = userMessage(error) }
    }
  }
  func importFile(
    _ url: URL, receiptID: String? = nil, navigate: Bool = true, parent: String? = nil,
    ticket: IntakeAdmission.Ticket? = nil
  ) {
    guard let ticket = ticket ?? admission.ticket(), admission.accepts(ticket) else { return }
    let id = receiptID ?? UUID().uuidString
    captureTickets[id] = ticket
    if let parent { parents[id] = parent }
    if navigate {
      currentID = id
      presentedID = "plan:\(parent ?? id)"
      error = nil
      sourceStored = false
    }
    running = true
    producer(ticket) { [self] in await ingestFile(url, id: id, navigate: navigate) }
  }
  private func ingestFile(_ url: URL, id: String, navigate: Bool) async {
    guard let ticket = captureTickets[id], admission.accepts(ticket) else { return }
    let generation = documentGeneration
    documentJobs += 1
    updateRunning()
    defer {
      documentJobs -= 1
      updateRunning()
    }
    do {
      let staged = try await Task.detached {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try IntakeStaging.validateSize(url)
        let root = try AppStorage.prepare().appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(id).appendingPathExtension(url.pathExtension)
        if destination != url && !FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.copyItem(at: url, to: destination)
        }
        return destination
      }.value
      guard accepted(id) else { return }
      _ = try await core.stagePhoto(id: id, path: staged.path)
      try? FileManager.default.removeItem(at: staged)
      let path = try await core.artifactPath(id: id, artifact: "source.bin")
      let original = URL(fileURLWithPath: path)
      let pdf = try await Task.detached {
        let file = try FileHandle(forReadingFrom: original)
        defer { try? file.close() }
        return try file.read(upToCount: 5) == Data("%PDF-".utf8)
      }.value
      guard admission.accepts(ticket), generation == documentGeneration, !suspended,
        !Task.isCancelled
      else { return }
      if navigate { sourceStored = true }
      if !pdf {
        if (try? await core.loadScan(id: id)) == nil {
          start(original, removeStaged: false, captureID: id)
        } else {
          finishedID = id
          updateRunning()
        }
        return
      }
      let count = try await Task.detached { try PDFIntake.pageCount(original) }.value
      guard accepted(id), generation == documentGeneration else { return }
      let pages = try await core.pdfPages(id: id, count: UInt32(count))
      guard accepted(id) else { return }
      if let parent = parents[id] {
        _ = try await core.appendPages(id: parent, pages: pages)
      }
      for (index, page) in pages.enumerated() {
        captureTickets[page] = ticket
        guard admission.accepts(ticket), generation == documentGeneration, !suspended,
          !Task.isCancelled
        else { return }
        if (try? await core.loadScan(id: page)) != nil { continue }
        if let existing = try? await core.artifactPath(id: page, artifact: "source.bin") {
          start(URL(fileURLWithPath: existing), force: true, removeStaged: false, captureID: page)
          continue
        }
        let rendered = try await Task.detached { try PDFIntake.render(original, index: index) }
          .value
        guard admission.accepts(ticket), generation == documentGeneration, !suspended,
          !Task.isCancelled
        else { return }
        let temporary = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          let url = folder.appendingPathComponent(page).appendingPathExtension("png")
          try rendered.png.write(to: url, options: .atomic)
          return url
        }.value
        guard accepted(id) else { return }
        _ = try await core.stagePhoto(id: page, path: temporary.path)
        guard accepted(id) else { return }
        try await core.retainPdfEvidence(pageId: page, evidenceJson: rendered.evidence)
        guard admission.accepts(ticket), generation == documentGeneration, !suspended,
          !Task.isCancelled
        else { return }
        start(temporary, force: true, captureID: page)
      }
      finishedID = id
      updateRunning()
    } catch {
      self.error = userMessage(error)
      updateRunning()
    }
  }
  func recoverShares() async {
    guard !recoveringShares, let ticket = admission.ticket(), let lease = admission.begin(ticket)
    else { return }
    defer { admission.end(lease) }
    recoveringShares = true
    defer { recoveringShares = false }
    do {
      let receipts = try await Task.detached { try IntakeStaging.pending() }.value
      for (receipt, url, folder) in receipts {
        guard admission.accepts(ticket) else { return }
        captureTickets[receipt.id] = ticket
        await ingestFile(url, id: receipt.id, navigate: false)
        // Receipt cleanup follows shared-core persistence, even if PDF
        // decoding failed. The archive can retry the retained original.
        if (try? await core.artifactPath(id: receipt.id, artifact: "source.bin")) != nil {
          try? FileManager.default.removeItem(at: folder)
        }
      }
    } catch { self.error = userMessage(error) }
  }
  func recoverInbox() async {
    guard let ticket = admission.ticket(), let lease = admission.begin(ticket) else { return }
    defer { admission.end(lease) }
    do {
      let urls = try await Task.detached {
        let folder = try AppStorage.prepare().appendingPathComponent("inbox")
        return
          (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
      }.value
      for url in urls {
        guard admission.accepts(ticket) else { return }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
          continue
        }
        let name = url.deletingPathExtension().lastPathComponent
        let id = UUID(uuidString: name) == nil ? UUID().uuidString : name
        do {
          _ = try await core.stagePhoto(id: id, path: url.path)
          try FileManager.default.removeItem(at: url)
        } catch { self.error = userMessage(error) }
      }
      guard admission.accepts(ticket) else { return }
      await recoverShares()
      guard admission.accepts(ticket) else { return }
      let history = try await core.history()
      for intake in history.intakes where intake.status == "document" {
        guard admission.accepts(ticket) else { return }
        captureTickets[intake.id] = ticket
        let pages = try await core.pageGroup(id: intake.id)
        if pages.contains(where: { page in
          !history.scans.contains(where: { $0.id == page && $0.retained })
        }) {
          let path = try await core.artifactPath(id: intake.id, artifact: "source.bin")
          await ingestFile(URL(fileURLWithPath: path), id: intake.id, navigate: false)
        }
      }
    } catch { self.error = userMessage(error) }
  }
  func cancel() {
    documentGeneration = UUID()
    if let currentID { LocalDiagnostics.shared.record(.intake, .cancelled, correlation: currentID) }
    if let currentID {
      cancelled.insert(currentID)
      try? core.cancelJob(id: currentID)
    }
    for (id, task) in tasks {
      cancelled.insert(id)
      try? core.cancelJob(id: id)
      task.cancel()
    }
    awaitingBytes.removeAll()
    updateRunning()
  }
}
