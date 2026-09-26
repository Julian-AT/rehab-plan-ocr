import Foundation

enum RecognitionAssetStatus: Int, Sendable {
  case unsupported = 0
  case supported, downloading, installed
}

enum RecognitionPreparation: Sendable {
  case assets(RecognitionAssetStatus)
  case installing(Bool)
}

/// Separate setup from capture: only the first preparation, while the microphone
/// is stopped, may install Apple's public language assets. No audio is uploaded.
@MainActor protocol RecognitionAssets {
  func status() async -> RecognitionAssetStatus
  func reserve() async throws
  func install() async throws
}

@MainActor enum SpeechAssetReadiness {
  static func ensure(
    _ assets: any RecognitionAssets, allowInstallation: Bool,
    observe: (RecognitionPreparation) -> Void
  ) async throws -> Bool {
    try Task.checkCancellation()
    let status = await assets.status()
    try Task.checkCancellation()
    observe(.assets(status))
    guard status != .unsupported else { return false }
    guard status == .installed || allowInstallation else {
      throw RecognitionFailure.assetsMissing
    }
    do {
      try await assets.reserve()
      try Task.checkCancellation()
      if status != .installed {
        observe(.installing(true))
        try await assets.install()
        try Task.checkCancellation()
        let installed = await assets.status()
        try Task.checkCancellation()
        observe(.assets(installed))
        guard installed == .installed else { throw RecognitionFailure.assetSetupFailed }
        observe(.installing(false))
      }
      return true
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      throw RecognitionFailure.assetSetupFailed
    }
  }
}
