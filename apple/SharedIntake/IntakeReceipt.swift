import Foundation
import CryptoKit

struct IntakeReceipt: Codable, Sendable {
    let id: String
    let filename: String
    let sha256: String
    let receivedAt: Date
}
enum IntakeStaging {
    static let group = "group.at.rehakalender.personal.intake"
    static func root() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return root.appendingPathComponent("receipts", isDirectory: true)
    }
    static func stage(_ url: URL) throws -> IntakeReceipt {
        let files = FileManager.default
        guard let size = (try files.attributesOfItem(atPath: url.path))[.size] as? NSNumber,
              size.uint64Value <= 40*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
        let bytes = try Data(contentsOf: url)
        let receipt = IntakeReceipt(id:UUID().uuidString,filename:url.lastPathComponent,sha256:SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),receivedAt:Date())
        let root = try root()
        try files.createDirectory(at: root,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = root.appendingPathComponent(receipt.id + ".partial",isDirectory:true)
        try files.createDirectory(at:folder,withIntermediateDirectories:true)
        var resources = URLResourceValues(); resources.isExcludedFromBackup=true; try folder.setResourceValues(resources)
        try JSONEncoder().encode(receipt).write(to:folder.appendingPathComponent("receipt.json"),options:.atomic)
        let original = folder.appendingPathComponent("original")
        try bytes.write(to:original,options:.atomic)
        let file = try FileHandle(forWritingTo: original); try file.synchronize(); try file.close()
        try files.moveItem(at:folder,to:root.appendingPathComponent(receipt.id,isDirectory:true))
        return receipt
    }
    static func pending() throws -> [(IntakeReceipt, URL, URL)] {
        let root = try root()
        let folders = (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf:folder.appendingPathComponent("receipt.json")),
                  let receipt = try? JSONDecoder().decode(IntakeReceipt.self,from:data), UUID(uuidString:receipt.id) != nil,
                  let bytes = try? Data(contentsOf:folder.appendingPathComponent("original")),
                  SHA256.hash(data:bytes).map({ String(format:"%02x",$0) }).joined() == receipt.sha256 else { return nil }
            return (receipt,folder.appendingPathComponent("original"),folder)
        }.sorted { $0.0.receivedAt < $1.0.receivedAt }
    }
}
