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
  static func stage(_ url: URL, generation: UUID) throws -> IntakeReceipt {
    try stage(url, generation: generation, gate: gate())
  }
  static func stage(_ url: URL, generation: UUID, gate: IntakeGate) throws -> IntakeReceipt {
    try gate.write(generation: generation) {
      try writeReceipt(url, root: gate.root.appendingPathComponent("receipts", isDirectory: true))
    }
  }
  private static func read(_ url: URL, limit: Int) throws -> Data {
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
      bytes.append(chunk)
      guard bytes.count <= limit else { throw CocoaError(.fileReadTooLarge) }
    }
    return bytes
  }
  private static func writeReceipt(_ url: URL, root: URL) throws -> IntakeReceipt {
    let files = FileManager.default
    let bytes = try read(url, limit: 40 * 1024 * 1024)
    guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    let receipt = IntakeReceipt(
      id: UUID().uuidString, filename: url.lastPathComponent,
      sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      receivedAt: Date())
    try files.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var folder = root.appendingPathComponent(receipt.id + ".partial", isDirectory: true)
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try folder.setResourceValues(resources)
    try JSONEncoder().encode(receipt).write(
      to: folder.appendingPathComponent("receipt.json"), options: .atomic)
    let original = folder.appendingPathComponent("original")
    try bytes.write(to: original, options: .atomic)
    let file = try FileHandle(forWritingTo: original)
    try file.synchronize()
    try file.close()
    try files.moveItem(at: folder, to: root.appendingPathComponent(receipt.id, isDirectory: true))
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
              == .typeDirectory
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
