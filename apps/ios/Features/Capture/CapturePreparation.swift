import Foundation

/// One accepted camera image. Encoding may finish after dismissal, but delivery may not.
@MainActor final class CapturePreparation {
  private enum State { case idle, preparing, finished, cancelled }
  private var state = State.idle
  private var task: Task<Void, Never>?

  @discardableResult func start(
    operation: @escaping @Sendable () throws -> Data,
    complete: @escaping @MainActor (Result<Data, Error>) -> Void
  ) -> Task<Void, Never>? {
    guard state == .idle else { return nil }
    state = .preparing
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let data = try operation()
      try Task.checkCancellation()
      return data
    }
    task = Task { [weak self] in
      let result: Result<Data, Error>
      do {
        let data = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        result = .success(data)
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled, let self, self.state == .preparing else { return }
      self.state = .finished
      self.task = nil
      complete(result)
    }
    return task
  }

  func cancel() {
    state = .cancelled
    task?.cancel()
    task = nil
  }
}
