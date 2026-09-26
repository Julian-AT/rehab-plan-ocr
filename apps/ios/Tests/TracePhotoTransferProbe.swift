import Foundation

private actor Signal {
  private var sent = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    guard !sent else { return }
    await withCheckedContinuation { waiting.append($0) }
  }
  func send() {
    sent = true
    let continuations = waiting
    waiting = []
    for continuation in continuations { continuation.resume() }
  }
}

@main struct TracePhotoTransferProbe {
  @MainActor static func main() async throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let store = AppTemporaryStore(temporary: root)
    try await store.prepare()
    let transfer = TracePhotoTransfer(store: store)
    let entered = Signal()
    let allowCallback = Signal()
    let photo = root.appendingPathComponent("late-provider-photo")
    let loading = Task { @MainActor in
      try await transfer.load {
        await entered.send()
        await allowCallback.wait()
        // The provider itself must remain uncancelled: an async provider wrapper
        // can otherwise return while its file callback is still copying bytes.
        precondition(!Task.isCancelled)
        try Data("synthetic private photo".utf8).write(to: photo)
        return photo
      }
    }
    await entered.wait()
    var erased = false
    let erasure = Task { @MainActor in
      try await store.erase()
      erased = true
    }
    while true {
      do {
        let lease = try await store.acquire(.recognition) {}
        try await store.release(lease)
        await Task.yield()
      } catch is CancellationError { break }
    }
    precondition(!erased, "Erasure acknowledged while the provider could still write")
    await allowCallback.send()
    do {
      _ = try await loading.value
      fatalError("A pre-erasure photo was delivered to tracing")
    } catch is CancellationError {}
    try await erasure.value
    precondition(erased && !files.fileExists(atPath: photo.path))

    var requestedWhileClosed = false
    do {
      _ = try await transfer.load {
        requestedWhileClosed = true
        return photo
      }
      fatalError("Provider started while erasure admission was closed")
    } catch is CancellationError {}
    precondition(!requestedWhileClosed)

    await store.resume()
    let delivered = try await transfer.load {
      try Data("synthetic fresh photo".utf8).write(to: photo)
      return photo
    }
    precondition(delivered == photo && files.fileExists(atPath: photo.path))
    await transfer.close()
    precondition(!files.fileExists(atPath: photo.path))
    print(
      "Trace photo transfer: delayed provider drain, erasure fencing and dismissal cleanup passed")
  }
}
