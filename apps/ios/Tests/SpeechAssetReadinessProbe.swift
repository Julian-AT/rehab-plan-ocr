import Foundation

@MainActor private final class Assets: RecognitionAssets {
  var state: RecognitionAssetStatus
  var reserves = 0
  var installs = 0
  var fails = false
  var remainMissing = false
  var suspend = false
  var continuation: CheckedContinuation<Void, Never>?
  init(_ state: RecognitionAssetStatus) { self.state = state }
  func status() async -> RecognitionAssetStatus { state }
  func reserve() async throws { reserves += 1 }
  func install() async throws {
    installs += 1
    if fails { throw CocoaError(.fileReadUnknown) }
    if suspend { await withCheckedContinuation { continuation = $0 } }
    if !remainMissing { state = .installed }
  }
}

@main struct SpeechAssetReadinessProbe {
  @MainActor static func main() async throws {
    let installed = Assets(.installed)
    let ready = try await SpeechAssetReadiness.ensure(
      installed, allowInstallation: false, observe: { _ in })
    precondition(ready && installed.reserves == 1 && installed.installs == 0)

    for state: RecognitionAssetStatus in [.supported, .downloading] {
      let missing = Assets(state)
      do {
        _ = try await SpeechAssetReadiness.ensure(
          missing, allowInstallation: false, observe: { _ in })
        preconditionFailure("Active capture downloaded assets or silently fell back")
      } catch RecognitionFailure.assetsMissing {}
      precondition(missing.reserves == 0 && missing.installs == 0)
      var completed = false
      let prepared = try await SpeechAssetReadiness.ensure(
        missing, allowInstallation: true,
        observe: { if case .installing(false) = $0 { completed = true } })
      precondition(prepared && missing.reserves == 1 && missing.installs == 1 && completed)
    }

    let unsupported = Assets(.unsupported)
    let fallback = try await SpeechAssetReadiness.ensure(
      unsupported, allowInstallation: true, observe: { _ in })
    precondition(!fallback && unsupported.reserves == 0 && unsupported.installs == 0)

    for staysMissing in [false, true] {
      let broken = Assets(.supported)
      broken.fails = !staysMissing
      broken.remainMissing = staysMissing
      var completed = false
      do {
        _ = try await SpeechAssetReadiness.ensure(
          broken, allowInstallation: true,
          observe: { if case .installing(false) = $0 { completed = true } })
        preconditionFailure("Failed setup became ready")
      } catch RecognitionFailure.assetSetupFailed {}
      precondition(!completed)
    }

    // A system download may finish after Stop. Its late completion must never
    // start the microphone or select a provider for an obsolete turn.
    let late = Assets(.supported)
    late.suspend = true
    var completed = false
    let task = Task {
      try await SpeechAssetReadiness.ensure(
        late, allowInstallation: true,
        observe: { if case .installing(false) = $0 { completed = true } })
    }
    while late.continuation == nil { await Task.yield() }
    task.cancel()
    late.continuation?.resume()
    do {
      _ = try await task.value
      preconditionFailure("Cancelled setup became ready")
    } catch is CancellationError {}
    precondition(!completed)
    print(
      "Speech setup: installed, missing, downloading, unsupported, failed, uninstalled after request, and late cancellation passed"
    )
  }
}
