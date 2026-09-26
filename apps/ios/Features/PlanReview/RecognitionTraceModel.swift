import Foundation
import RehaCore

/// A separate temporary store runs the production recognition pipeline without
/// admitting debug photos to the user's archive or calendar write paths.
@MainActor @Observable final class RecognitionTraceModel {
  private(set) var trace: RecognitionTrace?
  private(set) var busy = false
  private(set) var progress = ""
  private(set) var error: String?
  private(set) var original: URL?
  private(set) var page: URL?
  private(set) var core: NativeApplication?
  private var workspace: AppTemporaryStore.Lease?
  private var disposing = false
  private var task: Task<Void, Never>?
  private var recognitionJob: RecognitionJob?
  private var closed = false
  private var cancelRequested = false

  func start(_ source: URL, timezone: String) {
    guard !busy, !disposing else { return }
    busy = true
    closed = false
    cancelRequested = false
    error = nil
    trace = nil
    original = nil
    page = nil
    progress = "Bild vorbereiten"
    task = Task {
      await dispose()
      do {
        let lease = try await AppTemporaryStore.shared.acquire(.recognition) { [weak self] in
          await self?.close()
        }
        workspace = lease
        if closed || cancelRequested {
          await dispose()
          busy = false
          task = nil
          return
        }
        let root = try await AppTemporaryStore.shared.create(lease)
        let work = try await Task.detached(priority: .userInitiated) {
          let manager = FileManager.default
          let access = source.startAccessingSecurityScopedResource()
          defer { if access { source.stopAccessingSecurityScopedResource() } }
          do {
            let attributes = try manager.attributesOfItem(atPath: source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0, size.int64Value <= 40 * 1024 * 1024
            else {
              throw AppError.Validation(message: "Bitte ein Bild bis 40 MB auswählen.")
            }
            let input = root.appendingPathComponent("Eingang").appendingPathExtension(
              source.pathExtension)
            try manager.copyItem(at: source, to: input)
            try manager.setAttributes(
              [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
              ofItemAtPath: input.path)
            return (root, input)
          } catch {
            try? manager.removeItem(at: root)
            throw error
          }
        }.value
        if closed || cancelRequested {
          await dispose()
          busy = false
          task = nil
          return
        }
        let resources = Bundle.main.resourceURL!
        let bundled = resources.appendingPathComponent("models")
        let models =
          FileManager.default.fileExists(
            atPath: bundled.appendingPathComponent("manifest.json").path)
          ? bundled : resources.appendingPathComponent("small")
        let application = try await openApplication(
          root: work.0.path, models: models.path, host: RecognitionTraceHost())
        core = application
        let id = UUID().uuidString
        if closed || cancelRequested {
          await dispose()
          busy = false
          task = nil
          return
        }
        let job = try application.registerJob(id: id)
        recognitionJob = job
        defer {
          job.close()
          recognitionJob = nil
        }
        progress = "Bild vorbereiten"
        let poll = Task {
          while !Task.isCancelled {
            if let state = application.jobProgress(id: id) { progress = state.stage }
            if original == nil,
              let path = try? await application.artifactPath(id: id, artifact: "original.png")
            {
              original = URL(fileURLWithPath: path)
            }
            if page == nil,
              let path = try? await application.artifactPath(id: id, artifact: "page.png")
            {
              page = URL(fileURLWithPath: path)
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
          }
        }
        defer { poll.cancel() }
        do {
          _ = try await withTaskCancellationHandler {
            try await application.importTracePhoto(
              request: PhotoRequest(
                id: id, path: work.1.path, timezone: timezone, quarterTurns: 0,
                mirrored: false, pageCorners: [], force: true), job: job)
          } onCancel: {
            job.cancel()
          }
        } catch { self.error = userMessage(error) }
        if let json = try? await application.recognitionTrace(id: id) {
          trace = try RecognitionTrace.decode(json)
        }
        if let path = try? await application.artifactPath(id: id, artifact: "original.png") {
          original = URL(fileURLWithPath: path)
        }
        if let path = try? await application.artifactPath(id: id, artifact: "page.png") {
          page = URL(fileURLWithPath: path)
        }
        progress = trace == nil ? "Keine auswertbaren Schritte" : "Tracing abgeschlossen"
      } catch { self.error = userMessage(error) }
      busy = false
      if closed { await dispose() }
      task = nil
    }
  }
  func cancel() {
    cancelRequested = true
    recognitionJob?.cancel()
    progress = "Erkennung wird beendet …"
  }
  func close() async {
    closed = true
    trace = nil
    original = nil
    page = nil
    cancel()
    let pending = task
    await pending?.value
    await dispose()
  }
  private func dispose() async {
    disposing = true
    defer { disposing = false }
    // Rust may still be releasing a cancelled inference worker. Never delete
    // its workspace while it is writing a partial result.
    while core?.recognitionBusy() == true {
      try? await Task.sleep(for: .milliseconds(100))
    }
    core = nil
    recognitionJob?.close()
    recognitionJob = nil
    trace = nil
    original = nil
    page = nil
    error = nil
    if let workspace {
      try? await AppTemporaryStore.shared.release(workspace)
      self.workspace = nil
    }
  }
}

/// Recognition can decode an image and ask Vision to reread. Calendar effects
/// are deliberately unavailable in this disposable workspace.
private final class RecognitionTraceHost: AppleHost, Sendable {
  private let bridge = NativeBridge()
  private var forbidden: AppError { .Validation(message: "Tracing verändert keine Kalenderdaten.") }
  func decodePhoto(bytes: Data) throws -> Data { try bridge.decodePhoto(bytes: bytes) }
  func calendarEventCall(command: String, arguments: String) throws -> String {
    guard command == "recognize" else { throw forbidden }
    return try bridge.calendarEventCall(command: command, arguments: arguments)
  }
  func snapshot(records: [ImportRecord]) throws -> LiveCalendar { throw forbidden }
  func queryCalendar(request: CalendarReadQuery) throws -> CalendarReadResult { throw forbidden }
  func resolveCalendarEvent(reference: CalendarReadReference) throws -> CalendarReadEvent? {
    throw forbidden
  }
  func eventCalendars() throws -> [EventCalendarDestination] { throw forbidden }
  func mutateEvent(request: EventMutationRequest) throws -> EventMutationResult { throw forbidden }
  func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
    throw forbidden
  }
  func syncAgenda(records: [ImportRecord], preferences: Preferences) throws { throw forbidden }
  func forgetCalendar() throws { throw forbidden }
  func overlaps(events: [String: EventValues], exclude: [String]) throws -> [CalendarOverlap] {
    throw forbidden
  }
}
