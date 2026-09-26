import Foundation

/// Upright encoded page/crop from the common photo pipeline, without a Base64 copy.
public struct NativeTextRecognitionRequest: Sendable {
  public let image: Data
  public let budgetMs: UInt64
  public init(image: Data, budgetMs: UInt64) {
    self.image = image
    self.budgetMs = budgetMs
  }
  // A prepared 50MP RGB PNG may exceed the original-photo 40MiB intake limit.
  static let maximumBytes = 256 * 1024 * 1024
  static let maximumBudgetMs: UInt64 = 60_000
  public func validate() throws {
    guard !image.isEmpty, image.count <= Self.maximumBytes else {
      throw NativeServiceError.invalidInput("Bild für Vision fehlt oder ist zu groß.")
    }
    guard budgetMs > 0 else { throw NativeServiceError.timeout("recognize") }
    guard budgetMs <= Self.maximumBudgetMs else {
      throw NativeServiceError.invalidInput("Zeitbudget ungültig.")
    }
  }
}

public struct NativeRecognitionPoint: Sendable, Encodable {
  public let x: Double
  public let y: Double
}
public struct NativeRecognitionRegion: Sendable, Encodable {
  public let id: String
  public let polygon: [NativeRecognitionPoint]
  public let frame: String
  public let kind: String
  public let parent: String
  public let children: [String]
}
public struct NativeRecognitionObservation: Sendable, Encodable {
  public let id: String
  public let text: String
  public let regionIDs: [String]
  public let engine: String
  public let score: Float
  public let alternatives: [String]
  enum CodingKeys: String, CodingKey {
    case id, text, engine, score, alternatives
    case regionIDs = "region_ids"
  }
}
public struct NativeRecognitionIdentity: Sendable, Encodable {
  public let engine: String
  public let revision: UInt64
  public let systemVersion: String
  public let languageCorrection: Bool
  enum CodingKeys: String, CodingKey {
    case engine, revision
    case systemVersion = "system_version"
    case languageCorrection = "language_correction"
  }
}
public struct NativeTextRecognitionResult: Sendable, Encodable {
  public let regions: [NativeRecognitionRegion]
  public let observations: [NativeRecognitionObservation]
  public let durationMs: UInt64
  public let identity: NativeRecognitionIdentity
  // Encoding is confined to the old service adapter and persisted provenance.
  enum CodingKeys: String, CodingKey {
    case regions, observations
    case durationMs = "duration_ms"
    case identity = "manifest"
  }
  var legacyValue: [String: Any] {
    get throws {
      guard
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
          as? [String: Any]
      else { throw NativeServiceError.storage("Ungültige Erkennungsantwort.") }
      return value
    }
  }
}
