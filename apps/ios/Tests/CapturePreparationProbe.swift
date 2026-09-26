import Foundation

@main struct CapturePreparationProbe {
  @MainActor static func main() async throws {
    let accepted = CapturePreparation()
    let signal = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    var received: Data?
    let task = accepted.start {
      signal.continuation.yield(())
      precondition(release.wait(timeout: .now() + 5) == .success, "Main actor blocked by encoding")
      return Data([1, 2, 3])
    } complete: { result in
      MainActor.assertIsolated()
      received = try? result.get()
    }!
    var iterator = signal.stream.makeAsyncIterator()
    await iterator.next()
    precondition(received == nil)
    precondition(
      accepted.start(
        operation: { Data() },
        complete: { _ in
          preconditionFailure("Duplicate capture delivered")
        }) == nil)
    // The UI actor reaches this point while the worker remains inside encoding.
    release.signal()
    await task.value
    precondition(received == Data([1, 2, 3]))

    let cancelled = CapturePreparation()
    let began = AsyncStream<Void>.makeStream()
    let finish = DispatchSemaphore(value: 0)
    let cancelledTask = cancelled.start {
      began.continuation.yield(())
      precondition(finish.wait(timeout: .now() + 5) == .success)
      return Data([4])
    } complete: { _ in
      preconditionFailure("Dismissed capture delivered late data or error")
    }!
    var cancellationIterator = began.stream.makeAsyncIterator()
    await cancellationIterator.next()
    cancelled.cancel()
    finish.signal()
    await cancelledTask.value
    precondition(
      cancelled.start(
        operation: { Data() },
        complete: { _ in
          preconditionFailure("Dismissed capture restarted")
        }) == nil)

    enum Failure: Error { case encoding }
    let failed = CapturePreparation()
    var failedOnce = false
    let failureTask = failed.start {
      throw Failure.encoding
    } complete: { result in
      if case .failure(Failure.encoding) = result { failedOnce = true }
    }!
    await failureTask.value
    precondition(failedOnce)
    failed.cancel()
    print(
      "Capture preparation passed: responsive UI actor, one delivery, encoding failure and dismissal cancellation."
    )
  }
}
