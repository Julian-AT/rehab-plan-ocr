import Foundation
import os

@MainActor private final class Provider {
  let progress = Progress(totalUnitCount: 1)
  var callback: (@Sendable (URL?, Error?) -> Void)?
  func start(_ callback: @escaping @Sendable (URL?, Error?) -> Void) -> Progress {
    self.callback = callback
    return progress
  }
}

@main @MainActor struct IntakeProviderProbe {
  private static func ready(_ provider: Provider) async {
    for _ in 0..<10_000 {
      if provider.callback != nil { return }
      await Task.yield()
    }
    preconditionFailure("Provider was not started")
  }
  static func expectCancelled(_ task: Task<IntakeReceipt, Error>) async throws {
    do {
      _ = try await task.value
      preconditionFailure("Cancelled transfer returned a receipt")
    } catch is CancellationError {}
  }
  private static func publicationRace(_ root: URL) async throws {
    let permit = IntakeWritePermit(deadline: .now.advanced(by: .seconds(30)))
    let entered = AsyncStream<Void>.makeStream()
    let published = AsyncStream<Result<Void, Error>>.makeStream()
    let revoked = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let destination = root.appendingPathComponent("publication-won")
    DispatchQueue.global().async {
      let result = Result {
        try permit.publish {
          entered.continuation.yield()
          entered.continuation.finish()
          precondition(release.wait(timeout: .now() + 5) == .success)
          try Data("complete".utf8).write(to: destination, options: .atomic)
        }
      }
      published.continuation.yield(result)
      published.continuation.finish()
    }
    for await _ in entered.stream {}
    DispatchQueue.global().async {
      permit.revoke()
      revoked.continuation.yield()
      revoked.continuation.finish()
    }
    release.signal()
    for await result in published.stream { try result.get() }
    for await _ in revoked.stream {}
    precondition(FileManager.default.fileExists(atPath: destination.path))
    precondition(!permit.discardsUnpublishedFiles, "Late cancellation must preserve publication")
    let cancelled = IntakeWritePermit(deadline: .now.advanced(by: .seconds(30)))
    cancelled.revoke()
    do {
      try cancelled.publish { preconditionFailure("Revoked request entered publication") }
      preconditionFailure("Revoked request was accepted")
    } catch is CancellationError {}
  }
  static func main() async throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("synthetic.pdf")
    let bytes = Data("%PDF-synthetic provider transfer".utf8)
    try bytes.write(to: source)
    let gate = IntakeGate(root: root.appendingPathComponent("group"))
    let generation = try gate.ticket()
    try await publicationRace(root)
    let attempts = OSAllocatedUnfairLock(initialState: 0)
    let stage: @Sendable (URL, IntakeWritePermit) throws -> IntakeReceipt = { url, permit in
      attempts.withLock { $0 += 1 }
      return try IntakeStaging.stage(url, generation: generation, gate: gate, permit: permit)
    }

    // A provider that never calls back cannot hold the UI's continuation forever.
    let silent = Provider()
    let releaseCancellation = DispatchSemaphore(value: 0)
    silent.progress.cancellationHandler = { _ = releaseCancellation.wait(timeout: .now() + 5) }
    do {
      _ = try await IntakeProviderRequest.receive(timeout: 0.02, start: silent.start, stage: stage)
      preconditionFailure("Silent provider did not time out")
    } catch IntakeProviderError.timedOut {}
    releaseCancellation.signal()
    silent.callback?(source, nil)
    silent.callback?(source, nil)
    precondition(attempts.withLock { $0 } == 0, "Late callback touched its file")

    let cancelled = Provider()
    let cancelledTask = Task {
      try await IntakeProviderRequest.receive(start: cancelled.start, stage: stage)
    }
    await ready(cancelled)
    cancelledTask.cancel()
    try await expectCancelled(cancelledTask)
    cancelled.callback?(source, nil)
    precondition(attempts.withLock { $0 } == 0)
    let beforeStart = Provider()
    let early = Task {
      try await IntakeProviderRequest.receive(start: beforeStart.start, stage: stage)
    }
    early.cancel()
    try await expectCancelled(early)
    precondition(beforeStart.callback == nil)

    // The callback is allowed to be synchronous, reentrant, or repeated.
    let immediate = Provider()
    let published = try await IntakeProviderRequest.receive(
      start: { callback in
        callback(source, nil)
        callback(source, nil)
        return immediate.progress
      }, stage: stage)
    precondition(attempts.withLock { $0 } == 1 && !immediate.progress.isCancelled)
    let kept = try IntakeStaging.pending(gate: gate)
    precondition(kept.receipts.map { $0.0.id } == [published.id])

