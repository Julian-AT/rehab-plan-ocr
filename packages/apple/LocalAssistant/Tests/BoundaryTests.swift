import Foundation

#if canImport(LocalAssistant)
  import LocalAssistant
#endif

@main struct BoundaryTests {
  @MainActor static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("synthetic.gguf")
    try Data("synthetic invalid model".utf8).write(to: file)
    let wrong = LocalAssistant(
      asset: LocalAssistantAsset(url: file, sha256: String(repeating: "0", count: 64), bytes: 23))
    do {
      _ = try await wrong.generate(prompt: "Test", deadline: .now + .seconds(2))
      fatalError("Wrong asset size/hash was accepted")
    } catch LocalAssistantError.assetMismatch {}
    for (text, limit) in [("", UInt32(192)), ("Test", UInt32(0)), ("Test", UInt32(193))] {
      do {
        _ = try await wrong.generate(
          prompt: text, maximumTokens: limit, deadline: .now + .seconds(2))
        fatalError("Invalid request was accepted")
      } catch LocalAssistantError.invalidRequest {}
    }
    do {
      _ = try await wrong.generate(prompt: "Test", deadline: .now - .seconds(1))
      fatalError("Expired request was accepted")
    } catch LocalAssistantError.deadline {}
    let cancelled = Task {
      return try await wrong.generate(prompt: "Test", deadline: .now + .seconds(2))
    }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      fatalError("Canceled request was accepted")
    } catch is CancellationError {}
    print("Assistant boundary: invalid assets, bounded input and expired requests rejected")
  }
}
