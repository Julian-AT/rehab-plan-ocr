import AppKit
import Observation
import SwiftUI

@MainActor @Observable private final class ThumbnailScenario {
  let directory: URL
  var page = "first"
  var refresh = 0
  var processing = false
  var rendered: String?
  var discoveries = 0
  var decodes = 0
  var holdNext = false
  var suspended: CheckedContinuation<Void, Never>?
  init(directory: URL) { self.directory = directory }
  func locate(_ page: String) -> URL {
    discoveries += 1
    return directory.appendingPathComponent(page)
  }
  func load(_ url: URL) async throws -> String {
    decodes += 1
    let value = try String(contentsOf: url, encoding: .utf8)
    if holdNext {
      holdNext = false
      await withCheckedContinuation { suspended = $0 }
    }
    return value
  }
}

private struct MountedThumbnail: View {
  let scenario: ThumbnailScenario
  var body: some View {
    ArtifactThumbnail(
      request: ArtifactThumbnailRequest(
        page: scenario.page, refresh: scenario.refresh, processing: scenario.processing),
      locate: { scenario.locate($0) }, load: { try await scenario.load($0) },
      content: { value in
        Text(value ?? "placeholder")
          .onChange(of: value, initial: true) { scenario.rendered = value }
      })
  }
}

@main @MainActor struct ArtifactThumbnailProbe {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task {
      do {
        try await run()
        print(
          "Archive thumbnail: mounted missing/replaced/in-place pages, reuse and cancellation passed"
        )
        exit(0)
      } catch {
        print("Archive thumbnail failed: \(error)")
        exit(1)
      }
    }
    app.run()
  }

  private static func until(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private static func run() async throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    let scenario = ThumbnailScenario(directory: directory)
    let window = NSWindow(
      contentRect: CGRect(x: -10_000, y: -10_000, width: 200, height: 80),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: MountedThumbnail(scenario: scenario))
    window.orderBack(nil)
    defer { window.close() }

    // All transitions use this same hosting view and the same row position.
    try await until { scenario.discoveries == 1 }
    precondition(scenario.rendered == nil && scenario.decodes == 0)
    let first = directory.appendingPathComponent("first")
    try Data("first".utf8).write(to: first)
    scenario.processing = true
    try await until { scenario.rendered == "first" }

    // Same path, same size, same inode: exact timestamps must invalidate it.
    let handle = try FileHandle(forWritingTo: first)
    try handle.write(contentsOf: Data("fresh".utf8))
    try handle.close()
    scenario.processing = false
    try await until { scenario.rendered == "fresh" }
    let decoded = scenario.decodes
    let discovered = scenario.discoveries
    scenario.refresh += 1
    try await until { scenario.discoveries > discovered }
    try await Task.sleep(for: .milliseconds(100))
    precondition(scenario.decodes == decoded, "Unchanged refresh decoded the same image again")

    let second = directory.appendingPathComponent("second")
    try Data("other".utf8).write(to: second)
    scenario.page = "second"
    try await until { scenario.rendered == "other" }

    // A decoder may ignore task cancellation and return after a newer image.
    scenario.holdNext = true
    try Data("stale".utf8).write(to: second, options: .atomic)
    scenario.refresh += 1
    try await until { scenario.suspended != nil }
    try Data("latest".utf8).write(to: second, options: .atomic)
    scenario.refresh += 1
    try await until { scenario.rendered == "latest" }
    scenario.suspended?.resume()
    scenario.suspended = nil
    try await Task.sleep(for: .milliseconds(100))
    precondition(scenario.rendered == "latest", "Cancelled decoder replaced the current image")

    try files.removeItem(at: second)
    scenario.refresh += 1
    try await until { scenario.rendered == nil }
  }
}
