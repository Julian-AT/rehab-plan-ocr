import Foundation
import ImageIO
import Vision

/// Local comparison only: one complete Vision request, never an extra pass in the app.
@main struct DocumentProbe {
  static func main() async throws {
    guard CommandLine.arguments.count == 4 else {
      throw CocoaError(.fileReadInvalidFileName)
    }
    let mode = CommandLine.arguments[1]
    let input = URL(fileURLWithPath: CommandLine.arguments[2])
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    let started = ContinuousClock.now
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw CocoaError(.fileReadCorruptFile) }
    let width = Double(image.width)
    let height = Double(image.height)
    var regions: [[String: Any]] = []
    var observations: [[String: Any]] = []
    var tables: [[String: Any]] = []
    var seen = Set<UUID>()
    func point(_ p: NormalizedPoint) -> [String: Double] {
      ["x": p.cgPoint.x * width, "y": (1 - p.cgPoint.y) * height]
    }
    func region(_ r: NormalizedRegion) -> [[String: Double]] {
      let rect = r.normalizedPath.boundingBoxOfPath
      return [
        ["x": rect.minX * width, "y": (1 - rect.maxY) * height],
        ["x": rect.maxX * width, "y": (1 - rect.maxY) * height],
        ["x": rect.maxX * width, "y": (1 - rect.minY) * height],
        ["x": rect.minX * width, "y": (1 - rect.minY) * height],
      ]
    }
    func record(_ line: RecognizedTextObservation) -> String {
      let id = line.uuid.uuidString
      if seen.insert(line.uuid).inserted {
        regions.append([
          "id": id, "kind": "text", "frame": "page", "parent": "page",
          "children": [],
          "polygon": [
            point(line.topLeft), point(line.topRight),
            point(line.bottomRight), point(line.bottomLeft),
          ],
        ])
        let candidates = line.topCandidates(3)
        observations.append([
          "id": "obs-" + id, "text": line.transcript,
          "region_ids": [id], "engine": "Apple Vision " + mode,
          "score": line.confidence, "alternatives": candidates.dropFirst().map(\.string),
        ])
      }
      return id
    }
    let data: Data
    if mode == "documents" {
      var request = RecognizeDocumentsRequest()
      request.textRecognitionOptions.recognitionLanguages = [
        Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US"),
      ]
      request.textRecognitionOptions.automaticallyDetectLanguage = false
      request.textRecognitionOptions.useLanguageCorrection = false
      request.textRecognitionOptions.maximumCandidateCount = 3
      request.barcodeDetectionOptions.enabled = false
      for document in try await request.perform(on: image) {
        for line in document.document.text.lines { _ = record(line) }
        for table in document.document.tables {
          var cells: [[String: Any]] = []
          var cellsSeen = Set<String>()
          for row in table.rows {
            for cell in row {
              let key = "\(cell.rowRange):\(cell.columnRange)"
              guard cellsSeen.insert(key).inserted else { continue }
              cells.append([
                "row": cell.rowRange.lowerBound, "column": cell.columnRange.lowerBound,
                "row_span": cell.rowRange.count, "column_span": cell.columnRange.count,
                "region_ids": cell.content.text.lines.map(record),
                "text": cell.content.text.transcript,
                "polygon": region(cell.content.boundingRegion),
              ])
            }
          }
          tables.append(["cells": cells, "polygon": region(table.boundingRegion)])
        }
      }
    } else if mode == "text" {
      var request = RecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = [
        Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US"),
      ]
      request.usesLanguageCorrection = false
      for line in try await request.perform(on: image) { _ = record(line) }
    } else {
      throw CocoaError(.coderInvalidValue)
    }
    data = try JSONSerialization.data(
      withJSONObject: [
        "regions": regions, "observations": observations, "tables": tables,
        "width": width, "height": height,
        "manifest": [
          "engine": "Apple Vision " + mode,
          "system": ProcessInfo.processInfo.operatingSystemVersionString,
          "language_correction": false,
        ],
      ], options: [.sortedKeys])
    try data.write(to: output, options: .atomic)
    let elapsed = started.duration(to: .now).components
    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    let report: [String: Any] = [
      "mode": mode, "wall_ms": seconds * 1000,
      "system": ProcessInfo.processInfo.operatingSystemVersionString,
      "language_correction": false, "additional_pass": false,
      "physical_iphone_measurement": false,
    ]
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report))
    print()
  }
}
