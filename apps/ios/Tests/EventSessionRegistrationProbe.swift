import Foundation

@MainActor private final class Registrar {
  var registered: [String] = []
  var revoked: [String] = []
  var suspended: CheckedContinuation<Void, Never>?
  var hold = false

  func register() async throws -> String {
    let token = UUID().uuidString
    registered.append(token)
    if hold {
      hold = false
      await withCheckedContinuation { suspended = $0 }
    }
    try Task.checkCancellation()
    return token
  }

  func release() {
    suspended?.resume()
    suspended = nil
  }

  func registration() -> EventSessionRegistration {
    EventSessionRegistration(
      register: { try await self.register() }, revoke: { self.revoked.append($0) })
  }
}

@main @MainActor struct EventSessionRegistrationProbe {
  private static func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 {
      if condition() { return }
      await Task.yield()
    }
    preconditionFailure("Expected registration state was not reached")
  }

  static func main() async throws {
    let registrar = Registrar()
    let registration = registrar.registration()
    let first = try await registration.acquire()
    let again = try await registration.acquire()
    precondition(first == again && registrar.registered.count == 1)
    registration.invalidate()
    await waitUntil { registrar.revoked == [first] }
    let second = try await registration.acquire()
    precondition(second != first)
    registration.invalidate()
    await waitUntil { registrar.revoked.count == 2 }

    // An old reply cannot replace a newer session, and its server token is closed.
    registrar.hold = true
    let old = Task { try await registration.acquire() }
    await waitUntil { registrar.suspended != nil }
    let delayed = registrar.registered.last!
    registration.invalidate()
    let newest = try await registration.acquire()
    registrar.release()
    do {
      _ = try await old.value
      preconditionFailure("Interrupted registration returned a token")
    } catch is CancellationError {}
    precondition(registrar.revoked.contains(delayed))
    let retained = try await registration.acquire()
    precondition(retained == newest)
    registration.invalidate()
    await waitUntil { registrar.revoked.contains(newest) }

    // Cancelling the waiter must still obtain and revoke the registered token.
    registrar.hold = true
    let cancelled = Task { try await registration.acquire() }
    await waitUntil { registrar.suspended != nil }
    let cancelledToken = registrar.registered.last!
    cancelled.cancel()
    registrar.release()
    do {
      _ = try await cancelled.value
      preconditionFailure("Cancelled registration returned a token")
    } catch is CancellationError {}
    precondition(registrar.revoked.contains(cancelledToken))

    var abandoned: EventSessionRegistration? = registrar.registration()
    let abandonedToken = try await abandoned!.acquire()
    abandoned = nil
    await waitUntil { registrar.revoked.contains(abandonedToken) }
    precondition(Set(registrar.registered) == Set(registrar.revoked))
    print(
      "Event sessions: reuse, invalidation, delayed registration, cancellation and disposal passed")
  }
}
