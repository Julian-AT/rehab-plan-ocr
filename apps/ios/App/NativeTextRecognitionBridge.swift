import AppleServices
import Foundation
import RehaCore

extension NativeBridge {
  func recognizeText(request: TextRecognitionRequest) throws -> TextRecognitionResult {
    precondition(!Thread.isMainThread, "Text recognition belongs to the Rust worker")
    do {
      let input = NativeTextRecognitionRequest(image: request.image, budgetMs: request.budgetMs)
      try input.validate()
      let result = try NativeServiceCall.waitValue(
        for: .recognize, timeout: Double(input.budgetMs) / 1000
      ) { completion in
        NativeServices.shared.recognizeText(input, completion: completion)
      }
      return TextRecognitionResult(
        regions: result.regions.map { region in
          Region(
            id: region.id, polygon: region.polygon.map { Point(x: $0.x, y: $0.y) },
            frame: region.frame, kind: region.kind, parent: region.parent, children: region.children
          )
        },
        observations: result.observations.map { observation in
          OcrObservation(
            id: observation.id, text: observation.text, regionIds: observation.regionIDs,
            engine: observation.engine, score: observation.score,
            alternatives: observation.alternatives)
        },
        durationMs: result.durationMs,
        identity: TextRecognitionIdentity(
          engine: result.identity.engine, revision: result.identity.revision,
          systemVersion: result.identity.systemVersion,
          languageCorrection: result.identity.languageCorrection))
    } catch { throw Self.appError(error) }
  }
}
