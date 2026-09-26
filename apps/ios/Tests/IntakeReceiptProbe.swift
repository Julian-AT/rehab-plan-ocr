import CryptoKit
import Foundation

@main struct IntakeReceiptProbe {
  static func main() async throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("synthetic.pdf")
    let bytes = Data("%PDF-synthetic recovery original".utf8)
    try bytes.write(to: source)
    let gate = IntakeGate(root: root.appendingPathComponent("group"))
    let generation = try gate.ticket()
    let receipt = try IntakeStaging.stage(source, generation: generation, gate: gate)
    let receipts = gate.root.appendingPathComponent("receipts")
    let published = receipts.appendingPathComponent(receipt.id)
    let partial = receipts.appendingPathComponent(receipt.id + ".partial")
    // Simulate process termination after syncing the original but before publication.
    try files.moveItem(at: published, to: partial)
    let recovered = try IntakeStaging.pending(gate: gate)
    precondition(recovered.receipts.count == 1 && recovered.warning == nil)
    precondition(recovered.receipts[0].0.id == receipt.id)
    let recoveredBytes = try Data(contentsOf: recovered.receipts[0].1)
    precondition(recoveredBytes == bytes)
    precondition(!files.fileExists(atPath: partial.path))
    let replayed = try IntakeStaging.pending(gate: gate)
    precondition(replayed.receipts.count == 1 && replayed.receipts[0].0.id == receipt.id)

    func incomplete(_ content: Data?, metadata: Bool) throws -> URL {
      let id = UUID().uuidString
      let folder = receipts.appendingPathComponent(id + ".partial")
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      if metadata {
        let row = IntakeReceipt(
          id: id, filename: "synthetic.pdf", sha256: receipt.sha256, receivedAt: .now)
        try JSONEncoder().encode(row).write(to: folder.appendingPathComponent("receipt.json"))
      }
      if let content { try content.write(to: folder.appendingPathComponent("original")) }
      return folder
    }
    // Crash points before metadata, before source storage, and during source storage.
    let empty = try incomplete(nil, metadata: false)
    let metadataOnly = try incomplete(nil, metadata: true)
    let corrupt = try incomplete(Data("truncated".utf8), metadata: true)
    let corruptBefore = try Data(contentsOf: corrupt.appendingPathComponent("original"))
    let oversized = try incomplete(Data(), metadata: true)
    let file = try FileHandle(forWritingTo: oversized.appendingPathComponent("original"))
    try file.truncate(atOffset: 41 * 1024 * 1024)
    try file.close()
    let linked = try incomplete(nil, metadata: true)
    try files.createSymbolicLink(
      at: linked.appendingPathComponent("original"), withDestinationURL: source)
    // A publication collision must preserve both originals, even with identical bytes.
    try files.copyItem(at: published, to: partial)
    let pending = try IntakeStaging.pending(gate: gate)
    precondition(pending.receipts.count == 1 && pending.preservedIssues == 6)
    precondition(pending.warning != nil)
    for path in [empty, metadataOnly, corrupt, oversized, linked, partial] {
      precondition(files.fileExists(atPath: path.path))
    }
    let corruptAfter = try Data(contentsOf: corrupt.appendingPathComponent("original"))
    let sourceAfter = try Data(contentsOf: source)
    precondition(corruptAfter == corruptBefore)
    precondition(sourceAfter == bytes)
    let repeated = try IntakeStaging.pending(gate: gate)
    precondition(repeated.receipts.count == 1 && repeated.preservedIssues == 6)

    // Recovery may finish before erasure or be fenced out; it cannot publish afterwards.
    let recovery = Task.detached { try? IntakeStaging.pending(gate: gate) }
    let erasure = Task.detached { try gate.beginErasure() }
    _ = await recovery.value
    try await erasure.value
    let blocked = try IntakeStaging.pending(gate: gate)
    precondition(blocked.receipts.isEmpty && blocked.warning == nil)
    try gate.finishErasure()
    precondition(!files.fileExists(atPath: receipts.path))
    do {
      _ = try IntakeStaging.stage(source, generation: generation, gate: gate)
      fatalError("A pre-erasure transfer was republished")
    } catch IntakeGateError.expired {}
    let fresh = try gate.ticket()
    _ = try IntakeStaging.stage(source, generation: fresh, gate: gate)
    let reopened = try IntakeStaging.pending(gate: gate)
    precondition(reopened.receipts.count == 1 && reopened.warning == nil)
    print(
      "Intake receipts: partial recovery, replay, preserved corrupt/oversized originals, publication collision and erasure fencing passed"
    )
  }
}
