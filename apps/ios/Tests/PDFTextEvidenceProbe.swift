import Foundation
import PDFKit

private final class ObservedPage: PDFPage {
  let count: Int
  let content: String
  private(set) var textReads = 0
  private(set) var geometryReads = 0
  init(count: Int, content: String = "") {
    self.count = count
    self.content = content
    super.init()
  }
  override var numberOfCharacters: Int { count }
  override var string: String? {
    textReads += 1
    return content
  }
  override func characterBounds(at index: Int) -> CGRect {
    geometryReads += 1
    return CGRect(x: index, y: 10, width: 1, height: 1)
  }
}

@main struct PDFTextEvidenceProbe {
  static func main() throws {
    let oversized = ObservedPage(count: PDFTextEvidence.maximumCharacters + 1)
    try rejects(oversized)
    precondition(oversized.textReads == 0 && oversized.geometryReads == 0)
    let inconsistent = ObservedPage(count: 1, content: String(repeating: "A", count: 50_001))
    try rejects(inconsistent)
    precondition(inconsistent.geometryReads == 0)
    let unicode = ObservedPage(count: 3, content: "Ä😀")
    let unicodeEvidence = try PDFTextEvidence(page: unicode)
    precondition(unicodeEvidence.text == "Ä😀" && unicodeEvidence.characters.count == 3)
    let empty = try PDFTextEvidence(page: ObservedPage(count: 0))
    precondition(empty.text.isEmpty && empty.characters.isEmpty)

    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    for (name, count) in [("boundary", 50_000), ("oversized", 100_000)] {
      let url = root.appendingPathComponent(name + ".pdf")
      let original = try Data(contentsOf: url)
      precondition(original.count < 1024, "Fixture must exercise a compressed text layer")
      let document = PDFDocument(url: url)!
      let page = document.page(at: 0)!
      precondition(page.numberOfCharacters == count)
      if count > PDFTextEvidence.maximumCharacters {
        try rejects(page)
      } else {
        let evidence = try PDFTextEvidence(page: page)
        precondition(evidence.text.utf16.count == count && evidence.characters.count == count)
        precondition(evidence.characters.last?["index"] as? Int == count - 1)
      }
      let unchanged = try Data(contentsOf: url)
      precondition(unchanged == original, "Evidence extraction modified the original")
    }
    print(
      "PDF evidence: complete boundary, compressed oversized layer, UTF-16 and original retention passed."
    )
  }

  private static func rejects(_ page: PDFPage) throws {
    do {
      _ = try PDFTextEvidence(page: page)
      preconditionFailure("Oversized PDF text was accepted")
    } catch is PDFTextEvidence.TextLimitError {}
  }
}
