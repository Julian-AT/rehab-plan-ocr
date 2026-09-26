import Foundation
import os

@main struct ServiceRequestProbe {
  static func main() throws {
    struct Arguments: Decodable { let value: Int }
    let results = OSAllocatedUnfairLock(initialState: [Result<Data, Error>]())
    let request = ServiceRequest(arguments: Data("{\"value\":7}".utf8)) { result in
      results.withLock { $0.append(result) }
    }
    DispatchQueue.concurrentPerform(iterations: 1_000) { index in
      if index.isMultiple(of: 2) {
        request.resolve(["completed": index])
      } else {
        request.reject("Testfehler")
      }
    }
    precondition(
      results.withLock { $0.count } == 1, "Concurrent completion delivered more than once")
    let arguments = try request.parseArgs(Arguments.self)
    precondition(arguments.value == 7)

    let holder = OSAllocatedUnfairLock<ServiceRequest?>(initialState: nil)
    let reentries = OSAllocatedUnfairLock(initialState: 0)
    let reentrant = ServiceRequest(arguments: Data()) { _ in
      reentries.withLock { $0 += 1 }
      holder.withLock { $0 }?.reject("Late failure after successful completion")
    }
    holder.withLock { $0 = reentrant }
    reentrant.resolve()
    reentrant.reject("Another late result")
    precondition(reentries.withLock { $0 } == 1, "Re-entry must not deadlock or deliver twice")
    holder.withLock { $0 = nil }

    let invalidResults = OSAllocatedUnfairLock(initialState: 0)
    let invalid = ServiceRequest(arguments: Data("not JSON".utf8)) { result in
      if case .failure = result { invalidResults.withLock { $0 += 1 } }
    }
    do {
      _ = try invalid.parseArgs(Arguments.self)
      preconditionFailure("Invalid input must fail decoding")
    } catch { invalid.reject(error.localizedDescription) }
    invalid.resolve()
    precondition(invalidResults.withLock { $0 } == 1)
    print("Native request: concurrent completion, re-entry and invalid-input checks passed")
  }
}
