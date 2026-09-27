import Foundation

/// Provider-independent outcomes. Only a finalized result may become a command.
enum RecognitionCompletion: Equatable, Sendable {
  case finalized(String)
  case noSpeech, cancelled
  case failed(RecognitionFailure)
}

enum RecognitionFailure: String, Error, Sendable {
  case unavailable, assetsMissing, assetSetupFailed, unsupportedLocale, invalidAudio, overflow
  case noProgress, finalizationTimeout, interrupted, incomplete

  var message: String {
    switch self {
    case .noProgress:
      "Sprache ist hörbar, aber die Spracherkennung liefert noch keinen Text. Bitte erneut sprechen."
    case .finalizationTimeout, .incomplete:
      "Die Spracherkennung konnte den Satz nicht abschließen. Bitte den Satz erneut sprechen."
    case .assetsMissing, .assetSetupFailed:
      "Die deutsche Spracherkennung muss zuerst auf diesem iPhone eingerichtet werden. Bitte mit dem Internet verbinden und das Gespräch erneut starten. Danach funktioniert sie offline."
    case .unavailable, .unsupportedLocale:
      "Die lokale deutsche Spracherkennung ist noch nicht bereit. Deutsch für die Diktierfunktion aktivieren."
    case .overflow, .invalidAudio:
      "Die Mikrofondaten konnten nicht vollständig verarbeitet werden. Bitte erneut sprechen."
    case .interrupted:
      "Die Spracherkennung wurde unterbrochen. Bitte den Satz erneut sprechen."
    }
  }

  /// Stable categories only; never log arbitrary provider text or transcripts.
  var diagnosticCode: Int {
    switch self {
    case .unavailable: 1
    case .assetsMissing: 2
    case .unsupportedLocale: 3
    case .invalidAudio: 4
    case .overflow: 5
    case .noProgress: 6
    case .finalizationTimeout: 7
    case .interrupted: 8
    case .incomplete: 9
    case .assetSetupFailed: 10
    }
  }
}

struct RecognitionUpdate: Sendable {
  let text: String
  let stableText: String
  let audioStart: Double
  let audioEnd: Double
  let receivedAt: Double
  let isFinal: Bool
}

enum RecognitionEvent: Sendable {
  case result(RecognitionUpdate)
  case completed(RecognitionCompletion)
}

/// A stalled recognizer is distinct from an idle microphone or a natural pause.
/// Only changed words/numbers are progress. Repeated snapshots and punctuation
/// revisions cannot keep a finished question open in background noise.
struct RecognitionProgress {
  private(set) var voicedFrames = 0
  private var lastProgress: Double?
  private var firstVoice: Double?
  private var lastWords = ""
  mutating func voice(at time: Double) {
    voicedFrames += 1
    if firstVoice == nil { firstVoice = time }
  }
  mutating func result(text: String, at time: Double) {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    guard !words.isEmpty, words != lastWords else { return }
    lastWords = words
    lastProgress = time
  }
  /// Backup for noise classified as sustained speech. Drain the recognizer,
  /// then accept only its finalized outcome; never promote a partial snapshot.
  func shouldFinalize(at time: Double) -> Bool {
    guard let lastProgress else { return false }
    return time - lastProgress >= 4
  }
  func stalled(at time: Double) -> Bool {
    guard voicedFrames >= 25, let since = lastProgress ?? firstVoice else { return false }
    return time - since >= 12
  }
}

/// Final ranges are append-only. Provisional revisions replace provisional text,
/// never promote it on timeout, a route change, or cancellation.
struct RecognitionTranscript {
  private(set) var stable = ""
  private(set) var provisional = ""
  private var stableEnd = 0.0
  var text: String { Self.join(stable, provisional) }
  mutating func receive(_ text: String, start: Double, end: Double, final: Bool) throws {
    guard start.isFinite, end.isFinite, start >= 0, end >= start,
      start + 0.001 >= stableEnd
    else { throw RecognitionFailure.incomplete }
    if final {
      stable = Self.join(stable, text)
      stableEnd = end
      provisional = ""
    } else {
      provisional = text
    }
  }
  var completion: RecognitionCompletion {
    guard provisional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failed(.incomplete)
    }
    return stable.isEmpty ? .noSpeech : .finalized(stable)
  }
  static func join(_ first: String, _ second: String) -> String {
    [first, second].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }.joined(separator: " ")
  }
}
