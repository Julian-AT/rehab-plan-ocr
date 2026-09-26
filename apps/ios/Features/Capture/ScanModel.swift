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
  private let attempts = ScanAttemptRegistry()
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
  private func register(
    _ id: String, ticket: IntakeAdmission.Ticket, parent: String? = nil
  ) -> ScanAttemptRegistry.Attempt? {
    do { return try attempts.register(id: id, ticket: ticket, parent: parent) } catch {
      self.error = userMessage(error)
      return nil
    }
  }
  private func canRetain(_ attempt: ScanAttemptRegistry.Attempt) -> Bool {
    admission.accepts(attempt.ticket) && attempts.owns(attempt)
  }
  private func canProcess(_ attempt: ScanAttemptRegistry.Attempt) -> Bool {
    canRetain(attempt) && attempts.permits(attempt) && !suspended
  }
  private func release(_ lease: ScanAttemptRegistry.Lease) {
    if attempts.end(lease) { awaitingBytes.remove(lease.attempt.id) }
    updateRunning()
  }
  private func releaseAfterRecognition(_ lease: ScanAttemptRegistry.Lease) {
    attempts.endAfterDrain(lease) { [core] in
      core.recognitionBusy()
    } completion: { [self] retired in
      if retired { awaitingBytes.remove(lease.attempt.id) }
      updateRunning()
    }
  }
  private func producer(
    _ attempt: ScanAttemptRegistry.Attempt, operation: @escaping @MainActor () async -> Void
  ) {
    guard let intake = admission.begin(attempt.ticket) else { return }
    guard let owner = attempts.begin(attempt) else {
      admission.end(intake)
      return
    }
    attempts.finishInput(attempt)
    Task {
      defer {
        admission.end(intake)
        release(owner)
      }
      await operation()
    }
  }
  func initialize(_ preferences: PreferencesStore) async {
    guard !isReady, !isErasing else { return }
    erasureError = nil
    do {
      try await AppTemporaryStore.shared.prepare()
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
    cancel()
    let task = Task { @MainActor in
      do {
        try await Task.detached { try IntakeStaging.gate().beginErasure() }.value
        try await AppTemporaryStore.shared.erase()
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
        await AppTemporaryStore.shared.resume()
        progress = nil
        error = nil
        finishedID = nil
        presentedID = nil
        currentID = nil
        sourceStored = false
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
    guard let id = beginCapture(parent: session.parent, ticket: session.ticket),
      let attempt = attempts.active(id)
    else { return }
    producer(attempt) {
      do {
        guard let photo = try await item.loadTransferable(type: StagedPhoto.self) else {
          throw AppError.Validation(message: "Foto ist nicht lokal verfügbar.")
        }
        guard self.canRetain(attempt) else {
          try? FileManager.default.removeItem(at: photo.url)
          return
        }
        let retained = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let destination = folder.appendingPathComponent(id).appendingPathExtension(
            photo.url.pathExtension)
          _ = try IntakeInbox.stage(photo.url, at: destination)
          try FileManager.default.removeItem(at: photo.url)
          return destination
        }.value
        guard self.canRetain(attempt) else { return }
        self.start(retained, force: session.parent != nil, attempt: attempt)
      } catch { self.fail(error, attempt: attempt) }
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
  private var recognitionJobs: [String: RecognitionJob] = [:]
  init(core: NativeApplication) { self.core = core }
  @discardableResult func beginCapture(parent: String? = nil, ticket: IntakeAdmission.Ticket? = nil)
    -> String?
  {
    guard let ticket = ticket ?? admission.ticket(), admission.accepts(ticket) else { return nil }
    if parent == nil { cancel() }
    let id = UUID().uuidString
    guard register(id, ticket: ticket, parent: parent) != nil else { return nil }
    LocalDiagnostics.shared.record(.intake, .started, correlation: id)
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
    guard let attempt = attempts.active(id), canRetain(attempt) else { return }
    producer(attempt) { [self] in
      do {
        let url = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          let url = folder.appendingPathComponent(id).appendingPathExtension("jpg")
          try bytes.write(to: url, options: .atomic)
          return url
        }.value
        start(url, attempt: attempt)
      } catch { fail(error, attempt: attempt) }
    }
  }
  func fail(_ failure: Error, id: String) {
    guard let attempt = attempts.active(id) else { return }
    fail(failure, attempt: attempt)
  }
  private func fail(_ failure: Error, attempt: ScanAttemptRegistry.Attempt) {
    guard canProcess(attempt) else { return }
    awaitingBytes.remove(attempt.id)
    attempts.finishInput(attempt)
    updateRunning()
    if currentID == attempt.id { error = userMessage(failure) }
  }
  func start(
    _ url: URL, turns: UInt8 = 0, mirrored: Bool = false, corners: [Point] = [],
    force: Bool = false, removeStaged: Bool = true, captureID: String? = nil
  ) {
    guard let id = captureID ?? beginCapture(), let attempt = attempts.active(id) else { return }
    start(
      url, turns: turns, mirrored: mirrored, corners: corners, force: force,
      removeStaged: removeStaged, attempt: attempt)
  }
  private func start(
    _ url: URL, turns: UInt8 = 0, mirrored: Bool = false, corners: [Point] = [],
    force: Bool = false, removeStaged: Bool = true, attempt: ScanAttemptRegistry.Attempt
  ) {
    guard canRetain(attempt) else { return }
    let id = attempt.id
    guard !scheduledIDs.contains(id) else { return }
    scheduledIDs.insert(id)
    queueOrder.append(id)
    awaitingBytes.remove(id)
    pendingIntakes += 1
    updateRunning()
    // Persist even a late callback from an abandoned capture, but never let it
    // change the active result, edits or navigation.
    producer(attempt) { [self] in
      defer {
        pendingIntakes -= 1
        if tasks[id] == nil { finishQueue(id) }
        updateRunning()
      }
      do {
        _ = try await core.stagePhoto(id: id, path: url.path)
        if removeStaged { try? FileManager.default.removeItem(at: url) }
        guard canProcess(attempt) else { return }
        if let parent = attempt.parent {
          _ = try await core.appendPages(id: parent, pages: [id])
        }
        guard canProcess(attempt) else { return }
        if currentID == id { sourceStored = true }
        let retained = try await core.artifactPath(id: id, artifact: "source.bin")
        guard canProcess(attempt), let worker = attempts.begin(attempt) else { return }
        tasks[id] = Task {
          defer { releaseAfterRecognition(worker) }
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
              guard canProcess(attempt) else { return }
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
            guard canProcess(attempt), !Task.isCancelled else { return }
            let job = try core.registerJob(id: id)
            recognitionJobs[id] = job
            defer {
              job.close()
              recognitionJobs[id] = nil
            }
            let result = try await withTaskCancellationHandler {
              try await core.importPhoto(
                request: PhotoRequest(
                  id: id, path: retained, timezone: preferences.timezone, quarterTurns: turns,
                  mirrored: mirrored, pageCorners: corners, force: force), job: job)
            } onCancel: {
              job.cancel()
            }
            guard canProcess(attempt), !Task.isCancelled else { return }
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
            guard canProcess(attempt), !Task.isCancelled else { return }
            finishedID = result.scan.document.id
          } catch {
            guard canProcess(attempt), currentID == id, !Task.isCancelled else { return }
            self.error = userMessage(error)
            if let draft = try? await core.loadScan(id: id), canProcess(attempt), currentID == id {
              finishedID = draft.document.id
            }
          }
        }
      } catch { fail(error, attempt: attempt) }
    }
  }
  func retry(_ id: String) {
    guard !running, let ticket = admission.ticket() else { return }
    guard let attempt = register(id, ticket: ticket), let worker = attempts.begin(attempt) else {
      return
    }
    attempts.finishInput(attempt)
    currentID = id
    running = true
    sourceStored = true
    finishedID = nil
    error = nil
    tasks[id] = Task {
      defer { releaseAfterRecognition(worker) }
      let poll = Task {
        while !Task.isCancelled {
          guard canProcess(attempt) else { return }
          if currentID == id { progress = core.jobProgress(id: id) }
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
      defer {
        poll.cancel()
        tasks[id] = nil
        updateRunning()
        if currentID == id { progress = nil }
      }
      do {
        let path = try await core.artifactPath(id: id, artifact: "source.bin")
        guard canProcess(attempt), !Task.isCancelled else { return }
        let url = URL(fileURLWithPath: path)
        let pdf = try await Task.detached {
          let file = try FileHandle(forReadingFrom: url)
          defer { try? file.close() }
          return try file.read(upToCount: 5) == Data("%PDF-".utf8)
        }.value
        guard canProcess(attempt), !Task.isCancelled else { return }
        if pdf {
          await ingestFile(url, attempt: attempt, navigate: false)
          return
        }
        guard canProcess(attempt), !Task.isCancelled else { return }
        let job = try core.registerJob(id: id)
        recognitionJobs[id] = job
        defer {
          job.close()
          recognitionJobs[id] = nil
        }
        let review = try await withTaskCancellationHandler {
          try await core.retryCapture(id: id, job: job)
        } onCancel: {
          job.cancel()
        }
        guard canProcess(attempt), !Task.isCancelled else { return }
        finishedID = review.document.id
      } catch {
        if canProcess(attempt), currentID == id, !Task.isCancelled {
          self.error = userMessage(error)
        }
      }
    }
  }
  func importFile(
    _ url: URL, receiptID: String? = nil, navigate: Bool = true, parent: String? = nil,
    ticket: IntakeAdmission.Ticket? = nil
  ) {
    guard let ticket = ticket ?? admission.ticket(), admission.accepts(ticket) else { return }
    let id = receiptID ?? UUID().uuidString
    guard let attempt = register(id, ticket: ticket, parent: parent) else { return }
    if navigate {
      currentID = id
      presentedID = "plan:\(parent ?? id)"
      error = nil
      sourceStored = false
    }
    running = true
    producer(attempt) { [self] in await ingestFile(url, attempt: attempt, navigate: navigate) }
  }
  private func ingestFile(
    _ url: URL, attempt: ScanAttemptRegistry.Attempt, navigate: Bool,
    alreadyRetained: Bool = false
  ) async {
    guard canRetain(attempt), let owner = attempts.begin(attempt) else { return }
    attempts.finishInput(attempt)
    let id = attempt.id
    documentJobs += 1
    updateRunning()
    defer {
      documentJobs -= 1
      release(owner)
    }
    do {
      if !alreadyRetained {
        let staged = try await Task.detached {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          let root = try AppStorage.prepare().appendingPathComponent("inbox")
          let destination = root.appendingPathComponent(id).appendingPathExtension(
            url.pathExtension)
          return try IntakeInbox.stage(url, at: destination)
        }.value
        guard canRetain(attempt) else { return }
        _ = try await core.stagePhoto(id: id, path: staged.path)
        try? FileManager.default.removeItem(at: staged)
      }
      guard canProcess(attempt), !Task.isCancelled else { return }
      let path = try await core.artifactPath(id: id, artifact: "source.bin")
      guard canProcess(attempt), !Task.isCancelled else { return }
      let original = URL(fileURLWithPath: path)
      let pdf = try await Task.detached {
        let file = try FileHandle(forReadingFrom: original)
        defer { try? file.close() }
        return try file.read(upToCount: 5) == Data("%PDF-".utf8)
      }.value
      guard canProcess(attempt), !Task.isCancelled else { return }
      if navigate, currentID == id { sourceStored = true }
      if !pdf {
        let existing = try? await core.loadScan(id: id)
        guard canProcess(attempt), !Task.isCancelled else { return }
        if existing == nil {
          start(original, removeStaged: false, attempt: attempt)
        } else {
          finishedID = id
          updateRunning()
        }
        return
      }
      let count = try await Task.detached { try PDFIntake.pageCount(original) }.value
      guard canProcess(attempt), !Task.isCancelled else { return }
      let pages = try await core.pdfPages(id: id, count: UInt32(count))
      guard canProcess(attempt), !Task.isCancelled else { return }
      if let parent = attempt.parent {
        _ = try await core.appendPages(id: parent, pages: pages)
      }
      for (index, page) in pages.enumerated() {
        guard canProcess(attempt), !Task.isCancelled else { return }
        let existingReview = try? await core.loadScan(id: page)
        guard canProcess(attempt), !Task.isCancelled else { return }
        if existingReview != nil { continue }
        // Another recovery may already have admitted this same PDF page. Its
        // exact attempt, including revoked work still draining, remains owner.
        if attempts.contains(page) { continue }
        let child = try attempts.register(id: page, ticket: attempt.ticket)
        guard let pageOwner = attempts.begin(child) else { return }
        attempts.finishInput(child)
        defer { release(pageOwner) }
        let existing = try? await core.artifactPath(id: page, artifact: "source.bin")
        guard canProcess(attempt), canProcess(child), !Task.isCancelled else { return }
        if let existing {
          start(URL(fileURLWithPath: existing), force: true, removeStaged: false, attempt: child)
          continue
        }
        let rendered = try await Task.detached { try PDFIntake.render(original, index: index) }
          .value
        guard canProcess(attempt), canProcess(child), !Task.isCancelled else { return }
        let temporary = try await Task.detached {
          let folder = try AppStorage.prepare().appendingPathComponent("inbox")
          let url = folder.appendingPathComponent(page).appendingPathExtension("png")
          try rendered.png.write(to: url, options: .atomic)
          return url
        }.value
        guard canRetain(attempt), canRetain(child) else { return }
        _ = try await core.stagePhoto(id: page, path: temporary.path)
        guard canRetain(attempt), canRetain(child) else { return }
        try await core.retainPdfEvidence(pageId: page, evidenceJson: rendered.evidence)
        guard canProcess(attempt), canProcess(child), !Task.isCancelled else { return }
        start(temporary, force: true, attempt: child)
      }
      guard canProcess(attempt), !Task.isCancelled else { return }
      finishedID = id
      updateRunning()
    } catch {
      if canProcess(attempt), !Task.isCancelled { self.error = userMessage(error) }
      updateRunning()
    }
  }
  func recoverShares() async {
    guard !recoveringShares, let ticket = admission.ticket(), let lease = admission.begin(ticket)
    else { return }
    defer { admission.end(lease) }
    let generation = documentGeneration
    recoveringShares = true
    defer { recoveringShares = false }
    do {
      let pending = try await Task.detached { try IntakeStaging.pending() }.value
      for (receipt, url, folder) in pending.receipts {
        guard admission.accepts(ticket), generation == documentGeneration else { return }
        guard !attempts.contains(receipt.id),
          let attempt = register(receipt.id, ticket: ticket), let owner = attempts.begin(attempt)
        else { continue }
        attempts.finishInput(attempt)
        defer { release(owner) }
        do {
          // Bypass the inbox: a crash during its old non-atomic copy may have
          // left different bytes under this same ID. Core verifies this exact
          // receipt against the immutable original before acknowledging it.
          let retained = try await IntakeStaging.retainReceipt(
            receipt, source: url, folder: folder,
            canRetain: { self.canRetain(attempt) },
            retain: { [core] id, source in
              _ = try await core.stagePhoto(id: id, path: source.path)
              let path = try await core.artifactPath(id: id, artifact: "source.bin")
              return URL(fileURLWithPath: path)
            })
          if let retained {
            await ingestFile(retained, attempt: attempt, navigate: false, alreadyRetained: true)
          }
        } catch {
          if canRetain(attempt) { self.error = userMessage(error) }
        }
      }
      if let warning = pending.warning, admission.accepts(ticket), generation == documentGeneration
      {
        self.error = warning
      }
    } catch {
      if admission.accepts(ticket), generation == documentGeneration {
        self.error = userMessage(error)
      }
    }
  }
  func recoverInbox() async {
    guard let ticket = admission.ticket(), let lease = admission.begin(ticket) else { return }
    defer { admission.end(lease) }
    let generation = documentGeneration
    do {
      // A complete share receipt is authoritative over a legacy inbox copy
      // that may have been interrupted before its final bytes reached disk.
      await recoverShares()
      guard admission.accepts(ticket), generation == documentGeneration else { return }
      let urls = try await Task.detached {
        let folder = try AppStorage.prepare().appendingPathComponent("inbox")
        return try IntakeInbox.pending(in: folder)
      }.value
      for url in urls {
        guard admission.accepts(ticket), generation == documentGeneration else { return }
        let name = url.deletingPathExtension().lastPathComponent
        let id = UUID(uuidString: name) == nil ? UUID().uuidString : name
        guard !attempts.contains(id), let attempt = register(id, ticket: ticket),
          let owner = attempts.begin(attempt)
        else { continue }
        attempts.finishInput(attempt)
        defer { release(owner) }
        do {
          _ = try await core.stagePhoto(id: id, path: url.path)
          try FileManager.default.removeItem(at: url)
        } catch {
          if admission.accepts(ticket), generation == documentGeneration {
            self.error = userMessage(error)
          }
        }
      }
      guard admission.accepts(ticket), generation == documentGeneration else { return }
      let history = try await core.history()
      for intake in history.intakes where intake.status == "document" {
        guard admission.accepts(ticket), generation == documentGeneration else { return }
        guard !attempts.contains(intake.id), let attempt = register(intake.id, ticket: ticket),
          let owner = attempts.begin(attempt)
        else { continue }
        attempts.finishInput(attempt)
        defer { release(owner) }
        let pages = try await core.pageGroup(id: intake.id)
        guard canProcess(attempt), generation == documentGeneration else { return }
        if pages.contains(where: { page in
          !history.scans.contains(where: { $0.id == page && $0.retained })
        }) {
          let path = try await core.artifactPath(id: intake.id, artifact: "source.bin")
          guard canProcess(attempt), generation == documentGeneration else { return }
          await ingestFile(URL(fileURLWithPath: path), attempt: attempt, navigate: false)
        }
      }
    } catch {
      if admission.accepts(ticket), generation == documentGeneration {
        self.error = userMessage(error)
      }
    }
  }
  func cancel() {
    documentGeneration = UUID()
    if let currentID { LocalDiagnostics.shared.record(.intake, .cancelled, correlation: currentID) }
    attempts.revokeAll()
    for job in recognitionJobs.values { job.cancel() }
    for task in tasks.values { task.cancel() }
    awaitingBytes.removeAll()
    updateRunning()
  }
}
