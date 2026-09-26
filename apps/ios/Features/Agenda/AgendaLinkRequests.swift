import Foundation

enum AgendaLinkDelivery<Value: Sendable> {
  case today
  case event(Value)
}

/// Owns link work on the UI actor. Native reads may ignore Task cancellation;
/// the revision also fences their delivery and acknowledgement after navigation.
@MainActor final class AgendaLinkRequests<Value: Sendable> {
  typealias Delivery = @MainActor (AgendaLinkDelivery<Value>) throws -> Void
  typealias Failure = @MainActor (Error) -> Void
  private let resolve: @MainActor (String) async throws -> Value
  private let pending: @MainActor (String?) async throws -> String?
  private var task: Task<Void, Never>?
  private var activeEventID: String?
  private(set) var revision = UUID()

  init(
    resolve: @escaping @MainActor (String) async throws -> Value,
    pending: @escaping @MainActor (String?) async throws -> String?
  ) {
    self.resolve = resolve
    self.pending = pending
  }

  deinit { task?.cancel() }

  func invalidate() {
    revision = UUID()
    task?.cancel()
    task = nil
    activeEventID = nil
  }

  @discardableResult func open(
    _ link: AgendaLink, deliver: @escaping Delivery, failed: @escaping Failure
  ) -> Task<Void, Never>? {
    switch link {
    case .today:
      invalidate()
      do { try deliver(.today) } catch { failed(error) }
      return nil
    case .event(let id):
      guard activeEventID != id else { return task }
      return start(id: id, deliver: deliver, failed: failed)
    }
  }

  /// Capture this revision before startup/share recovery awaits. A delayed
  /// resume must not replace a URL or user navigation that arrived meanwhile.
  @discardableResult func openPending(
    expectedRevision: UUID, deliver: @escaping Delivery, failed: @escaping Failure
  ) -> Task<Void, Never>? {
    guard current(expectedRevision), task == nil else { return nil }
    return start(id: nil, deliver: deliver, failed: failed)
  }

  private func current(_ request: UUID) -> Bool {
    revision == request && !Task.isCancelled
  }

  private func finish(_ request: UUID) {
    guard revision == request else { return }
    task = nil
    activeEventID = nil
  }

  private func start(
    id: String?, deliver: @escaping Delivery, failed: @escaping Failure
  ) -> Task<Void, Never> {
    invalidate()
    activeEventID = id
    let request = revision
    let resolve = resolve
    let pending = pending
    let work = Task { [weak self] in
      defer { self?.finish(request) }
      do {
        let target: String?
        if let id { target = id } else { target = try await pending(nil) }
        guard self?.current(request) == true, let target, UUID(uuidString: target) != nil else {
          return
        }
        self?.activeEventID = target
        let value = try await resolve(target)
        guard self?.current(request) == true else { return }
        try deliver(.event(value))
        guard self?.current(request) == true else { return }
        _ = try await pending(target)
      } catch {
        if self?.current(request) == true { failed(error) }
      }
    }
    task = work
    return work
  }
}
