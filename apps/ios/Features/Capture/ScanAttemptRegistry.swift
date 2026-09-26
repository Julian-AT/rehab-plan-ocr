import Foundation

/// Entries describe live work, never historical cancellation tombstones. A
/// producer keeps its exact attempt until it drains; a reused document ID does
/// not grant old callbacks access to the new attempt.
@MainActor final class ScanAttemptRegistry {
  @MainActor final class Attempt {
    let id: String
    let ticket: IntakeAdmission.Ticket
    let parent: String?
    fileprivate var awaitingInput = true
    fileprivate var owners = Set<UUID>()
    fileprivate(set) var revoked = false
    fileprivate init(id: String, ticket: IntakeAdmission.Ticket, parent: String?) {
      self.id = id
      self.ticket = ticket
      self.parent = parent
    }
  }
  struct Lease {
    let attempt: Attempt
    fileprivate let owner = UUID()
  }
  enum RegistrationError: LocalizedError {
    case busy, full
    var errorDescription: String? {
      switch self {
      case .busy: "Diese Datei wird noch übernommen. Bitte kurz warten und erneut versuchen."
      case .full:
        "Es werden noch zu viele Dateien übernommen. Bitte die laufende Übernahme abwarten."
      }
    }
  }
  private var entries: [String: Attempt] = [:]
  private struct Draining {
    let lease: Lease
    let completion: @MainActor (Bool) -> Void
  }
  private var draining: [UUID: Draining] = [:]
  private var drainTask: Task<Void, Never>?
  private let limit: Int
  var count: Int { entries.count }
  var drainingCount: Int { draining.count }
  // A full share batch can contain 12 documents with 12 pages each.
  // Keep room for their roots and normal intake while bounding hung providers.
  init(limit: Int = 256) {
    precondition(limit > 0)
    self.limit = limit
  }
  func register(id: String, ticket: IntakeAdmission.Ticket, parent: String? = nil) throws -> Attempt
  {
    guard entries[id] == nil else { throw RegistrationError.busy }
    guard entries.count < limit else { throw RegistrationError.full }
    let attempt = Attempt(id: id, ticket: ticket, parent: parent)
    entries[id] = attempt
    return attempt
  }
  func contains(_ id: String) -> Bool { entries[id] != nil }
  func active(_ id: String) -> Attempt? {
    guard let attempt = entries[id], !attempt.revoked else { return nil }
    return attempt
  }
  func owns(_ attempt: Attempt) -> Bool { entries[attempt.id] === attempt }
  func permits(_ attempt: Attempt) -> Bool { owns(attempt) && !attempt.revoked }
  func begin(_ attempt: Attempt) -> Lease? {
    guard owns(attempt) else { return nil }
    let lease = Lease(attempt: attempt)
    attempt.owners.insert(lease.owner)
    return lease
  }
  @discardableResult func end(_ lease: Lease) -> Bool {
    guard draining[lease.owner] == nil else { return false }
    lease.attempt.owners.remove(lease.owner)
    return retire(lease.attempt)
  }
  /// Every caller supplies the same native-worker busy predicate. A partial
  /// result can finish its Swift task before the native writer has drained.
  /// Keep those owners registered with one shared timer, including after cancel.
  func endAfterDrain(
    _ lease: Lease, isBusy: @escaping @MainActor () -> Bool,
    completion: @escaping @MainActor (Bool) -> Void
  ) {
    guard owns(lease.attempt), lease.attempt.owners.contains(lease.owner),
      draining[lease.owner] == nil
    else { return }
    guard isBusy() else {
      completion(end(lease))
      return
    }
    draining[lease.owner] = Draining(lease: lease, completion: completion)
    guard drainTask == nil else { return }
    drainTask = Task {
      while isBusy() { try? await Task.sleep(for: .milliseconds(50)) }
      let pending = Array(draining.values)
      draining.removeAll()
      drainTask = nil
      for entry in pending { entry.completion(end(entry.lease)) }
    }
  }
  @discardableResult func finishInput(_ attempt: Attempt) -> Bool {
    attempt.awaitingInput = false
    return retire(attempt)
  }
  func revokeAll() {
    for attempt in Array(entries.values) {
      attempt.revoked = true
      attempt.awaitingInput = false
      retire(attempt)
    }
  }
  @discardableResult private func retire(_ attempt: Attempt) -> Bool {
    guard owns(attempt), !attempt.awaitingInput, attempt.owners.isEmpty else { return false }
    entries.removeValue(forKey: attempt.id)
    return true
  }
}
