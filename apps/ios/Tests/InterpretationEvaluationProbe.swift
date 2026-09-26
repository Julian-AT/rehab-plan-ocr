import Foundation

@main struct InterpretationEvaluationProbe {
  @MainActor static func main() async throws {
    let sample = InterpretationEvaluation.Sample(
      id: "synthetic", text: "Und danach?", today: "2031-05-15", timezone: "Europe/Vienna",
      references: ["r1"], selected: "r1")
    let fixture = URL(fileURLWithPath: "ml/evaluation/conversation/fixtures/native-contract.json")
    let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: Any]]
    for row in rows where row["valid"] as! Bool {
      let text = row["json"] as! String
      let value = try AssistantInterpretation.decode(
        text, references: ["r1"], timezone: sample.timezone)
      let actual = try InterpretationEvaluation.operation(value, sample: sample)
      let expected = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! NSDictionary
      precondition(
        NSDictionary(dictionary: actual) == expected, "Lost compact fields: \(row["id"]!)")
    }
    let rules = CalendarRulesProvider()
    let result = try await rules.interpret(sample.request())
    let operation = try InterpretationEvaluation.operation(result, sample: sample)
    precondition(
      NSDictionary(dictionary: operation) == [
        "action": "calendar", "query": ["detail": "next", "reference": "r1"],
      ] as NSDictionary)
    var changed = result
    changed.query?.offset = 5
    changed.query?.title = "Gymnastik"
    changed.query?.days = 3
    let preserved =
      try InterpretationEvaluation.operation(changed, sample: sample)["query"] as! [String: Any]
    precondition(preserved["offset"] as? Int == 5 && preserved["days"] as? Int == 3)
    precondition(preserved["title"] as? String == "Gymnastik")
    for bad in [
      InterpretationEvaluation.Fixture(runID: "stale", mode: "rules", cases: [sample]),
      InterpretationEvaluation.Fixture(runID: "current", mode: "unknown", cases: [sample]),
      InterpretationEvaluation.Fixture(runID: "current", mode: "rules", cases: []),
      InterpretationEvaluation.Fixture(runID: "current", mode: "rules", cases: [sample, sample]),
      InterpretationEvaluation.Fixture(
        runID: "current", mode: "rules",
        cases: [
          .init(
            id: "bad", text: "Frage", today: "2031-02-29", timezone: sample.timezone,
            references: ["r1"], selected: "r1")
        ]),
      InterpretationEvaluation.Fixture(
        runID: "current", mode: "rules",
        cases: [
          .init(
            id: "bad", text: "Frage", today: sample.today, timezone: sample.timezone,
            references: ["r1", "r2"], selected: "r1")
        ]),
    ] {
      do {
        try bad.validate(runID: "current")
        preconditionFailure("Lossy or stale fixture accepted")
      } catch InterpretationError.invalidRequest {}
    }
    print(
      "App evaluation passed: compact round trips, unique reference resolution, extra constraints and fixture rejection"
    )
  }
}
