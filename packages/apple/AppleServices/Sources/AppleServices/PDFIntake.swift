import Foundation
import PDFKit
import UIKit

/// PDFKit is another source of text evidence. Its text layer is retained with
/// page coordinates; the portable OCR remains active until evaluation approves
/// a policy for using this additional reader.
public enum PDFIntake {
  public struct Page: Sendable {
    public let png: Data
    public let evidence: String
  }
  public static func pageCount(_ url: URL) throws -> Int {
    guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
      throw IntakeError.unreadable
    }
    guard document.pageCount <= 12 else { throw IntakeError.tooManyPages }
    return document.pageCount
  }
  public static func render(_ url: URL, index: Int) throws -> Page {
    try autoreleasepool {
      guard let document = PDFDocument(url: url), !document.isLocked,
        let page = document.page(at: index)
      else { throw IntakeError.unreadable }
      let bounds = page.bounds(for: .mediaBox)
      guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0
      else { throw IntakeError.unreadable }
      let scale = min(3.0, 2560 / max(bounds.width, bounds.height))
      let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      let image = page.thumbnail(of: size, for: .mediaBox)
      guard let png = image.pngData() else { throw IntakeError.unreadable }
      var characters: [[String: Any]] = []
      let text = page.string ?? ""
      // Keep UTF-16 indices: PDFKit's character geometry uses NSString
      // indexing. Bounds are in PDF page coordinates, not image pixels.
      for i in 0..<min(page.numberOfCharacters, 50_000) {
        let rect = page.characterBounds(at: i)
        if rect.isNull || rect.isInfinite { continue }
        characters.append([
          "index": i, "x": rect.origin.x, "y": rect.origin.y, "width": rect.width,
          "height": rect.height,
        ])
      }
      let evidence: [String: Any] = [
        "schema_version": 1, "reader": "PDFKit", "verified": false, "page_index": index,
        "text": text, "characters": characters,
        "coordinate_space": "PDF mediaBox, lower-left origin", "rotation": page.rotation,
        "media_box": [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height],
        "raster_width": image.cgImage?.width ?? 0, "raster_height": image.cgImage?.height ?? 0,
      ]
      let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
      return Page(png: png, evidence: String(decoding: data, as: UTF8.self))
    }
  }
  private enum IntakeError: LocalizedError {
    case unreadable, tooManyPages
    var errorDescription: String? {
      switch self {
      case .unreadable: "PDF ist gesperrt oder nicht lesbar. Die Originaldatei bleibt gespeichert."
      case .tooManyPages:
        "Ein Plan kann bis zu zwölf PDF-Seiten enthalten. Die Originaldatei bleibt gespeichert."
      }
    }
  }
}
