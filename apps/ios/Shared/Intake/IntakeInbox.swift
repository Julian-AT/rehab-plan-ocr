import Foundation

/// Inbox names are recoverable originals. Publish them only after a complete,
/// bounded copy; hidden workspaces left by interruption are never recovery input.
enum IntakeInbox {
  private static let maximumBytes = 40 * 1024 * 1024

  static func stage(
    _ source: URL, at destination: URL,
    copy: (FileHandle, FileHandle) throws -> Void = copyContents
  ) throws -> URL {
    try IntakeStaging.validateSize(source)
    if source.standardizedFileURL == destination.standardizedFileURL { return destination }
    let files = FileManager.default
    let root = destination.deletingLastPathComponent()
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    let workspace = root.appendingPathComponent(".intake-\(UUID().uuidString).partial")
    try files.createDirectory(at: workspace, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: workspace) }
    let temporary = workspace.appendingPathComponent("original")
    guard files.createFile(atPath: temporary.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: temporary)
    defer { try? output.close() }
    try copy(input, output)
    try output.synchronize()
    try output.close()
    try IntakeStaging.validateSize(temporary)
    if files.fileExists(atPath: destination.path) {
      guard try sameContents(temporary, destination) else {
        throw CocoaError(.fileWriteFileExists)
      }
      return destination
    }
    // Same-filesystem move publishes the final name only after the copy is
    // complete. A prior complete file is never replaced by an interrupted copy.
    try files.moveItem(at: temporary, to: destination)
    return destination
  }

  static func copyContents(_ input: FileHandle, _ output: FileHandle) throws {
    var count = 0
    while let chunk = try input.read(upToCount: min(64 * 1024, maximumBytes + 1 - count)),
      !chunk.isEmpty
    {
      count += chunk.count
      guard count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
      try output.write(contentsOf: chunk)
    }
    guard count > 0 else { throw CocoaError(.fileReadCorruptFile) }
  }

  private static func sameContents(_ first: URL, _ second: URL) throws -> Bool {
    try IntakeStaging.validateSize(second)
    let left = try FileHandle(forReadingFrom: first)
    defer { try? left.close() }
    let right = try FileHandle(forReadingFrom: second)
    defer { try? right.close() }
    var count = 0
    while true {
      let limit = min(64 * 1024, maximumBytes + 1 - count)
      let a = try left.read(upToCount: limit) ?? Data()
      let b = try right.read(upToCount: limit) ?? Data()
      guard a == b else { return false }
      count += a.count
      guard count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
      if a.isEmpty { return true }
    }
  }

  static func pending(in root: URL) throws -> [URL] {
    let files = FileManager.default
    guard files.fileExists(atPath: root.path) else { return [] }
    return try files.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    ).filter {
      (try? files.attributesOfItem(atPath: $0.path)[.type] as? FileAttributeType) == .typeRegular
    }
  }
}
