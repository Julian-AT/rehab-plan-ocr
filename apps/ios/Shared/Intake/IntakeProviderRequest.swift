import Foundation
import os

enum IntakeProviderError: LocalizedError {
  case timedOut
  var errorDescription: String? {
    "Die Datei wurde nicht rechtzeitig bereitgestellt. Bitte erneut teilen."
  }
}

/// Per-request write admission, independent of the cross-process erasure ticket.
/// Revocation and final publication share one lock; published receipts stay owned
/// by IntakeStaging and are never removed by cancellation of the provider.
final class IntakeWritePermit: Sendable {
  private enum State: Sendable { case active, revoked, published }
  private let state = OSAllocatedUnfairLock(initialState: State.active)
  private let deadline: ContinuousClock.Instant
  private let now: @Sendable () -> ContinuousClock.Instant

  init(
    deadline: ContinuousClock.Instant,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
  ) {
    self.deadline = deadline
    self.now = now
  }

  func check() throws {
    try state.withLock { value in
      guard value == .active else { throw CancellationError() }
      guard now() < deadline else { throw IntakeProviderError.timedOut }
    }
  }
  func revoke() {
    state.withLock { value in
      if value == .active { value = .revoked }
    }
  }
  var discardsUnpublishedFiles: Bool {
    state.withLock { $0 == .revoked || ($0 == .active && now() >= deadline) }
  }
  func publish(_ move: @Sendable () throws -> Void) throws {
    try state.withLock { value in
      guard value == .active else { throw CancellationError() }
      guard now() < deadline else { throw IntakeProviderError.timedOut }
      // Only the final local rename runs under this lock, never copy/hash/fsync.
      try move()
      value = .published
    }
  }
}

/// NSItemProvider cancellation is advisory. Finish the caller ourselves and
/// reject late/duplicate callbacks before they can touch the provider's file.
final class IntakeProviderRequest: Sendable {
  typealias Completion = @Sendable (Result<IntakeReceipt, Error>) -> Void
  private struct State: Sendable {
    var receiving = false
    var result: Result<IntakeReceipt, Error>?
    var completion: Completion?
    var progress: Progress?
    var timer: Task<Void, Never>?
  }
  private let state = OSAllocatedUnfairLock(initialState: State())
  private let permit: IntakeWritePermit

  private init(timeout: TimeInterval) {
    permit = IntakeWritePermit(deadline: .now.advanced(by: .seconds(timeout)))
  }

  @MainActor static func receive(
    timeout: TimeInterval = 30,
    start: (@escaping @Sendable (URL?, Error?) -> Void) -> Progress,
    stage: @escaping @Sendable (URL, IntakeWritePermit) throws -> IntakeReceipt
  ) async throws -> IntakeReceipt {
    precondition(timeout.isFinite && timeout > 0)
    let request = IntakeProviderRequest(timeout: timeout)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard request.install({ continuation.resume(with: $0) }, timeout: timeout) else { return }
        let progress = start { url, error in request.received(url, error: error, stage: stage) }
        request.attach(progress)
      }
    } onCancel: {
      request.stop(CancellationError())
    }
  }

  private func install(_ completion: @escaping Completion, timeout: TimeInterval) -> Bool {
    let timer = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(timeout))
        self?.stop(IntakeProviderError.timedOut)
      } catch {}
    }
    let result = state.withLock { value -> Result<IntakeReceipt, Error>? in
      if let result = value.result { return result }
      value.completion = completion
      value.timer = timer
      return nil
    }
    if let result {
      timer.cancel()
      completion(result)
      return false
    }
    return true
  }
  private func attach(_ progress: Progress) {
    let cancel = state.withLock { value in
      if let result = value.result {
        if case .failure = result { return true }
      } else {
        value.progress = progress
      }
      return false
    }
    if cancel { Self.cancel(progress) }
  }
  private func received(
    _ url: URL?, error: Error?,
    stage: (URL, IntakeWritePermit) throws -> IntakeReceipt
  ) {
    let accepted = state.withLock { value in
      guard value.result == nil, !value.receiving else { return false }
      value.receiving = true
      return true
    }
    guard accepted else { return }
    do {
      try permit.check()
      guard let url else { throw error ?? CocoaError(.fileNoSuchFile) }
      finish(.success(try stage(url, permit)))
    } catch { finish(.failure(error)) }
  }
  private func stop(_ error: Error) {
    permit.revoke()
    finish(.failure(error))
  }
  private func finish(_ result: Result<IntakeReceipt, Error>) {
    let ended = state.withLock { value -> (Completion?, Progress?, Task<Void, Never>?)? in
      guard value.result == nil else { return nil }
      value.result = result
      let ended = (value.completion, value.progress, value.timer)
      value.completion = nil
      value.progress = nil
      value.timer = nil
      return ended
    }
    guard let (completion, progress, timer) = ended else { return }
    timer?.cancel()
    completion?(result)
    if case .failure = result, let progress { Self.cancel(progress) }
  }
  private static func cancel(_ progress: Progress) {
    // Provider cancellation handlers are foreign code. They must not hold up
    // our deadline delivery or the visible cancel button.
    DispatchQueue.global(qos: .utility).async { progress.cancel() }
  }
}
