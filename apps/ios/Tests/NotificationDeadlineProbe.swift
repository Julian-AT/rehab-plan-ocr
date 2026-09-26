import Foundation

private actor HeldOperations {
  var waiting: [Int: CheckedContinuation<Int, Never>] = [:]
  var started = Set<Int>()
  func run(_ id: Int) async -> Int {
    started.insert(id)
    return await withCheckedContinuation { waiting[id] = $0 }
  }
  func release(_ id: Int) { waiting.removeValue(forKey: id)?.resume(returning: id) }
}

private final class CompletionOwner: Sendable {
  let released: AsyncStream<Bool>.Continuation
  init(_ released: AsyncStream<Bool>.Continuation) { self.released = released }
  deinit {
    released.yield(true)
    released.finish()
  }
}

@main struct NotificationDeadlineProbe {
  private static func completedOwnerIsReleased(failing: Bool) async -> Bool {
    let queue = DispatchQueue(label: "deadline-completed-owner")
    let deadline = NotificationDeadline(queue: queue, seconds: 60)
    let released = AsyncStream<Bool>.makeStream()
    let succeeded: Bool = await withCheckedContinuation { continuation in
      queue.async {
        let owner = CompletionOwner(released.continuation)
        deadline.run(operation: {
          if failing { throw AgendaError.message("Simulierter Fehler") }
          return 42
        }) { [owner] result in
          withExtendedLifetime(owner) {
            continuation.resume(returning: (try? result.get()) == 42)
          }
        }
      }
    }
    precondition(succeeded == !failing)
    // Observe destruction, not a fixed delay. A completed operation must not
    // retain its owner until the cancelled 60-second work item reaches its queue.
    return await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        var iterator = released.stream.makeAsyncIterator()
        return await iterator.next() ?? false
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }
  }

  static func main() async throws {
    for failing in [false, true] {
      guard await completedOwnerIsReleased(failing: failing) else {
        print("Completed notification callback retained its owner until the cancelled deadline.")
        exit(1)
      }
    }
    let queue = DispatchQueue(label: "deadline-probe")
    let deadline = NotificationDeadline(queue: queue, seconds: 0.02, maximumOperations: 2)
    let held = HeldOperations()
    func run(_ id: Int, late: (@Sendable (Result<Int, Error>) -> Void)? = nil) async -> Result<
      Int, Error
    > {
      await withCheckedContinuation { continuation in
        queue.async {
          deadline.run(operation: { await held.run(id) }, late: late) {
            continuation.resume(returning: $0)
          }
        }
      }
    }
    let lateOne = AsyncStream<Int>.makeStream()
    for id in [1, 2] {
      let result = await run(id) { result in
        if let value = try? result.get() { lateOne.continuation.yield(value) }
      }
      if case .success = result { fatalError("Suspended adapter did not time out") }
    }
    for id in 3...102 {
      let result = await run(id)
      if case .success = result { fatalError("Exhausted slots admitted another adapter") }
    }
    let started = await held.started
    precondition(started == Set([1, 2]))
    await held.release(1)
    var iterator = lateOne.stream.makeAsyncIterator()
    let lateResult = await iterator.next()
    precondition(lateResult == 1)
    // Slot release happens before the late callback; this ordinary request must
    // now succeed even while the second original adapter remains suspended.
    let fresh: Result<Int, Error> = await withCheckedContinuation { continuation in
      queue.async {
        deadline.run(operation: { 103 }) { continuation.resume(returning: $0) }
      }
    }
    let freshValue = try fresh.get()
    precondition(freshValue == 103)
    await held.release(2)
    let second = await iterator.next()
    precondition(second == 2)
    lateOne.continuation.finish()
    print(
      "Notification deadlines: completed owners released, bounded uncooperative operations, one timeout, late cleanup and resumed admission passed."
    )
  }
}
