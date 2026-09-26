import Foundation

/// Local generations fence delayed registration; the server only retains active
/// editing tokens. Cleanup also joins registrations whose caller was cancelled.
@MainActor final class EventSessionRegistration {
  typealias Register = @MainActor @Sendable () async throws -> String
  typealias Revoke = @MainActor @Sendable (String) async -> Void
  private let register: Register
  private let revoke: Revoke
  private var generation = UUID()
  private var current: String?

  init(register: @escaping Register, revoke: @escaping Revoke) {
    self.register = register
    self.revoke = revoke
  }

  func acquire() async throws -> String {
    try Task.checkCancellation()
    if let current { return current }
    let generation = generation
    // Registration must finish even when its waiter is cancelled, otherwise its
    // server-issued token could be lost before it can be revoked.
    let registration = Task { try await register() }
    let token = try await registration.value
    guard generation == self.generation, !Task.isCancelled else {
      await Task { await revoke(token) }.value
      throw CancellationError()
    }
    if let current {
      await Task { await revoke(token) }.value
      guard generation == self.generation, !Task.isCancelled else {
        throw CancellationError()
      }
      return current
    }
    current = token
    return token
  }

  func invalidate() {
    generation = UUID()
    guard let token = current else { return }
    current = nil
    Task { await revoke(token) }
  }

  deinit {
    if let current {
      let revoke = revoke
      Task { await revoke(current) }
    }
  }
}
