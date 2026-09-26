import CryptoKit
import Foundation

struct IntakeReceipt: Codable, Sendable {
  let id: String
  let filename: String
  let sha256: String
  let receivedAt: Date
}
enum IntakeStaging {
  struct Pending: Sendable {
    let receipts: [(IntakeReceipt, URL, URL)]
    let preservedIssues: Int
    var warning: String? {
      guard preservedIssues > 0 else { return nil }
      return
        "Unvollständige oder beschädigte Dateiübernahmen bleiben zur Wiederherstellung erhalten. Bitte die betroffenen Dateien erneut teilen."
    }
  }
  static let group = "group.at.rehakalender.personal.intake"
  private static let providerMarker = "awaiting-provider-commit"
  static func gate() throws -> IntakeGate {
    guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else {
      throw CocoaError(.fileNoSuchFile)
    }
    return IntakeGate(root: root)
  }
  static func validateSize(_ url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.uint64Value <= 40 * 1024 * 1024
    else { throw CocoaError(.fileReadTooLarge) }
  }
  static func stage(_ url: URL, generation: UUID, permit: IntakeWritePermit? = nil) throws
    -> IntakeReceipt
  {
    try stage(url, generation: generation, gate: gate(), permit: permit)
  }
  static func stage(
    _ url: URL, generation: UUID, gate: IntakeGate, permit: IntakeWritePermit? = nil
  ) throws -> IntakeReceipt {
    try gate.write(generation: generation) {
      try writeReceipt(
        url, root: gate.root.appendingPathComponent("receipts", isDirectory: true), permit: permit)
    }
  }
  private static func read(_ url: URL, limit: Int, permit: IntakeWritePermit? = nil) throws -> Data
  {
    try permit?.check()
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber, size.uint64Value <= UInt64(limit)
    else { throw CocoaError(.fileReadTooLarge) }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var bytes = Data()
    while let chunk = try file.read(upToCount: min(64 * 1024, limit + 1 - bytes.count)),
      !chunk.isEmpty
    {
      try permit?.check()
      bytes.append(chunk)
      guard bytes.count <= limit else { throw CocoaError(.fileReadTooLarge) }
    }
    return bytes
  }
  private static func writeReceipt(_ url: URL, root: URL, permit: IntakeWritePermit?) throws
    -> IntakeReceipt
  {
    let files = FileManager.default
    let bytes = try read(url, limit: 40 * 1024 * 1024, permit: permit)
    guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    let receipt = IntakeReceipt(
      id: UUID().uuidString, filename: url.lastPathComponent,
      sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      receivedAt: Date())
    try permit?.check()
    try files.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var folder = root.appendingPathComponent(receipt.id + ".partial", isDirectory: true)
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    do {
      // A process may exit after cancellation but before its worker cleans up.
      // Such a copy must not be republished by legacy partial-receipt recovery.
      let marker = folder.appendingPathComponent(providerMarker)
      if permit != nil { try Data().write(to: marker, options: .atomic) }
      var resources = URLResourceValues()
      resources.isExcludedFromBackup = true
      try folder.setResourceValues(resources)
      try permit?.check()
      try JSONEncoder().encode(receipt).write(
        to: folder.appendingPathComponent("receipt.json"), options: .atomic)
      let original = folder.appendingPathComponent("original")
      try bytes.write(to: original, options: .atomic)
      let file = try FileHandle(forWritingTo: original)
      try file.synchronize()
      try file.close()
      let publish: @Sendable () throws -> Void = { [folder] in
        let files = FileManager()
        if permit != nil { try files.removeItem(at: marker) }
        try files.moveItem(
          at: folder, to: root.appendingPathComponent(receipt.id, isDirectory: true))
      }
      if let permit { try permit.publish(publish) } else { try publish() }
    } catch {
      // Cancel removes only this unpublished transfer. Other storage failures
      // retain their partial receipt for the existing recovery path.
      if permit?.discardsUnpublishedFiles == true { try? files.removeItem(at: folder) }
      throw error
    }
    return receipt
  }
  static func pending() throws -> Pending { try pending(gate: gate()) }
  static func pending(gate: IntakeGate) throws -> Pending {
    let state = try gate.snapshot()
    guard !state.erasing else { return Pending(receipts: [], preservedIssues: 0) }
    // Recovery and publication share the same cross-process erasure fence as staging.
    return try gate.write(generation: state.generation) {
      let files = FileManager.default
      let root = gate.root.appendingPathComponent("receipts", isDirectory: true)
      guard files.fileExists(atPath: root.path) else {
        return Pending(receipts: [], preservedIssues: 0)
      }
      let folders = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      var receipts: [(IntakeReceipt, URL, URL)] = []
      var issues = 0
      for source in folders {
        let partial = source.pathExtension == "partial"
        let id =
          partial ? source.deletingPathExtension().lastPathComponent : source.lastPathComponent
        do {
          guard UUID(uuidString: id) != nil,
            (try files.attributesOfItem(atPath: source.path))[.type] as? FileAttributeType
              == .typeDirectory,
            !files.fileExists(atPath: source.appendingPathComponent(providerMarker).path)
          else { throw CocoaError(.fileReadCorruptFile) }
          let receipt = try JSONDecoder().decode(
            IntakeReceipt.self,
            from: read(source.appendingPathComponent("receipt.json"), limit: 64 * 1024))
          let bytes = try read(source.appendingPathComponent("original"), limit: 40 * 1024 * 1024)
          guard receipt.id == id, !bytes.isEmpty,
            SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == receipt.sha256
          else { throw CocoaError(.fileReadCorruptFile) }
          let folder = root.appendingPathComponent(id, isDirectory: true)
          if partial {
            // Never overwrite another original or discard evidence of an incomplete transfer.
            try files.moveItem(at: source, to: folder)
          }
          receipts.append((receipt, folder.appendingPathComponent("original"), folder))
        } catch {
          issues += 1
        }
      }
      return Pending(
        receipts: receipts.sorted { $0.0.receivedAt < $1.0.receivedAt }, preservedIssues: issues)
    }
  }
}
