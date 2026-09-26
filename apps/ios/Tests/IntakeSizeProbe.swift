import Foundation

@main struct IntakeSizeProbe {
  static func main() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }
    let source = root.appendingPathComponent("photo.heic")
    precondition(files.createFile(atPath: source.path, contents: Data([1])))
    let handle = try FileHandle(forWritingTo: source)
    defer { try? handle.close() }
    let maximum: UInt64 = 40 * 1024 * 1024
    try handle.truncate(atOffset: maximum)
    try IntakeStaging.validateSize(source)
    try handle.truncate(atOffset: maximum + 1)
    try rejects(source)
    // Sparse files exercise admission without allocating the oversized payload.
    let oversizedAttributes = try files.attributesOfItem(atPath: source.path)
    precondition(oversizedAttributes[.size] as? UInt64 == maximum + 1)
    try rejects(root)
    let link = root.appendingPathComponent("link")
    try files.createSymbolicLink(at: link, withDestinationURL: source)
    try rejects(link)
    try handle.truncate(atOffset: 1)
    try IntakeStaging.validateSize(source)
    let remaining = try Data(contentsOf: source)
    precondition(remaining == Data([1]), "Admission modified the original")
    print("Photo intake: 40 MiB boundary, oversized sparse file, directory and symlink passed.")
  }

  private static func rejects(_ url: URL) throws {
    do {
      try IntakeStaging.validateSize(url)
      preconditionFailure("Invalid photo source accepted: \(url.lastPathComponent)")
    } catch let error as CocoaError {
      precondition(error.code == .fileReadTooLarge)
    }
  }
}
