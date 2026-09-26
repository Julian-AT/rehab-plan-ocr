import Foundation

private actor Signal {
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

@main struct TemporaryPrivacyProbe {
  @MainActor static func main() async throws {
    let files = FileManager.default
    let fixture = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let temporary = fixture.appendingPathComponent("tmp")
    let protected = fixture.appendingPathComponent("original.txt")
    try files.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: fixture) }
    try Data("protected original".utf8).write(to: protected)
    let legacy = temporary.appendingPathComponent("Termine-\(UUID().uuidString).ics")
    try Data("private synthetic appointment".utf8).write(to: legacy)
    let keep = ["Termine-original.ics", "Termine-\(UUID().uuidString).ics.backup", "notes.txt"]
    for name in keep { try Data(name.utf8).write(to: temporary.appendingPathComponent(name)) }
    let oldTraces = temporary.appendingPathComponent("RecognitionTrace")
    let oldTrace = oldTraces.appendingPathComponent(UUID().uuidString)
    let unrelated = oldTraces.appendingPathComponent("user-reference")
    try files.createDirectory(at: oldTrace, withIntermediateDirectories: true)
    try files.createDirectory(at: unrelated, withIntermediateDirectories: true)
    try Data("private synthetic image".utf8).write(
      to: oldTrace.appendingPathComponent("Eingang.png"))
    let link = oldTraces.appendingPathComponent(UUID().uuidString)
    try files.createSymbolicLink(at: link, withDestinationURL: protected)
    let store = AppTemporaryStore(temporary: temporary)
    try await store.prepare()
    precondition(!files.fileExists(atPath: legacy.path))
    precondition(!files.fileExists(atPath: oldTrace.path))
    precondition(!files.fileExists(atPath: link.path))
    precondition(files.fileExists(atPath: unrelated.path))
    for name in keep {
      precondition(files.fileExists(atPath: temporary.appendingPathComponent(name).path))
    }
    let originalBefore = try String(contentsOf: protected, encoding: .utf8)
    precondition(originalBefore == "protected original")

    let export = TemporaryCalendarExport(store: store)
    try await export.write { "BEGIN:VCALENDAR\nSUMMARY:synthetic first\nEND:VCALENDAR" }
    let first = export.url!
    precondition(files.fileExists(atPath: first.path))
    try await export.write { "BEGIN:VCALENDAR\nSUMMARY:synthetic second\nEND:VCALENDAR" }
    let second = export.url!
    precondition(first != second && !files.fileExists(atPath: first.path))
    await export.close()
    precondition(export.url == nil && !files.fileExists(atPath: second.path))

    // An uncooperative content generator can finish after cancellation. Erasure
    // waits for it, and the cancelled export must never publish its late result.
    let entered = Signal()
    let cancelled = Signal()
    let continueGeneration = Signal()
    let writing = Task { @MainActor in
      try await export.write {
        await withTaskCancellationHandler {
          await entered.send()
          await continueGeneration.wait()
          return "SUMMARY:late private appointment"
        } onCancel: {
          Task { await cancelled.send() }
        }
      }
    }
    await entered.wait()
    let erasing = Task { try await store.erase() }
    await cancelled.wait()
    do {
      _ = try await store.acquire(.calendar) {}
      fatalError("Temporary admission remained open during erasure")
    } catch is CancellationError {}
    await continueGeneration.send()
    do {
      try await writing.value
      fatalError("Cancelled export published a result")
    } catch is CancellationError {}
    try await erasing.value
    precondition(export.url == nil)
    await store.resume()

    // Simulate a native writer that keeps working until its own cancellation
    // handshake. Its directory remains valid until drain; erasure removes even
    // the last file written during that handshake, before reopening admission.
    let writerFinished = Signal()
    let stopRequested = Signal()
    let lease = try await store.acquire(.recognition) {
      await stopRequested.send()
      await writerFinished.wait()
    }
    let workspace = try await store.create(lease)
    let draining = Task { try await store.erase() }
    await stopRequested.wait()
    precondition(files.fileExists(atPath: workspace.path))
    try Data("last native write".utf8).write(to: workspace.appendingPathComponent("last.png"))
    await writerFinished.send()
    try await draining.value
    precondition(!files.fileExists(atPath: workspace.path))
    await store.resume()
    do {
      _ = try await store.create(lease)
      fatalError("Old workspace lease revived after erasure")
    } catch is CancellationError {}
    try await export.write { "SUMMARY:after erasure" }
    let orphan = export.url!
    precondition(files.fileExists(atPath: orphan.path))

    // A new process has no retained owners. Startup removes abandoned exports
    // and trace workspaces without depending on view disappearance callbacks.
    let restarted = AppTemporaryStore(temporary: temporary)
    try await restarted.prepare()
    precondition(!files.fileExists(atPath: orphan.path))
    let originalAfter = try String(contentsOf: protected, encoding: .utf8)
    precondition(originalAfter == originalBefore)
    for name in keep {
      precondition(files.fileExists(atPath: temporary.appendingPathComponent(name).path))
    }
    print(
      "Temporary privacy: exact legacy cleanup, export replacement/dismissal, writer drain, stale leases, restart and protected originals passed"
    )
  }
}
