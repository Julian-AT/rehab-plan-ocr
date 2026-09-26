import Foundation
import Speech

/// Read-only preflight. It never requests microphone access or downloads assets.
@main struct AvailabilityProbe {
  static func main() async throws {
    let installed = await SpeechTranscriber.installedLocales
    let supported = await SpeechTranscriber.supportedLocales
    var locales: [[String: Any]] = []
    for identifier in ["de-AT", "de-DE"] {
      let locale = Locale(identifier: identifier)
      let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
      let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
      let status = await AssetInventory.status(forModules: [transcriber])
      locales.append([
        "requested": identifier, "equivalent": equivalent?.identifier ?? "",
        "asset_status": String(describing: status),
        "exact_locale_installed": installed.contains {
          $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            == identifier.lowercased()
        },
        "offline_eligible": SpeechTranscriber.isAvailable && status == .installed,
      ])
    }
    let output: [String: Any] = [
      "system": ProcessInfo.processInfo.operatingSystemVersionString,
      "transcriber_available": SpeechTranscriber.isAvailable,
      "installed": installed.map(\.identifier), "supported": supported.map(\.identifier),
      "locales": locales, "download_requested": false, "microphone_tested": false,
    ]
    FileHandle.standardOutput.write(
      try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]))
    print()
  }
}