    // Caller cancellation completes even while a callback still owns its URL.
    // Once the held stage resumes it must observe revocation before any write.
    let copying = Provider()
    let entered = AsyncStream<Void>.makeStream()
    let ended = AsyncStream<Void>.makeStream()
    let releaseCopy = DispatchSemaphore(value: 0)
    let copyTask = Task {
      try await IntakeProviderRequest.receive(
        start: copying.start,
        stage: { url, permit in
          entered.continuation.yield()
          entered.continuation.finish()
          defer {
            ended.continuation.yield()
            ended.continuation.finish()
          }
          precondition(releaseCopy.wait(timeout: .now() + 5) == .success)
          return try stage(url, permit)
        })
    }
    await ready(copying)
    let callback = copying.callback!
    DispatchQueue.global().async { callback(source, nil) }
    for await _ in entered.stream {}
    copyTask.cancel()
    try await expectCancelled(copyTask)
    releaseCopy.signal()
    for await _ in ended.stream {}
    let afterCancel = try IntakeStaging.pending(gate: gate)
    precondition(afterCancel.receipts.map { $0.0.id } == [published.id])

    // Expiry after the actual original copy removes only this request's partial.
    let receipts = gate.root.appendingPathComponent("receipts")
    let foreign = receipts.appendingPathComponent(UUID().uuidString + ".partial")
    try files.createDirectory(at: foreign, withIntermediateDirectories: true)
    try Data("preserved interruption".utf8).write(to: foreign.appendingPathComponent("original"))
    let instant = ContinuousClock.now
    let expiry = IntakeWritePermit(
      deadline: instant.advanced(by: .seconds(30)),
      now: {
        let folders =
          (try? FileManager.default.contentsOfDirectory(
            at: receipts, includingPropertiesForKeys: nil)) ?? []
        let copied = folders.contains {
          $0 != foreign && $0.pathExtension == "partial"
            && FileManager.default.fileExists(atPath: $0.appendingPathComponent("original").path)
        }
        return copied ? instant.advanced(by: .seconds(60)) : instant
      })
    do {
      _ = try IntakeStaging.stage(source, generation: generation, gate: gate, permit: expiry)
      preconditionFailure("Expired copied file was published")
    } catch IntakeProviderError.timedOut {}
    let remaining = try files.contentsOfDirectory(at: receipts, includingPropertiesForKeys: nil)
    precondition(
      Set(remaining.map(\.lastPathComponent)) == [published.id, foreign.lastPathComponent])
    let sourceAfterCancel = try Data(contentsOf: source)
    precondition(sourceAfterCancel == bytes)

    // A killed extension cannot revive an unaccepted provider copy via recovery.
    let owned = receipts.appendingPathComponent(published.id)
    let partial = receipts.appendingPathComponent(published.id + ".partial")
    try files.moveItem(at: owned, to: partial)
    try Data().write(to: partial.appendingPathComponent("awaiting-provider-commit"))
    let interrupted = try IntakeStaging.pending(gate: gate)
    precondition(interrupted.receipts.isEmpty && interrupted.preservedIssues == 2)
    let interruptedBytes = try Data(contentsOf: partial.appendingPathComponent("original"))
    precondition(interruptedBytes == bytes)
    // A committed legacy receipt retains its recovery behavior.
    try files.removeItem(at: partial.appendingPathComponent("awaiting-provider-commit"))
    let recovered = try IntakeStaging.pending(gate: gate)
    precondition(recovered.receipts.map { $0.0.id } == [published.id])

    let committedPermit = IntakeWritePermit(deadline: .now.advanced(by: .seconds(30)))
    let committed = try IntakeStaging.stage(
      source, generation: generation, gate: gate, permit: committedPermit)
    committedPermit.revoke()
    precondition(!committedPermit.discardsUnpublishedFiles)
    precondition(files.fileExists(atPath: receipts.appendingPathComponent(committed.id).path))

    // Erasure fencing remains authoritative even for an otherwise active request.
    let delayed = Provider()
    let delayedTask = Task {
      try await IntakeProviderRequest.receive(start: delayed.start, stage: stage)
    }
    await ready(delayed)
    try gate.beginErasure()
    try gate.finishErasure()
    delayed.callback?(source, nil)
    do {
      _ = try await delayedTask.value
      preconditionFailure("Pre-erasure provider republished data")
    } catch IntakeGateError.expired {}
    precondition(!files.fileExists(atPath: receipts.path))
    let sourceAfterErasure = try Data(contentsOf: source)
    precondition(sourceAfterErasure == bytes)
    print(
      "Share intake: deadline, cancel, late/duplicate callbacks, owned cleanup, recovery and erasure passed"
    )
  }
}
