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

    let failures: [NativeServiceError] = [
      .permissionDenied, .invalidInput("Ungültig"), .storage("Speicherfehler"),
      .timeout("snapshot"), .uncertainWrite, .cancelled,
    ]
    for expected in failures {
      let observed = OSAllocatedUnfairLock<NativeServiceError?>(initialState: nil)
      let request = ServiceRequest(arguments: Data()) { result in
        if case .failure(let error) = result {
          observed.withLock { $0 = error as? NativeServiceError }
        }
      }
      request.reject(expected)
      precondition(observed.withLock { $0 } == expected, "Typed request failure was lost")
    }

    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      defer { finished.signal() }
      for operation in [
        NativeOperation.snapshot, .queryEvents, .getEvent, .decodePhoto, .recognize,
      ] {
        do {
          _ = try NativeServiceCall.wait(for: operation, timeout: 0.001) { _ in }
          preconditionFailure("Missing completion must expire")
        } catch {
          precondition(error as? NativeServiceError == .timeout(operation.rawValue))
        }
      }
      for operation in [NativeOperation.apply, .mutateEvent, .agenda] {
        do {
          _ = try NativeServiceCall.wait(for: operation, timeout: 0.001) { _ in }
          preconditionFailure("Missing write completion must remain uncertain")
        } catch { precondition(error as? NativeServiceError == .uncertainWrite) }
      }
      for expected in failures {
        do {
          _ = try NativeServiceCall.wait(for: .snapshot) { $0(.failure(expected)) }
          preconditionFailure("Failure must propagate")
        } catch { precondition(error as? NativeServiceError == expected) }
      }
      let late = OSAllocatedUnfairLock<NativeServiceCall.Completion?>(initialState: nil)
      do {
        _ = try NativeServiceCall.wait(for: .snapshot, timeout: 0.001) { callback in
          late.withLock { $0 = callback }
        }
        preconditionFailure("Late callback must expire")
      } catch { precondition(error as? NativeServiceError == .timeout("snapshot")) }
      late.withLock { $0 }?(.success(Data("late".utf8)))
      late.withLock { $0 }?(.failure(NativeServiceError.uncertainWrite))
      do {
        let next = try NativeServiceCall.wait(for: .snapshot) { callback in
          callback(.success(Data("current".utf8)))
          callback(.failure(NativeServiceError.cancelled))
        }
        precondition(next == Data("current".utf8), "Late or duplicate result changed another call")
      } catch { preconditionFailure("Successful completion failed: \(error)") }
    }
    precondition(finished.wait(timeout: .now() + 5) == .success, "Bridge tests stalled")
    print("Native request: concurrent completion, re-entry and invalid-input checks passed")
  }
}
