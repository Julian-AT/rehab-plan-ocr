import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Each invocation owns its image and Vision request. Only cancellation crosses
/// the worker boundary; UI and EventKit never participate in recognition.
public enum NativeTextRecognition {
  public static func recognize(
    _ input: NativeTextRecognitionRequest,
    completion: @escaping @Sendable (Result<NativeTextRecognitionResult, Error>) -> Void
  ) {
    let started = ContinuousClock.now
    do { try input.validate() } catch {
      completion(.failure(error))
      return
    }
    let deadline = started.advanced(by: .milliseconds(Int64(input.budgetMs)))
    DispatchQueue.global(qos: .userInitiated).async {
      completion(Result { try perform(input, started: started, deadline: deadline) })
    }
  }

  static func perform(
    _ input: NativeTextRecognitionRequest, started: ContinuousClock.Instant,
    deadline: ContinuousClock.Instant
  ) throws -> NativeTextRecognitionResult {
    try input.validate()
    func checkDeadline() throws {
      guard ContinuousClock.now < deadline else { throw NativeServiceError.timeout("recognize") }
    }
    try checkDeadline()
    guard
      let source = CGImageSourceCreateWithData(
        input.image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { throw NativeServiceError.invalidInput("Bild für Vision nicht lesbar.") }
    // Prepared PNGs are already upright. Preserve their page coordinate frame.
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= NativePhoto.maximumPixels / height
    else { throw NativeServiceError.invalidInput("Bild für Vision nicht lesbar oder zu groß.") }
    try checkDeadline()
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw NativeServiceError.invalidInput("Bild für Vision konnte nicht dekodiert werden.")
    }
    try checkDeadline()
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["de-DE", "en-US"]
    request.usesLanguageCorrection = false
    // A cancelled timer must not retain a completed request until its old deadline.
    let timeout = DispatchWorkItem { [weak request] in request?.cancel() }
    let remaining = ContinuousClock.now.duration(to: deadline).components
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + max(0, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18),
      execute: timeout)
    defer { timeout.cancel() }
    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch {
      try checkDeadline()
      throw NativeServiceError.storage("Lokale Vision-Erkennung fehlgeschlagen.")
    }
    try checkDeadline()
    var regions: [NativeRecognitionRegion] = []
    var observations: [NativeRecognitionObservation] = []
    for (index, observation) in (request.results ?? []).enumerated() {
      let candidates = observation.topCandidates(3)
      let bounds = observation.boundingBox
      let x = bounds.minX * Double(image.width)
      let y = (1 - bounds.maxY) * Double(image.height)
      let w = bounds.width * Double(image.width)
      let h = bounds.height * Double(image.height)
      let id = String(format: "region-%04d", index)
      regions.append(
        NativeRecognitionRegion(
          id: id,
          polygon: [
            .init(x: x, y: y), .init(x: x + w, y: y),
            .init(x: x + w, y: y + h), .init(x: x, y: y + h),
          ],
          frame: "page", kind: "text", parent: "page", children: []))
      observations.append(
        NativeRecognitionObservation(
          id: "obs-\(id)", text: candidates.first?.string ?? "", regionIDs: [id],
          engine: "Apple Vision", score: candidates.first?.confidence ?? 0,
          alternatives: candidates.dropFirst().map(\.string)))
    }
    try checkDeadline()
    let duration = started.duration(to: .now).components
    return NativeTextRecognitionResult(
      regions: regions, observations: observations,
      durationMs: UInt64(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000),
      identity: NativeRecognitionIdentity(
        engine: "Apple Vision", revision: UInt64(request.revision),
        systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        languageCorrection: false))
  }
}
