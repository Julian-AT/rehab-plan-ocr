import Foundation

@main struct IntakeErasureProbe {
  @MainActor static func main() async throws {
    let admission = IntakeAdmission()
    precondition(admission.ticket() == nil)
    admission.open()
    let oldCamera = admission.ticket()!
    let oldPhoto = admission.ticket()!
    let lease = admission.begin(oldPhoto)!
    admission.close()
    precondition(!admission.isDrained && !admission.accepts(oldCamera))
    precondition(admission.begin(oldPhoto) == nil)
    admission.end(lease)
    precondition(admission.isDrained)
    admission.open()
    precondition(!admission.accepts(oldCamera) && !admission.accepts(oldPhoto))
    precondition(admission.accepts(admission.ticket()))

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = IntakeGate(root: root)
    let delayedShare = try gate.ticket()
    let receipts = root.appendingPathComponent("receipts")
    let writerEntered = DispatchSemaphore(value: 0)
    let writerRelease = DispatchSemaphore(value: 0)
    let writer = Task.detached {
      try gate.write(generation: delayedShare) {
        writerEntered.signal()
        writerRelease.wait()
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        try Data("synthetic receipt".utf8).write(to: receipts.appendingPathComponent("old"))
      }
    }
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        writerEntered.wait()
        continuation.resume()
      }
    }
    // Erasure and an admitted writer use the same stable advisory lock.
    let eraser = Task.detached { try gate.beginErasure() }
    writerRelease.signal()
    try await writer.value
    try await eraser.value
    let blocked = try gate.snapshot()
    precondition(blocked.erasing)
    do {
      _ = try gate.ticket()
      fatalError("Admission reopened during erasure")
    } catch IntakeGateError.erasing {}
    // Reopening cannot revive callbacks from the previous share session.
    try gate.finishErasure()
    do {
      try IntakeGate(root: root).write(generation: delayedShare) {
        try Data().write(to: receipts.appendingPathComponent("late"))
      }
      fatalError("Old share callback was admitted")
    } catch IntakeGateError.expired {}
    precondition(!FileManager.default.fileExists(atPath: receipts.path))
    let fresh = try IntakeGate(root: root).ticket()
    try gate.write(generation: fresh) {
      try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
      try Data().write(to: receipts.appendingPathComponent("fresh"))
    }
    precondition(
      FileManager.default.fileExists(atPath: receipts.appendingPathComponent("fresh").path))
    try gate.beginErasure()
    let restarted = IntakeGate(root: root)
    let recovered = try restarted.snapshot()
    precondition(recovered.erasing)
    try restarted.finishErasure()
    print(
      "Intake erasure: closed admission, producer drain, delayed callbacks, serialized receipt writes, restart recovery and fresh intake passed"
    )
  }
}
