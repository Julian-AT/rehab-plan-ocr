import Foundation
import PDFKit

@main struct DisplayPDFProbe {
  @MainActor static func main() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let source = PDFDocument()
    source.insert(PDFPage(), at: 0)
    guard let original = source.dataRepresentation() else { fatalError("PDF fixture unavailable") }
    try original.write(to: url)
    let opened = try await DisplayPDF.load(url)
    precondition(opened.pageCount == 1 && opened !== source)
    let retained = try Data(contentsOf: url)
    precondition(retained == original)

    let began = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    var delivered: PDFDocument?
    let loading = Task { @MainActor in
      delivered = try await DisplayPDF.load(url) { url in
        began.continuation.yield(())
        precondition(
          release.wait(timeout: .now() + 5) == .success, "PDF opening blocked the UI actor")
        return PDFDocument(url: url)!
      }
    }
    var iterator = began.stream.makeAsyncIterator()
    await iterator.next()
    precondition(delivered == nil)
    release.signal()
    try await loading.value
    precondition(delivered?.pageCount == 1)

    let cancelledBegan = AsyncStream<Void>.makeStream()
    let cancelledRelease = DispatchSemaphore(value: 0)
    var publishedAfterDismissal = false
    let cancelled = Task { @MainActor in
      _ = try await DisplayPDF.load(url) { url in
        cancelledBegan.continuation.yield(())
        precondition(cancelledRelease.wait(timeout: .now() + 5) == .success)
        return PDFDocument(url: url)!
      }
      publishedAfterDismissal = true
    }
    var cancelledIterator = cancelledBegan.stream.makeAsyncIterator()
    await cancelledIterator.next()
    cancelled.cancel()
    cancelledRelease.signal()
    do {
      try await cancelled.value
      fatalError("Cancelled document was delivered")
    } catch is CancellationError {}
    precondition(!publishedAfterDismissal)

    try Data("invalid PDF".utf8).write(to: url)
    do {
      _ = try await DisplayPDF.load(url)
      fatalError("Unreadable PDF was accepted")
    } catch is CocoaError {}
    print(
      "PDF display: source retained, responsive main actor, ownership transfer and cancellation passed"
    )
  }
}
