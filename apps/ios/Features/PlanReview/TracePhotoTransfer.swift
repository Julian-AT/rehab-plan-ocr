import Foundation

/// Own the provider before asking it for a photo. Cancellation is advisory, so
/// data erasure waits for the callback and cleanup before removing photo scratch.
@MainActor final class TracePhotoTransfer {
  private let store: AppTemporaryStore
  private var lease: AppTemporaryStore.Lease?
  private var task: Task<URL, Error>?
  private var source: URL?
  private var generation = UUID()

  init(store: AppTemporaryStore = .shared) { self.store = store }

  func load(_ receive: @escaping @MainActor () async throws -> URL) async throws -> URL {
    await close()
    let current = UUID()
    generation = current
    let pending = Task { @MainActor [self] in
      let lease = try await store.acquire(.recognition) { [weak self] in await self?.close() }
      self.lease = lease
      do {
        try Task.checkCancellation()
        // Do not propagate cancellation into the provider's async wrapper: it
        // might return before its file-representation callback stops writing.
        // Keep waiting for the uncancelled transfer and then discard its result.
        let provider = Task { @MainActor in try await receive() }
        let received = try await provider.value
        source = received
        try Task.checkCancellation()
        return received
      } catch {
        if let source { try? FileManager.default.removeItem(at: source) }
        source = nil
        try? await store.release(lease)
        if self.lease == lease { self.lease = nil }
        throw error
      }
    }
    task = pending
    do {
      let url = try await withTaskCancellationHandler {
        try await pending.value
      } onCancel: {
        pending.cancel()
      }
      guard generation == current, !pending.isCancelled else { throw CancellationError() }
      task = nil
      return url
    } catch {
      if generation == current { task = nil }
      throw error
    }
  }

  func close() async {
    generation = UUID()
    let pending = task
    pending?.cancel()
    _ = try? await pending?.value
    if let source { try? FileManager.default.removeItem(at: source) }
    source = nil
    if let lease { try? await store.release(lease) }
    lease = nil
    task = nil
  }
}
