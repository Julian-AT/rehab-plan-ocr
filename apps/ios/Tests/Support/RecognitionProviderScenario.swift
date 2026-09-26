#if DEBUG && targetEnvironment(simulator)
  import CryptoKit
  import Foundation
  import RehaCore

  /// Only photo decoding and native field rereading can cross this host boundary.
  private final class RecognitionProbeHost: AppleHost, @unchecked Sendable {
    private let native = NativeBridge()
    private let lock = NSLock()
    private var rejected = 0
    private var rereads = 0
    var counts: [String: Int] {
      lock.lock()
      defer { lock.unlock() }
      return ["rejected_calendar_calls": rejected, "native_reread_calls": rereads]
    }
    private func denied() -> AppError {
      lock.lock()
      rejected += 1
      lock.unlock()
      return AppError.Validation(message: "Calendar access is forbidden in the recognition probe")
    }
    func calendarEventCall(command: String, arguments: String) throws -> String {
      guard command == "recognize" else { throw denied() }
      lock.lock()
      rereads += 1
      lock.unlock()
      return try native.calendarEventCall(command: command, arguments: arguments)
    }
    func decodePhoto(bytes: Data) throws -> Data { try native.decodePhoto(bytes: bytes) }
    func snapshot(records: [ImportRecord]) throws -> LiveCalendar { throw denied() }
    func calendarStatus() throws -> CalendarPlatformStatus { throw denied() }
    func queryCalendar(request: CalendarReadQuery) throws -> CalendarReadResult { throw denied() }
    func resolveCalendarEvent(reference: CalendarReadReference) throws -> CalendarReadEvent? {
      throw denied()
    }
    func eventCalendars() throws -> [EventCalendarDestination] { throw denied() }
    func mutateEvent(request: EventMutationRequest) throws -> EventMutationResult { throw denied() }
    func apply(operation: CalendarOperation, recoveryOnly: Bool) throws -> CalendarResult {
      throw denied()
    }
    func syncAgenda(request: AgendaSyncRequest) throws -> AgendaSyncResult { throw denied() }
    func inspectCalendarLinks(records: [AgendaOwnedRecord]) throws -> CalendarLinkInspection {
      throw denied()
    }
    func forgetCalendar() throws { throw denied() }
    func overlaps(events: [String: EventValues], exclude: [String]) throws -> [CalendarOverlap] {
      throw denied()
    }
  }

  @MainActor enum RecognitionProviderScenario {
    private static var started = false
    static func runIfRequested() async -> Bool {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--recognition-provider-probe"),
        arguments.indices.contains(index + 1), let runID = UUID(uuidString: arguments[index + 1])
      else { return false }
      guard !started else { return true }
      started = true
      let folder = URL.documentsDirectory.appendingPathComponent("recognition-probe")
      let output = folder.appendingPathComponent("result.json")
      let host = RecognitionProbeHost()
      var report: [String: Any] = [
        "run_id": runID.uuidString.lowercased(), "qualified": false,
        "calendar_operations": 0, "stage": "started",
      ]
      func save() throws {
        report["host_calls"] = host.counts
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
          .write(to: output, options: .atomic)
      }
      do {
        let input = try Data(contentsOf: folder.appendingPathComponent("input.json"))
        guard input.count <= 4096,
          let request = try JSONSerialization.jsonObject(with: input) as? [String: String],
          request["run_id"] == runID.uuidString.lowercased(),
          ["baseline", "frozen"].contains(request["variant"] ?? "")
        else { throw InterpretationError.invalidRequest }
        let models = folder.appendingPathComponent("models")
        let source = folder.appendingPathComponent("input.png")
        let hashes = try await Task.detached {
          func sha(_ file: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
              hash.update(data: bytes)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
          }
          return (try sha(models.appendingPathComponent("manifest.json")), try sha(source))
        }.value
        guard hashes.0 == request["model_manifest_sha256"], hashes.1 == request["source_sha256"]
        else { throw InterpretationError.invalidRequest }
        report["variant"] = request["variant"]
        report["model_manifest_sha256"] = hashes.0
        report["source_sha256"] = hashes.1
        let root = folder.appendingPathComponent("store-\(runID.uuidString.lowercased())")
        guard !FileManager.default.fileExists(atPath: root.path) else {
          throw InterpretationError.invalidRequest
        }
        let core = try await openApplication(root: root.path, models: models.path, host: host)
        var cases: [[String: Any]] = []
        for index in 0..<2 {
          report["stage"] = "recognizing"
          report["case_index"] = index
          try save()
          let id = UUID().uuidString
          let start = ContinuousClock.now
          let job = try core.registerJob(id: id)
          defer { job.close() }
          let outcome = try await core.importPhoto(
            request: PhotoRequest(
              id: id, path: source.path, timezone: "Europe/Vienna", quarterTurns: 0,
              mirrored: false, pageCorners: [], force: true), job: job)
          let elapsed = start.duration(to: .now).components
          guard !outcome.duplicate, outcome.scan.document.id == id else {
            throw InterpretationError.invalidRequest
          }
          // Reread the persisted result through the ordinary review/trace APIs.
          let retained = try await core.loadScan(id: id)
          let trace = try await core.recognitionTrace(id: id)
          let name = "trace-\(index).json"
          try Data(trace.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
          cases.append([
            "index": index, "document_id": id, "duplicate": outcome.duplicate,
            "appointments": retained.appointments.count, "trace": name,
            "import_seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
          ])
          report["cases"] = cases
          try save()
        }
        guard host.counts["rejected_calendar_calls"] == 0 else {
          throw InterpretationError.invalidRequest
        }
        report["stage"] = "passed"
        try save()
      } catch {
        report["stage"] = "failed"
        report["error"] = String(describing: error)
        try? save()
      }
      return true
    }
  }
#endif
