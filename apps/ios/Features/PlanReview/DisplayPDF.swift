import Foundation
import PDFKit

enum DisplayPDF {
  /// A fresh document is initialized on the concurrent executor, then its sole
  /// ownership transfers to the caller. PDFKit never needs Sendable conformance.
  @concurrent static func load(
    _ url: URL,
    open: @Sendable (URL) throws -> sending PDFDocument = openDocument
  ) async throws -> sending PDFDocument {
    try Task.checkCancellation()
    let document = try open(url)
    try Task.checkCancellation()
    return document
  }

  private static func openDocument(_ url: URL) throws -> sending PDFDocument {
    guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
    return document
  }
}
