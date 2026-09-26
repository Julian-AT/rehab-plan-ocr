import Foundation

/// Only disposable app-created files belong here. Original imports and the
/// persistent store keep their separate retention and recovery contracts.
actor AppTemporaryStore {
  static let shared = AppTemporaryStore(temporary: FileManager.default.temporaryDirectory)

  enum Kind: String, Sendable { case calendar, recognition }
  struct Lease: Equatable, Sendable {
    fileprivate let id: UUID
    fileprivate let generation: UUID
    let directory: URL
  }
  private struct Owner {
    let lease: Lease
    let cancelAndDrain: @Sendable () async -> Void
  }
  private let temporary: URL
  private let root: URL
  private var generation = UUID()
  private var owners: [UUID: Owner] = [:]
  private var prepared = false
  private var open = false

  init(temporary: URL) {
    self.temporary = temporary
    root = temporary.appendingPathComponent("reha-disposable-v1", isDirectory: true)
  }

  /// Run once, before presenting the app. A process restart has no live owners.
  func prepare() throws {
    guard !prepared else { return }
    try cleanup()
    prepared = true
    open = true
  }

  func acquire(_ kind: Kind, cancelAndDrain: @escaping @Sendable () async -> Void) throws -> Lease {
    guard open else { throw CancellationError() }
    let id = UUID()
    let lease = Lease(
      id: id, generation: generation,
      directory: root.appendingPathComponent("\(kind.rawValue)-\(id.uuidString)", isDirectory: true)
    )
    owners[id] = Owner(lease: lease, cancelAndDrain: cancelAndDrain)
    return lease
  }

  private func validate(_ lease: Lease) throws {
    guard open, lease.generation == generation, owners[lease.id]?.lease == lease else {
      throw CancellationError()
    }
  }

  func create(_ lease: Lease) throws -> URL {
    try validate(lease)
    let files = FileManager.default
    for directory in [root, lease.directory] {
      var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
      #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
      #endif
      try files.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: attributes)
      // Refuse a substituted directory rather than following its target.
      let current = try files.attributesOfItem(atPath: directory.path)
      guard current[.type] as? FileAttributeType == .typeDirectory else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
      var directory = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
    }
    return lease.directory
  }

  func writeCalendar(_ content: String, lease: Lease) throws -> URL {
    let url = try create(lease).appendingPathComponent("Termine.ics")
    let data = Data(content.utf8)
    #if os(iOS)
      try data.write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: url, options: .atomic)
    #endif
    return url
  }

  func release(_ lease: Lease) throws {
    guard owners[lease.id]?.lease == lease else { return }
    try removeIfPresent(lease.directory)
    owners.removeValue(forKey: lease.id)
  }

  /// Admission closes before callbacks run. Callbacks must wait for all writers,
  /// including native inference, before returning. Late leases stay invalid even
  /// after the caller explicitly reopens admission following successful erasure.
  func erase() async throws {
    open = false
    generation = UUID()
    let callbacks = owners.values.map(\.cancelAndDrain)
    for cancelAndDrain in callbacks { await cancelAndDrain() }
    try cleanup()
    owners.removeAll()
  }

  func resume() {
    precondition(prepared && owners.isEmpty)
    open = true
  }

  private func removeIfPresent(_ url: URL) throws {
    do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {}
  }

  private func cleanup() throws {
    try removeIfPresent(root)
    let files = FileManager.default
    let entries = try files.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
    for entry in entries {
      let name = entry.lastPathComponent
      // Exact legacy exporter names only; unrelated user and system temp files
      // are not evidence that they belong to this application feature.
      if name.hasPrefix("Termine-"), name.hasSuffix(".ics"),
        UUID(uuidString: String(name.dropFirst(8).dropLast(4))) != nil
      {
        try removeIfPresent(entry)
      }
    }
    let traces = temporary.appendingPathComponent("RecognitionTrace", isDirectory: true)
    if let attributes = try? files.attributesOfItem(atPath: traces.path),
      attributes[.type] as? FileAttributeType == .typeDirectory
    {
      for entry in try files.contentsOfDirectory(at: traces, includingPropertiesForKeys: nil)
      where UUID(uuidString: entry.lastPathComponent) != nil {
        try removeIfPresent(entry)
      }
    }
  }
}

/// A visible export owns its file until replacement, dismissal or data erasure.
/// Its producer is retained and drained so a suspended generator cannot recreate
/// sensitive files after the global erasure has completed.
@MainActor @Observable final class TemporaryCalendarExport {
  private let store: AppTemporaryStore
  private var lease: AppTemporaryStore.Lease?
  private var task: Task<URL, Error>?
  private var generation = UUID()
  private(set) var url: URL?

  init(store: AppTemporaryStore = .shared) { self.store = store }

  func write(_ generate: @escaping @MainActor () async throws -> String) async throws {
    await close()
    let current = UUID()
    generation = current
    let pending = Task { @MainActor [self] in
      let lease = try await store.acquire(.calendar) { [weak self] in await self?.close() }
      self.lease = lease
      do {
        try Task.checkCancellation()
        let content = try await generate()
        try Task.checkCancellation()
        return try await store.writeCalendar(content, lease: lease)
      } catch {
        try? await store.release(lease)
        if self.lease == lease { self.lease = nil }
        throw error
      }
    }
    task = pending
    do {
      let value = try await pending.value
      guard generation == current, !pending.isCancelled else { throw CancellationError() }
      url = value
      task = nil
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
    if let lease { try? await store.release(lease) }
    lease = nil
    task = nil
    url = nil
  }
}
