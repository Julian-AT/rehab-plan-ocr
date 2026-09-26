import Foundation

enum AppStorage {
  static func prepare() throws -> URL {
    guard let identifier = Bundle.main.bundleIdentifier else {
      throw CocoaError(.fileNoSuchFile)
    }
    let files = FileManager.default
    let support = try files.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    var root = support.appendingPathComponent(identifier, isDirectory: true)
    // Resolve storage through iOS: HOME and NSHomeDirectory can use different
    // /private/var aliases, particularly before this directory exists.
    try files.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    try files.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: root.path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try root.setResourceValues(values)
    return root
  }
}
