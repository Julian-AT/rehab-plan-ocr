import Foundation
import RehaCore

struct PlanEvidenceQuery: Sendable {
  var source: Int?
  var comparison: Int?
  var search = ""
  var latest = false
  func validate() throws {
    guard source.map({ (1...5).contains($0) }) ?? true,
      comparison.map({ (1...5).contains($0) && $0 != source }) ?? true,
      comparison == nil || source != nil, search.count <= 160,
      !latest || (source == nil && comparison == nil)
    else { throw InterpretationError.invalidRequest }
  }
  static func direct(_ text: String) -> Self? {
    let words = VoiceRules.normalized(text).trimmingCharacters(in: .punctuationCharacters)
    if ["was steht in meinem plan", "was steht auf meinem plan", "was sagt mein plan"].contains(
      words)
    {
      return Self()
    }
    if words == "was steht im neuesten plan" { return Self(latest: true) }
    if let match = VoiceRules.matches(
      #"^(?:was steht in |was steht auf )?plan ([1-5])(?: zu (.{1,160}))?$"#, words
    ).first {
      return Self(source: Int(match[1]), search: match.count > 2 ? match[2] : "")
    }
    if let match = VoiceRules.matches(#"^vergleiche plan ([1-5]) mit plan ([1-5])$"#, words).first,
      match[1] != match[2]
    {
      return Self(source: Int(match[1]), comparison: Int(match[2]))
    }
    return nil
  }
}

struct PlanEvidenceAccess {
  let list: @Sendable () async throws -> [PlanSummary]
  let read: @Sendable (PlanEvidenceRequest) async throws -> PlanEvidenceResponse
}

/// References are app-assigned positions in a bounded source catalog. Subsequent
/// replies recheck source identity/revision; a new import cannot renumber them.
@MainActor final class PlanEvidenceConversation {
  struct Answer {
    let text: String
    var sources: [PlanEvidenceResponse] = []
  }
  private let access: PlanEvidenceAccess
  private var catalog: [PlanSummary] = []
  init(access: PlanEvidenceAccess) { self.access = access }
  func context() -> [[String: String]] {
    catalog.enumerated().map {
      ["reference": "p\($0.offset + 1)", "date": $0.element.dates.joined(separator: ", ")]
    }
  }
  func answer(_ query: PlanEvidenceQuery) async throws -> Answer {
    try query.validate()
    try Task.checkCancellation()
    let available = try await access.list()
    try Task.checkCancellation()
    guard available.count <= 5 else { throw InterpretationError.invalidRequest }
    if catalog.isEmpty || query.latest { catalog = available }
    guard !catalog.isEmpty else {
      return Answer(text: "Es ist kein gespeicherter Papierplan verfügbar.")
    }
    let position = query.source ?? ((catalog.count == 1 || query.latest) ? 1 : nil)
    guard let position else {
      return Answer(
        text: "Welchen gespeicherten Plan meinst du? "
          + catalog.enumerated().map {
            "Plan \($0.offset + 1): \($0.element.dates.isEmpty ? "ohne erkanntes Datum" : $0.element.dates.joined(separator: ", "))."
          }.joined(separator: " "))
    }
    let positions = [position, query.comparison].compactMap { $0 }
    var snapshots: [[PlanEvidenceResponse]] = []
    for number in positions {
      guard catalog.indices.contains(number - 1) else { throw InterpretationError.invalidRequest }
      let selected = catalog[number - 1]
      guard available.contains(where: { $0.id == selected.id && $0.pageIds == selected.pageIds })
      else {
        catalog = []
        return Answer(
          text: "Die gespeicherten Quellen haben sich geändert. Bitte den Plan erneut auswählen.")
      }
      guard !selected.pageIds.isEmpty, selected.pageIds.count <= 6 else {
        return Answer(
          text: "Bitte diesen mehrseitigen Plan im Archiv öffnen und die gewünschte Seite prüfen.")
      }
      var pages: [PlanEvidenceResponse] = []
      for page in selected.pageIds {
        let result = try await access.read(
          PlanEvidenceRequest(
            documentId: page, expectedRevision: nil, search: query.search))
        try Task.checkCancellation()
        guard result.documentId == page else { throw InterpretationError.invalidRequest }
        pages.append(result)
      }
      snapshots.append(pages)
    }
    // The two reads of a comparison must not straddle an unobserved revision.
    if snapshots.count == 2 {
      for page in snapshots[0] {
        _ = try await access.read(
          PlanEvidenceRequest(
            documentId: page.documentId,
            expectedRevision: page.revision, search: query.search))
        try Task.checkCancellation()
      }
    }
    let sources = snapshots.flatMap { $0 }
    func excerpts(_ pages: [PlanEvidenceResponse]) -> [String] {
      pages.flatMap { $0.excerpts.map(\.text) }
    }
    let text: String
    if snapshots.count == 2 {
      let first = excerpts(snapshots[0])
      let second = excerpts(snapshots[1])
      // OCR may reorder rows or split lines: differences are text evidence only,
      // never asserted appointment additions, removals or calendar changes.
      let removed = first.filter { !second.contains($0) }
      let added = second.filter { !first.contains($0) }
      if removed.isEmpty && added.isEmpty {
        text =
          "Die gelesenen Textausschnitte stimmen überein. Das belegt nicht, dass die vollständigen Pläne identisch sind."
      } else {
        text =
          "Textvergleich der gespeicherten Quellen: "
          + "Nur in Plan \(positions[0]): \(removed.prefix(3).joined(separator: "; ")). "
          + "Nur in Plan \(positions[1]): \(added.prefix(3).joined(separator: "; ")). "
          + "Dies sind Unterschiede im erkannten Text; bitte die Originale prüfen."
      }
    } else {
      let rows = sources.enumerated().flatMap { pageIndex, source in
        source.excerpts.map {
          "Seite \(pageIndex + 1), Quelle \($0.id): „\($0.text)“\($0.uncertain ? " (Erkennung unsicher)" : "")"
        }
      }
      text =
        rows.isEmpty
        ? "In der aufbewahrten Erkennung wurde dazu kein Text gefunden."
        : "Im gespeicherten Papierplan wurde erkannt: " + rows.prefix(5).joined(separator: ". ")
    }
    let uncertain = sources.contains {
      $0.fields.contains { [.unreviewed, .illegible, .cropped, .contradictory].contains($0.state) }
    }
    let partial =
      sources.contains { $0.truncated || !$0.completePageConfirmed }
      || sources.reduce(0, { $0 + $1.excerpts.count }) > 5
    return Answer(
      text: String(text.prefix(3_000))
        + (partial ? " Die Auskunft ist ein begrenzter Ausschnitt des gespeicherten Plans." : "")
        + (uncertain
          ? " Einige Felder sind ungeprüft, unleserlich, abgeschnitten oder widersprüchlich." : ""),
      sources: sources)
  }
}
