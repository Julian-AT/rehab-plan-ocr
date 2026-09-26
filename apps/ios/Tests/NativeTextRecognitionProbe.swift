import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

@main struct NativeTextRecognitionProbe {
  static func fixture() -> Data {
    let context = CGContext(
      data: nil, width: 800, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
    let text = NSAttributedString(
      string: "Raum 204",
      attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String):
          CTFontCreateWithName("Helvetica" as CFString, 64, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 0, alpha: 1),
      ])
    context.textPosition = CGPoint(x: 40, y: 90)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }

  /// Previous production mapping, kept here as an independent differential oracle.
  static func previousResult(_ data: Data) throws -> [String: Any] {
    let image = CGImageSourceCreateImageAtIndex(
      CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["de-DE", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    var regions: [[String: Any]] = []
    var observations: [[String: Any]] = []
    for (index, observation) in (request.results ?? []).enumerated() {
      let candidates = observation.topCandidates(3)
      let bounds = observation.boundingBox
      let x = bounds.minX * Double(image.width)
      let y = (1 - bounds.maxY) * Double(image.height)
      let w = bounds.width * Double(image.width)
      let h = bounds.height * Double(image.height)
      let id = String(format: "region-%04d", index)
      regions.append([
        "id": id,
        "polygon": [
          ["x": x, "y": y], ["x": x + w, "y": y],
          ["x": x + w, "y": y + h], ["x": x, "y": y + h],
        ],
        "frame": "page", "kind": "text", "parent": "page", "children": [],
      ])
      observations.append([
        "id": "obs-\(id)", "text": candidates.first?.string ?? "", "region_ids": [id],
        "engine": "Apple Vision", "score": candidates.first?.confidence ?? 0,
        "alternatives": candidates.dropFirst().map(\.string),
      ])
    }
    return [
      "regions": regions, "observations": observations,
      "manifest": [
        "engine": "Apple Vision", "revision": request.revision,
        "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
        "language_correction": false,
      ],
    ]
  }

  static func rejects(_ input: NativeTextRecognitionRequest, timeout: Bool = false) async {
    do {
      let _: NativeTextRecognitionResult = try await withCheckedThrowingContinuation { done in
        NativeTextRecognition.recognize(input) { done.resume(with: $0) }
      }
      preconditionFailure("Invalid recognition input was accepted")
    } catch NativeServiceError.timeout("recognize") {
      precondition(timeout)
    } catch NativeServiceError.invalidInput {
      precondition(!timeout)
    } catch { preconditionFailure("Wrong recognition error: \(error)") }
  }

  static func main() async throws {
    let data = fixture()
    let input = NativeTextRecognitionRequest(image: data, budgetMs: 60_000)
    let result: NativeTextRecognitionResult = try await withCheckedThrowingContinuation { done in
      NativeTextRecognition.recognize(input) { done.resume(with: $0) }
    }
    precondition(result.observations.map(\.text) == ["Raum 204"])
    precondition(result.durationMs < 60_000)
    var actual = try result.legacyValue
    actual.removeValue(forKey: "duration_ms")
    // Both Vision calls run on worker threads; only the test assertion crosses back.
    let matched = try await Task.detached {
      let reference = try previousResult(data)
      let native = try NativeTextRecognition.perform(
        input, started: .now, deadline: .now.advanced(by: .seconds(60)))
      var encoded = try native.legacyValue
      encoded.removeValue(forKey: "duration_ms")
      return NSDictionary(dictionary: reference).isEqual(to: encoded)
    }.value
    precondition(matched, "Typed output changed the existing geometry/text/provenance mapping")
    precondition(actual["manifest"] != nil && actual["regions"] != nil)
    await rejects(.init(image: Data(), budgetMs: 60_000))
    await rejects(.init(image: Data("broken image".utf8), budgetMs: 60_000))
    await rejects(.init(image: data, budgetMs: 0), timeout: true)
    await rejects(.init(image: data, budgetMs: 60_001))
    await rejects(
      .init(
        image: Data(repeating: 0, count: NativeTextRecognitionRequest.maximumBytes + 1),
        budgetMs: 60_000))
    var oversized = data
    let width = UInt32(NativePhoto.maximumPixels + 1)
    for index in 0..<4 {
      oversized[16 + index] = UInt8(truncatingIfNeeded: width >> ((3 - index) * 8))
      oversized[20 + index] = index == 3 ? 1 : 0
    }
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in oversized[12..<29] {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
    }
    crc ^= 0xFFFF_FFFF
    for index in 0..<4 {
      oversized[29 + index] = UInt8(truncatingIfNeeded: crc >> ((3 - index) * 8))
    }
    await rejects(.init(image: oversized, budgetMs: 60_000))
    do {
      _ = try NativeTextRecognition.perform(input, started: .now, deadline: .now)
      preconditionFailure("Expired queued work must not reach Vision")
    } catch NativeServiceError.timeout("recognize") {}
    print(
      "Native Vision: actual text, legacy geometry/alternatives/provenance, byte/pixel bounds and expired work passed"
    )
  }
}
