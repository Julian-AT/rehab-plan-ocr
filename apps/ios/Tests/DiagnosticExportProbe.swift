import Foundation

private actor ExportSignal {
  private var sent = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    guard !sent else { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func send() {
    sent = true
    let continuations = waiting
    waiting = []
    for continuation in continuations { continuation.resume() }
  }
}

@main struct DiagnosticExportProbe {
  @MainActor static func main() async throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let protected = root.appendingPathComponent("unrelated.json")
    try Data("untouched".utf8).write(to: protected)
    let store = AppTemporaryStore(temporary: root)
    try await store.prepare()
    let export = TemporaryDiagnosticExport(store: store)
    let content = Data(#"{"redacted":true,"events":[]}"#.utf8)

    try await export.write { content }
    let first = export.url!
    let firstBytes = try Data(contentsOf: first)
    precondition(firstBytes == content)
    precondition(first.path.contains("/reha-disposable-v1/diagnostic-"))
    let mode = try files.attributesOfItem(atPath: first.deletingLastPathComponent().path)
    precondition((mode[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    try await export.write { content }
    let second = export.url!
    precondition(first != second && !files.fileExists(atPath: first.path))
    await export.close()
    precondition(export.url == nil && !files.fileExists(atPath: second.path))

    // A suspended producer deliberately ignores cancellation. Navigation away
    // must wait for its return and reject the result before any file is written.
    try await delayedProducer(export: export, store: store, erase: false)
    precondition(export.url == nil)
    precondition(diagnosticFiles(root).isEmpty)

    // Global erasure closes admission before draining owners. The same delayed
    // producer cannot recreate a file after erasure or after admission resumes.
    try await delayedProducer(export: export, store: store, erase: true)
    await store.resume()
    precondition(export.url == nil)
    precondition(diagnosticFiles(root).isEmpty)

    enum Failure: Error { case producer }
    do {
      try await export.write { throw Failure.producer }
      fatalError("Producer failure was swallowed")
    } catch Failure.producer {}
    precondition(export.url == nil)
    precondition(diagnosticFiles(root).isEmpty)

    try await export.write { content }
    let erased = export.url!
    try await store.erase()
    precondition(export.url == nil && !files.fileExists(atPath: erased.path))
    let protectedBytes = try Data(contentsOf: protected)
    precondition(protectedBytes == Data("untouched".utf8))
    print(
      "Diagnostic export: replacement, close drain, erasure drain, failure and protected files passed"
    )
  }

  @MainActor private static func delayedProducer(
    export: TemporaryDiagnosticExport, store: AppTemporaryStore, erase: Bool
  ) async throws {
    let entered = ExportSignal()
    let cancelled = ExportSignal()
    let release = ExportSignal()
    let writing = Task { @MainActor in
      try await export.write {
        await withTaskCancellationHandler {
          await entered.send()
          await release.wait()
          return Data(#"{"redacted":true,"events":[{"code":"late"}]}"#.utf8)
        } onCancel: {
          Task { await cancelled.send() }
        }
      }
    }
    await entered.wait()
    let closing = Task { @MainActor in
      if erase { try await store.erase() } else { await export.close() }
    }
    await cancelled.wait()
    if erase {
      do {
        _ = try await store.acquire(.diagnostic) {}
        fatalError("Diagnostic admission remained open during erasure")
      } catch is CancellationError {}
    }
    await release.send()
    do {
      try await writing.value
      fatalError("Closed diagnostic producer published its result")
    } catch is CancellationError {}
    try await closing.value
  }

  private static func diagnosticFiles(_ root: URL) -> [URL] {
    let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
    return paths.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasPrefix("Diagnose-") }
  }
}
