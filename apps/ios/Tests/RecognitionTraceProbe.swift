import Foundation

@main struct RecognitionTraceProbe {
  static func main() throws {
    // The public fixture predates optional refinement/field evidence. Supply
    // the defaults that the Rust serde reader emits when loading it today.
    let data = try Data(contentsOf: URL(fileURLWithPath: "ml/evaluation/fixtures/sample-run.json"))
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json["refinement_attempts"] = []
    var appointments = json["appointments"] as! [[String: Any]]
    for index in appointments.indices { appointments[index]["fields"] = [:] }
    json["appointments"] = appointments
    func decode() throws -> RecognitionTrace {
      let bytes = try JSONSerialization.data(withJSONObject: json)
      return try RecognitionTrace.decode(String(decoding: bytes, as: UTF8.self))
    }
    let trace = try decode()
    precondition(trace.document.id != trace.id)
    precondition(trace.appointments.count == 8)
    precondition(trace.appointments[0].value(for: "location") == "Speisesaal")
    precondition(trace.steps.map(\.id) == trace.steps.map(\.id))
    precondition(Set(trace.steps.map(\.id)).count == trace.stages.count)
    let detection = trace.steps.first { $0.stage.name == "detection" }!
    let recognition = trace.steps.first { $0.stage.name == "recognition" }!
    let original = trace.steps.first { $0.stage.name == "decode" }!
    precondition(trace.polygons(for: original).isEmpty)
    precondition(trace.polygons(for: detection).count == 32)
    precondition(trace.polygons(for: recognition).count == 32)
    let first = trace.initialObservations[0]
    precondition(abs(trace.polygons(for: first)[0][0].x - 90.88709677419357) < 0.0001)

    // Detection retains boxes with no decoded text. Reread observations are
    // separate from the first recognition pass; non-page geometry is excluded.
    var regions = json["regions"] as! [[String: Any]]
    var observations = json["observations"] as! [[String: Any]]
    var extra = regions[0]
    extra["id"] = "undecoded"
    extra["kind"] = "uncertain_text"
    regions.append(extra)
    extra["id"] = "reread-region"
    regions.append(extra)
    extra["id"] = "original-frame"
    extra["frame"] = "original"
    regions.append(extra)
    var observation = observations[0]
    observation["id"] = "reread-observation"
    observation["region_ids"] = ["reread-region", "original-frame"]
    observations.append(observation)
    json["regions"] = regions
    json["observations"] = observations
    json["refinement_attempts"] = [
      [
        "id": "retry", "reason": "unclear", "variant": "crop", "status": "complete",
        "detail": "Public geometry probe", "width": 20, "height": 10,
        "crop_to_page": [2, 0, 100, 0, 3, 200, 0, 0, 1],
        "observation_ids": ["reread-observation"],
      ]
    ]
    var stages = json["stages"] as! [[String: Any]]
    stages.append(stages[0])
    json["stages"] = stages
    let refined = try decode()
    precondition(Set(refined.steps.map(\.id)).count == refined.stages.count)
    precondition(refined.polygons(for: detection).count == 33)
    precondition(refined.polygons(for: recognition).count == 32)
    precondition(refined.initialObservations.count == 32)
    precondition(refined.polygons(for: refined.observations.last!).count == 1)
    let polygon = refined.refinementAttempts[0].polygon
    precondition(polygon.count == 4)
    precondition(polygon[0].x == 100 && polygon[0].y == 200)
    precondition(polygon[2].x == 140 && polygon[2].y == 230)
    print(
      "Tracing: decoding, stage identity, original/page frames, detector-only boxes, reread separation and crop transforms passed."
    )
  }
}
