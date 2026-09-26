import Foundation
import Observation

extension AppTemporaryStore {
  func writeDiagnostic(_ data: Data, lease: Lease) throws -> URL {
    let url = try create(lease).appendingPathComponent("Diagnose-\(UUID().uuidString).json")
    #if os(iOS)
      try data.write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: url, options: .atomic)
    #endif
    return url
  }
}

/// The export is admitted before its asynchronous producer starts. Dismissal
/// and global erasure cancel and drain that producer before releasing its file.
@MainActor @Observable final class TemporaryDiagnosticExport {
  private let store: AppTemporaryStore
  private var lease: AppTemporaryStore.Lease?
  private var task: Task<URL, Error>?
  private var generation = UUID()
  private(set) var url: URL?

  init(store: AppTemporaryStore = .shared) { self.store = store }

  func write(_ generate: @escaping @MainActor () async throws -> Data) async throws {
    let current = UUID()
    generation = current
    await drain(current)
    guard generation == current else { throw CancellationError() }
    try Task.checkCancellation()
    let pending = Task { @MainActor [self] in
      let lease = try await store.acquire(.diagnostic) { [weak self] in await self?.close() }
      self.lease = lease
      do {
        try Task.checkCancellation()
        let data = try await generate()
        try Task.checkCancellation()
        return try await store.writeDiagnostic(data, lease: lease)
      } catch {
        try? await store.release(lease)
        if self.lease == lease { self.lease = nil }
        throw error
      }
    }
    task = pending
    do {
      let value = try await withTaskCancellationHandler {
        try await pending.value
      } onCancel: {
        pending.cancel()
      }
      guard generation == current, !pending.isCancelled, !Task.isCancelled else {
        throw CancellationError()
      }
      url = value
      task = nil
    } catch {
      if generation == current {
        task = nil
        let stale = lease
        lease = nil
        if let stale { try? await store.release(stale) }
      }
      throw error
    }
  }

  func close() async {
    let current = UUID()
    generation = current
    await drain(current)
  }

  private func drain(_ current: UUID) async {
    let pending = task
    pending?.cancel()
    url = nil
    _ = try? await pending?.value
    guard generation == current else { return }
    let stale = lease
    lease = nil
    task = nil
    if let stale { try? await store.release(stale) }
  }
}
