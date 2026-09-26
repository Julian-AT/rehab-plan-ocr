import Foundation

@main struct IntakeInboxProbe {
  @MainActor static func main() async throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let inbox = root.appendingPathComponent("inbox")
    let source = root.appendingPathComponent("synthetic.pdf")
    let bytes = Data("%PDF-complete synthetic original".utf8)
    try bytes.write(to: source)
    let destination = inbox.appendingPathComponent(UUID().uuidString)

    // Interrupt after writing a prefix. The recoverable final name must never
    // be visible, even during the callback, and failure cannot acknowledge it.
    do {
      _ = try IntakeInbox.stage(source, at: destination) { _, output in
        try output.write(contentsOf: bytes.prefix(8))
        precondition(!files.fileExists(atPath: destination.path))
        let pending = try IntakeInbox.pending(in: inbox)
        precondition(pending.isEmpty)
        throw CocoaError(.fileWriteUnknown)
      }
      fatalError("Interrupted input was published")
    } catch CocoaError.fileWriteUnknown {}
    precondition(!files.fileExists(atPath: destination.path))

    _ = try IntakeInbox.stage(source, at: destination)
    let complete = try Data(contentsOf: destination)
    precondition(complete == bytes)
    _ = try IntakeInbox.stage(source, at: destination)

    // A failed replacement and a complete but different input both leave the
    // previously acknowledged file intact. No silent ID reuse is permitted.
    do {
      _ = try IntakeInbox.stage(source, at: destination) { _, output in
        try output.write(contentsOf: Data("partial".utf8))
        throw CocoaError(.fileWriteUnknown)
      }
      fatalError("Interrupted replacement was accepted")
    } catch CocoaError.fileWriteUnknown {}
    let different = root.appendingPathComponent("different.pdf")
    try Data("different complete original".utf8).write(to: different)
    do {
      _ = try IntakeInbox.stage(different, at: destination)
      fatalError("A different inbox original was overwritten")
    } catch CocoaError.fileWriteFileExists {}
    let preserved = try Data(contentsOf: destination)
    precondition(preserved == bytes)

    // A crash cannot run deferred cleanup. Orphaned hidden workspaces and
    // hidden files must still be absent from the actual recovery enumeration.
    let partial = inbox.appendingPathComponent(".intake-\(UUID().uuidString).partial")
    try files.createDirectory(at: partial, withIntermediateDirectories: false)
    try Data("prefix".utf8).write(to: partial.appendingPathComponent("original"))
    try Data("prefix".utf8).write(to: inbox.appendingPathComponent(".orphan.partial"))
    try files.createSymbolicLink(
      at: inbox.appendingPathComponent("linked-original"), withDestinationURL: source)
    let pending = try IntakeInbox.pending(in: inbox)
    precondition(pending.map(\.lastPathComponent) == [destination.lastPathComponent])

    // Metadata was admitted at one byte, then the source grows. The stream
    // itself must stop at the overflow sentinel and never publish its prefix.
    let growing = root.appendingPathComponent("growing")
    try Data([1]).write(to: growing)
    let oversized = inbox.appendingPathComponent(UUID().uuidString)
    let maximum = UInt64(40 * 1024 * 1024)
    var consumed: UInt64 = 0
    do {
      _ = try IntakeInbox.stage(growing, at: oversized) { input, output in
        let writer = try FileHandle(forWritingTo: growing)
        try writer.truncate(atOffset: maximum + 1)
        try writer.close()
        defer { consumed = (try? input.offset()) ?? 0 }
        try IntakeInbox.copyContents(input, output)
      }
      fatalError("Growing input exceeded the actual copy limit")
    } catch CocoaError.fileReadTooLarge {}
    precondition(consumed == maximum + 1 && !files.fileExists(atPath: oversized.path))
    let boundary = try FileHandle(forWritingTo: growing)
    try boundary.truncate(atOffset: maximum)
    try boundary.close()
    _ = try IntakeInbox.stage(growing, at: oversized)
    let boundarySize = try files.attributesOfItem(atPath: oversized.path)[.size] as? NSNumber
    precondition(boundarySize?.uint64Value == maximum)

    // ScanModel's producer admission stays held around this synchronous copy.
    // Closing intake cannot permit erasure cleanup until the writer drains.
    let admission = IntakeAdmission()
    admission.open()
    let producer = admission.begin(admission.ticket()!)!
    let (entered, checkpoint) = AsyncStream<Void>.makeStream()
    let resume = DispatchSemaphore(value: 0)
    let active = inbox.appendingPathComponent(UUID().uuidString)
    let copying = Task.detached {
      try IntakeInbox.stage(source, at: active) { input, output in
        checkpoint.yield(())
        checkpoint.finish()
        resume.wait()
        try IntakeInbox.copyContents(input, output)
      }
    }
    for await _ in entered { break }
    admission.close()
    precondition(!admission.isDrained && !files.fileExists(atPath: active.path))
    resume.signal()
    _ = try await copying.value
    admission.end(producer)
    precondition(admission.isDrained)
    try files.removeItem(at: inbox)
    precondition(!files.fileExists(atPath: active.path))
    let untouchedSource = try Data(contentsOf: source)
    precondition(untouchedSource == bytes)
    print(
      "Inbox: atomic publication, interrupted copy, preserved replay/conflict, hidden recovery, bounded growth and erasure drain passed"
    )
  }
}
