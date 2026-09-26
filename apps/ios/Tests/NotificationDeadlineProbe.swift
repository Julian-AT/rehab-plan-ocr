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

@main struct NotificationDeadlineProbe {
  static func main() async throws {
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
      "Notification deadlines: bounded uncooperative operations, one timeout, late cleanup and resumed admission passed."
    )
  }
}
