import Foundation
import RehaCore

private actor EvidenceFixture {
  var pages = ["a": "09:00 Physiotherapie Raum 2.14", "b": "10:00 Physiotherapie Raum 3.12"]
  var changed = false
  var reads = 0
  func remove() { pages = [:] }
  func armChange() { changed = true }
  func list() -> [PlanSummary] {
    ["a", "b"].filter { pages[$0] != nil }.map {
      PlanSummary(
        id: $0, importedAt: 0, pageIds: [$0], itemCount: 1, dates: ["2026-09-27"],
        status: .readyForReview)
    }
  }
  func read(_ request: PlanEvidenceRequest) throws -> PlanEvidenceResponse {
    reads += 1
    guard let text = pages[request.documentId] else { throw AppError.ExpiredScan }
    if changed && request.expectedRevision != nil { throw AppError.StaleRevision }
    return PlanEvidenceResponse(
      documentId: request.documentId, revision: "revision", sourceHash: "hash",
      observedAt: 1,
      excerpts: [PlanEvidenceExcerpt(id: "o1", text: text, regionIds: ["r1"], uncertain: false)],
      fields: [], truncated: false, completePageConfirmed: true)
  }
}

@main struct PlanEvidenceProbe {
  @MainActor static func main() async throws {
    let fixture = EvidenceFixture()
    let conversation = PlanEvidenceConversation(
      access: PlanEvidenceAccess(
        list: { await fixture.list() }, read: { try await fixture.read($0) }))
    let choice = try await conversation.answer(PlanEvidenceQuery())
    precondition(choice.sources.isEmpty && choice.text.contains("Welchen"))
    let answer = try await conversation.answer(PlanEvidenceQuery(source: 1))
    precondition(answer.sources[0].documentId == "a" && answer.text.contains("09:00"))
    let comparison = try await conversation.answer(PlanEvidenceQuery(source: 1, comparison: 2))
    precondition(comparison.sources.count == 2 && comparison.text.contains("Textvergleich"))
    precondition(!comparison.text.contains("Termin gelöscht"))
    await fixture.armChange()
    do {
      _ = try await conversation.answer(PlanEvidenceQuery(source: 1, comparison: 2))
      preconditionFailure("Changed first source accepted during comparison")
    } catch AppError.StaleRevision {}
    await fixture.remove()
    let missing = try await conversation.answer(PlanEvidenceQuery(source: 1))
    precondition(missing.sources.isEmpty && missing.text.contains("geändert"))
    precondition(PlanEvidenceQuery.direct("Was steht in meinem Plan?") != nil)
    precondition(PlanEvidenceQuery.direct("vergleiche Plan 1 mit Plan 2")?.comparison == 2)
    precondition(PlanEvidenceQuery.direct("lösche Plan 1") == nil)
    print(
      "Plan evidence: source clarification, literal excerpts, revision-bound comparison, removal, bounded references and read-only routing passed"
    )
  }
}
