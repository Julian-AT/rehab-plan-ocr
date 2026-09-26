import Foundation

struct RecognitionTrace: Decodable, Sendable {
  struct Point: Decodable, Sendable {
    let x: Double
    let y: Double
  }
  struct Region: Decodable, Identifiable, Sendable {
    let id: String
    let polygon: [Point]
    let frame: String
    let kind: String
    var isText: Bool { kind == "text" || kind == "uncertain_text" }
  }
  struct Observation: Decodable, Identifiable, Sendable {
    let id: String
    let text: String
    let regionIds: [String]
    let engine: String
    let score: Double?
  }
  struct Stage: Decodable, Sendable {
    let name: String
    let status: String
    let durationMs: UInt64
    let detail: String
    let artifacts: [String]
  }
  struct Attempt: Decodable, Identifiable, Sendable {
    let id: String
    let reason: String
    let variant: String
    let cropToPage: [Double]
    let width: Double
    let height: Double
    let status: String
    let detail: String
    let observationIds: [String]
    var polygon: [Point] {
      guard cropToPage.count == 9 else { return [] }
      return [(0.0, 0.0), (width, 0), (width, height), (0, height)].compactMap { x, y in
        let divisor = cropToPage[6] * x + cropToPage[7] * y + cropToPage[8]
        guard abs(divisor) > 0.000_001 else { return nil }
        let px = (cropToPage[0] * x + cropToPage[1] * y + cropToPage[2]) / divisor
        let py = (cropToPage[3] * x + cropToPage[4] * y + cropToPage[5]) / divisor
        return px.isFinite && py.isFinite ? Point(x: px, y: py) : nil
      }
    }
  }
  struct Field: Decodable, Sendable {
    let polygon: [Point]
    let frame: String
    let state: String
    let reasons: [String]
  }
  struct Appointment: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: String?
    let start: String?
    let end: String?
    let durationMinutes: UInt32?
    let location: String
    let therapist: String
    let notes: String
    let fields: [String: Field]
    let provenance: [String: [String]]
    func value(for field: String) -> String? {
      switch field {
      case "title": title
      case "date": date
      case "start": start
      case "end": end
      case "duration_minutes": durationMinutes.map { "\($0) Minuten" }
      case "location": location
      case "therapist": therapist
      case "notes": notes
      default: nil
      }
    }
  }
  struct Issue: Decodable, Identifiable, Sendable {
    let id = UUID()
    let code: String
    let message: String
    let blocking: Bool
    private enum CodingKeys: String, CodingKey { case code, message, blocking }
  }
  struct Step: Identifiable, Sendable {
    let id: String
    let stage: Stage
    var title: String {
      switch stage.name {
      case "decode": "Original lesen"
      case "preprocessing": "Bild aufbereiten"
      case "quality": "Bildqualität prüfen"
      case "model_load": "Modelle laden"
      case "detection": "Textbereiche finden"
      case "recognition": "Text erkennen"
      case "layout_and_fields": "Zeilen und Felder zuordnen"
      case "validation": "Termine prüfen"
      case "selective_reread": "Unklare Ausschnitte nachlesen"
      case "refinement": "Felder nachprüfen"
      default: stage.name.replacingOccurrences(of: "_", with: " ")
      }
    }
    var original: Bool { stage.name == "decode" }
    var reread: Bool { stage.name.contains("reread") || stage.name.contains("refin") }
    var layout: Bool { stage.name == "layout_and_fields" || stage.name == "validation" }
  }
  struct Document: Decodable, Sendable { let id: String }
  let document: Document
  let id: String
  let engine: String
  let stages: [Stage]
  let regions: [Region]
  let observations: [Observation]
  let appointments: [Appointment]
  let refinementAttempts: [Attempt]
  let issues: [Issue]
  let pageWidth: Double
  let pageHeight: Double
  let totalMs: UInt64
  var steps: [Step] {
    var occurrences: [String: Int] = [:]
    return stages.map { stage in
      let occurrence = occurrences[stage.name, default: 0]
      occurrences[stage.name] = occurrence + 1
      return Step(id: "\(id)-\(stage.name)-\(occurrence)", stage: stage)
    }
  }
  var initialObservations: [Observation] {
    let reread = Set(refinementAttempts.flatMap(\.observationIds))
    return observations.filter { !reread.contains($0.id) }
  }
  func polygons(for observation: Observation) -> [[Point]] {
    regions.filter { observation.regionIds.contains($0.id) && $0.frame == "page" }.map(\.polygon)
  }
  func polygons(for step: Step) -> [[Point]] {
    if step.reread { return refinementAttempts.map(\.polygon) }
    if step.layout {
      return regions.filter { $0.frame == "page" && !$0.isText }.map(\.polygon)
    }
    if step.stage.name == "detection" {
      let rereadIDs = Set(refinementAttempts.flatMap(\.observationIds))
      let rereadRegions = Set(
        observations.filter { rereadIDs.contains($0.id) }.flatMap(\.regionIds))
      return regions.filter {
        $0.frame == "page" && $0.isText && !rereadRegions.contains($0.id)
      }.map(\.polygon)
    }
    if step.stage.name == "recognition" { return initialObservations.flatMap { polygons(for: $0) } }
    return []
  }
  static func decode(_ json: String) throws -> Self {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Self.self, from: Data(json.utf8))
  }
}
