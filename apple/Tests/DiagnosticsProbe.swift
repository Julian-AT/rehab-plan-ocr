import Foundation
@main struct Probe {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = LocalDiagnostics(directory: { root })
    let session = UUID().uuidString
    for _ in 0..<5010 { journal.record(.ocr, .completed, correlation: session, durationMs: 10) }
    let events = try await journal.snapshot()
    precondition(events.count == 5000)
    let export = String(decoding: try await journal.redactedExport(), as: UTF8.self)
    precondition(!export.contains(session) && !export.contains("time"))
    let future = Date().addingTimeInterval(15 * 86400)
    let reopened = LocalDiagnostics(directory: { root }, clock: { future })
    let expired = try await reopened.snapshot()
    precondition(expired.isEmpty)
    print("Diagnostics: 5000-entry cap, 14-day retention and redacted export passed")
  }
}
