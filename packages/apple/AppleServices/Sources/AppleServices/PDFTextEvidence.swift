import Foundation
import PDFKit

/// Bounds the expanded text layer, independently of the compressed file size.
/// Evidence is complete within this limit; oversized pages are never truncated.
struct PDFTextEvidence {
  static let maximumCharacters = 50_000
  let text: String
  let characters: [[String: Any]]

  init(page: PDFPage) throws {
    let count = page.numberOfCharacters
    guard (0...Self.maximumCharacters).contains(count) else { throw TextLimitError() }
    let text = page.string ?? ""
    // PDFKit exposes NSString-based text and character indices. Also validate
    // the returned text before constructing its per-character evidence.
    guard text.utf16.count <= Self.maximumCharacters else { throw TextLimitError() }
    var characters: [[String: Any]] = []
    for i in 0..<count {
      let rect = page.characterBounds(at: i)
      if rect.isNull || rect.isInfinite { continue }
      characters.append([
        "index": i, "x": rect.origin.x, "y": rect.origin.y, "width": rect.width,
        "height": rect.height,
      ])
    }
    self.text = text
    self.characters = characters
  }

  struct TextLimitError: LocalizedError {
    var errorDescription: String? {
      "Die PDF-Seite enthält zu viel Text. Bitte den Plan in kleineren Abschnitten importieren. Die Originaldatei bleibt gespeichert."
    }
  }
}
