import Foundation

public enum DiagnosticStep: String, Codable, Sendable {
  case intake, preparation, ocr, mapping, interpretation, refinement, confirmation
  case calendarRead, calendarWrite, reminderSettings, reminderSelection, reminderPlan,
    reminderConfirmed
  case speechSession, speechRecognition, tools, synthesis, playback, interruption
}
public enum DiagnosticOutcome: String, Codable, Sendable {
  case started, completed, failed, cancelled
}
public struct DiagnosticEvent: Codable, Sendable, Identifiable {
  public let id: String
  public let correlation: String
  public let time: Date
  public let step: DiagnosticStep
  public let outcome: DiagnosticOutcome
  public let durationMs: Int?
  public let count: Int?
  /// A stable technical code; arbitrary errors, text and paths are never accepted.
  public var code: String { "\(step.rawValue).\(outcome.rawValue)" }
}

/// Independent of original retention and recovery journals. Only enums, random
/// identifiers, time, duration and counts can enter this local technical log.
public final class LocalDiagnostics: @unchecked Sendable {
  #if os(iOS)
    public static let shared = LocalDiagnostics(directory: { try AppStorage.prepare() })
  #endif
  private let queue = DispatchQueue(label: "at.rehakalender.diagnostics", qos: .utility)
  private let directory: @Sendable () throws -> URL
  private var events: [DiagnosticEvent] = []
  private var loaded = false
  private var flush: DispatchWorkItem?
  private let clock: @Sendable () -> Date
  public init(
    directory: @escaping @Sendable () throws -> URL,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.directory = directory
    self.clock = clock
  }
  private func path() throws -> URL {
    try directory().appendingPathComponent("diagnostics-v1.json")
  }
  private func load() throws {
    guard !loaded else { return }
    let url = try path()
    if FileManager.default.fileExists(atPath: url.path) {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size < 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
      events = try JSONDecoder().decode([DiagnosticEvent].self, from: Data(contentsOf: url))
    }
    loaded = true
    trim()
  }
  private func trim() {
    let cutoff = clock().addingTimeInterval(-14 * 86400)
    events.removeAll { $0.time < cutoff }
    if events.count > 5000 { events.removeFirst(events.count - 5000) }
  }
  public func record(
    _ step: DiagnosticStep, _ outcome: DiagnosticOutcome, correlation: String = UUID().uuidString,
    durationMs: Int? = nil, count: Int? = nil
  ) {
    let event = DiagnosticEvent(
      id: UUID().uuidString,
      correlation: UUID(uuidString: correlation)?.uuidString ?? UUID().uuidString,
      time: clock(), step: step, outcome: outcome, durationMs: durationMs.map { max(0, $0) },
      count: count.map { max(0, $0) })
    queue.async {
      do {
        try self.load()
        self.events.append(event)
        self.trim()
        if self.flush == nil {
          let flush = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flush = nil
            // A later read reports storage errors; logging never changes a business result.
            try? self.persist()
          }
          self.flush = flush
          self.queue.asyncAfter(deadline: .now() + 0.2, execute: flush)
        }
      } catch {
        // The read/export path surfaces inaccessible diagnostic storage.
      }
    }
  }
  private func persist() throws {
    trim()
    let url = try path()
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    #if os(iOS)
      try JSONEncoder().encode(events).write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try JSONEncoder().encode(events).write(to: url, options: .atomic)
    #endif
  }
  public func snapshot() async throws -> [DiagnosticEvent] {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          try self.load()
          try self.persist()
          continuation.resume(returning: self.events.reversed())
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  public func redactedExport() async throws -> Data {
    let events = try await snapshot()
    var aliases: [String: String] = [:]
    let rows: [[String: Any]] = events.map { event in
      let alias = aliases[event.correlation] ?? "Vorgang \(aliases.count + 1)"
      aliases[event.correlation] = alias
      return [
        "correlation": alias, "step": event.step.rawValue, "outcome": event.outcome.rawValue,
        "code": event.code, "duration_ms": event.durationMs as Any? ?? NSNull(),
        "count": event.count as Any? ?? NSNull(),
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: ["schema": 1, "redacted": true, "events": rows],
      options: [.prettyPrinted, .sortedKeys])
  }
  public func erase() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          self.flush?.cancel()
          self.flush = nil
          self.events = []
          self.loaded = true
          try self.persist()
          continuation.resume()
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
