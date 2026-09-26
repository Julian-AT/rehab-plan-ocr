import Foundation

/// Immutable mono 24 kHz speech crosses the renderer/playback actor boundary.
struct SpeechPCM: Sendable {
  static let sampleRate = 24_000
  static let maximumFrames = sampleRate * 300
  let samples: [Float]
}

enum SpeechPCMError: LocalizedError {
  case invalidFile
  var errorDescription: String? { "Die Sprachaufnahme ist ungültig." }
}
