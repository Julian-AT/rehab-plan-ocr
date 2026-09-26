import XCTest

final class AppStorageTests: XCTestCase {
  func testStorageProtectionAndRepeatedPreparationPreserveFiles() throws {
    let root = try AppStorage.prepare()
    let file = root.appendingPathComponent("storage-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    let content = Data("storage regression fixture".utf8)
    try content.write(to: file)

    XCTAssertEqual(try AppStorage.prepare(), root)
    XCTAssertEqual(try Data(contentsOf: file), content)
    XCTAssertEqual(
      try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    // The old Rust path must still point at the same data after an app update.
    let previous = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["HOME"]))
      .appendingPathComponent("Library/Application Support")
      .appendingPathComponent(try XCTUnwrap(Bundle.main.bundleIdentifier))
      .appendingPathComponent(file.lastPathComponent)
    XCTAssertEqual(try Data(contentsOf: previous), content)
  }

  func testDeviceFileProtection() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("The simulator does not expose iOS file-protection attributes.")
    #else
      let root = try AppStorage.prepare()
      let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
      XCTAssertEqual(
        attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
    #endif
  }
}
